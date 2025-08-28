#!/usr/bin/env bash
# Unified build script with daemonless fallback
# Purpose: Build targets (full | r-ci) for host or amd64.
# Features:
#   * Uses classic docker / buildx when daemon available.
#   * Falls back to rootless BuildKit (buildctl) when daemon absent AND output mode
#     does not require loading into local daemon.
#   * Output modes: load (default), oci (OCI layout dir), tar (docker save archive).
#   * Adds --output flag to select mode; load requires a running docker daemon.
#   * Multi-platform manifest creation remains responsibility of push-to-ghcr.sh.
#
# Usage examples:
#   ./build.sh r-ci                 # host arch, load into daemon (if running)
#   ./build.sh --amd64 r-ci         # cross-build (load if daemon; else advise)
#   ./build.sh --output oci r-ci    # produce r-ci-<arch>.oci (no daemon needed)
#   ./build.sh --output tar r-ci    # produce r-ci-<arch>.tar (no daemon needed)
#   R_BUILD_JOBS=4 ./build.sh --output oci --amd64 r-ci
#   ./build.sh --no-cache --debug full
#
# Environment:
#   R_BUILD_JOBS (default 2)  Parallel R package compile jobs.
#   EXPORT_TAR=1              (deprecated) still respected; equivalent to --output tar.
#   TAG_SUFFIX                Extra suffix for local tag (e.g. -dev).
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[INFO]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
err(){ echo -e "${RED}[ERR]${NC} $*" >&2; }
succ(){ echo -e "${GREEN}[OK]${NC} $*"; }

usage(){ cat <<EOF
Unified build script (docker + rootless buildctl fallback)

Usage: $0 [--amd64] [--no-cache] [--debug] [--no-fallback] [--output load|oci|tar] <full|r-ci>

Options:
  --amd64              Build linux/amd64 (uses buildx or buildctl if cross-arch).
  --no-cache           Disable Docker build cache.
  --debug              Pass DEBUG_PACKAGES=true (verbose R package logs) to Dockerfile.
  --output <mode>      load (default), oci (directory), tar (docker archive). Load requires daemon.
  --no-fallback        Do NOT attempt buildctl rootless fallback; fail instead.
  -h, --help           Show help.

Environment:
  R_BUILD_JOBS (default 2)  Parallel R package compile jobs.
  TAG_SUFFIX                Extra suffix for local tag (e.g. -dev).
  EXPORT_TAR=1              Deprecated shortcut for --output tar.
  AUTO_INSTALL_BUILDKIT=1   Permit script to apt-get install buildkit if buildctl missing.
  BUILDKIT_HOST             Remote buildkit address (e.g. tcp://buildkitd:1234) for buildctl.
  BUILDKIT_PROGRESS=plain   Control buildctl progress output (default fancy, plain better for CI logs).
  IGNORE_RAM_CHECK=1        Override 32GB RAM requirement for full (use with caution).

Examples:
  ./build.sh full
  ./build.sh --output oci r-ci
  ./build.sh --amd64 --output tar r-ci
  R_BUILD_JOBS=6 ./build.sh --debug --output oci full
EOF
}

# Defaults
FORCE_AMD64=false
NO_CACHE=false
DEBUG_PACKAGES=false
OUTPUT_MODE=load
OUTPUT_EXPLICIT=false
FALLBACK_ENABLED=true
TARGET=""
OUT_SPEC=""   # predeclare to satisfy set -u; only populated for oci/tar outputs
OUT_DEST=""   # ditto

while [[ $# -gt 0 ]]; do
  case "$1" in
  --amd64) FORCE_AMD64=true; shift;;
  --no-cache) NO_CACHE=true; shift;;
  --debug) DEBUG_PACKAGES=true; shift;;
  --output) OUTPUT_MODE="$2"; OUTPUT_EXPLICIT=true; shift 2;;
  --no-fallback) FALLBACK_ENABLED=false; shift;;
    -h|--help) usage; exit 0;;
    full|r-ci) TARGET="$1"; shift;;
    *) err "Unknown argument: $1"; usage; exit 1;;
  esac
done

if [ -z "$TARGET" ]; then
  usage; err "Target required"; exit 1
fi

# Check memory requirements for full
if [ "$TARGET" = "full" ]; then
  TOTAL_RAM_GB=0
  
  # Detect OS and use appropriate memory detection method
  if [ "$(uname)" = "Darwin" ]; then
    # macOS - use sysctl to get memory in bytes, convert to GB
    if command -v sysctl >/dev/null 2>&1; then
      TOTAL_RAM_BYTES=$(sysctl -n hw.memsize 2>/dev/null)
      if [ -n "$TOTAL_RAM_BYTES" ] && [ "$TOTAL_RAM_BYTES" -gt 0 ]; then
        TOTAL_RAM_GB=$((TOTAL_RAM_BYTES / 1024 / 1024 / 1024))
      fi
    fi
  elif [ -r /proc/meminfo ]; then
    # Linux - use /proc/meminfo
    TOTAL_RAM_KB=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
    TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
  fi
  
  if [ "$TOTAL_RAM_GB" -gt 0 ]; then
    # Use 30GB threshold to account for integer truncation (31.3GB → 31GB)
    if [ "$TOTAL_RAM_GB" -lt 30 ]; then
      err "full requires ≥32GB RAM (detected: ${TOTAL_RAM_GB}GB). Use r-ci instead or add swap."
      err "Override with IGNORE_RAM_CHECK=1 if you have sufficient swap configured."
      if [ "${IGNORE_RAM_CHECK:-0}" != "1" ]; then
        exit 2
      fi
      warn "IGNORE_RAM_CHECK=1 set; proceeding despite insufficient RAM (may OOM)"
    else
      info "Detected ${TOTAL_RAM_GB}GB RAM - sufficient for full build"
    fi
  else
    warn "Cannot detect system RAM; proceeding with full build"
  fi
fi

if [ "${EXPORT_TAR:-0}" = "1" ] && [ "$OUTPUT_MODE" = load ]; then
  OUTPUT_MODE=tar
fi

if ! command -v docker >/dev/null 2>&1; then
  warn "docker CLI not found in PATH; will attempt rootless buildctl path (requires buildctl)."
fi

DOCKER_DAEMON_UP=true
if command -v docker >/dev/null 2>&1; then
  if ! docker info >/dev/null 2>&1; then
    DOCKER_DAEMON_UP=false
    warn "Docker daemon not reachable."
  fi
else
  DOCKER_DAEMON_UP=false
fi

case "$OUTPUT_MODE" in
  load|oci|tar) :;;
  *) err "Invalid --output '$OUTPUT_MODE' (expected load|oci|tar)"; exit 1;;
esac

# Detect host arch & potential cross-build BEFORE enforcing daemon requirement so we can auto-switch output.
HOST_ARCH_RAW="$(uname -m)"
case "$HOST_ARCH_RAW" in
  x86_64) HOST_ARCH=amd64;;
  aarch64|arm64) HOST_ARCH=arm64;;
  *) err "Unsupported host arch: $HOST_ARCH_RAW"; exit 4;;
esac

# Determine build platform
if $FORCE_AMD64; then
  BUILD_PLATFORM=linux/amd64
else
  BUILD_PLATFORM="linux/${HOST_ARCH}"
fi

# Decide if buildx is needed (host != target amd64 implies cross-build)
NEED_BUILDX=false
if [ "$BUILD_PLATFORM" = "linux/amd64" ] && [ "$HOST_ARCH" != "amd64" ]; then
  NEED_BUILDX=true
fi

# Auto-adjust default output mode for cross-builds (only if user did not explicitly choose one)
if $NEED_BUILDX && ! $OUTPUT_EXPLICIT && [ "$OUTPUT_MODE" = load ]; then
  OUTPUT_MODE=oci
  info "Auto-selected --output oci for cross-build (safer than load; choose --output load to override)."
fi

# Now that OUTPUT_MODE may have been auto-adjusted, enforce daemon requirement for load mode.
if [ "$OUTPUT_MODE" = load ] && ! $DOCKER_DAEMON_UP; then
  err "--output load requires a running docker daemon. Use --output oci or --output tar instead."; exit 3
fi

# If we still need buildx (cross-build) ensure it's present when using docker path
if $NEED_BUILDX && $DOCKER_DAEMON_UP && [ "$OUTPUT_MODE" = load ] && ! docker buildx version >/dev/null 2>&1; then
  err "buildx required for cross-building to amd64 from $HOST_ARCH. Install Docker buildx or specify --output oci (non-load artifact)."; exit 5
fi

R_BUILD_JOBS="${R_BUILD_JOBS:-2}"
IMAGE_ARCH_SUFFIX=${BUILD_PLATFORM#linux/}
IMAGE_TAG_BASE="${TARGET}-${IMAGE_ARCH_SUFFIX}"
IMAGE_TAG="${IMAGE_TAG_BASE}${TAG_SUFFIX:-}"

BUILD_ARGS=( --target "$TARGET" --build-arg R_BUILD_JOBS="$R_BUILD_JOBS" )
$DEBUG_PACKAGES && BUILD_ARGS+=( --build-arg DEBUG_PACKAGES=true ) || true
$NO_CACHE && BUILD_ARGS+=( --no-cache ) || true

info "Building target=$TARGET platform=$BUILD_PLATFORM tag=$IMAGE_TAG (R_BUILD_JOBS=$R_BUILD_JOBS output=$OUTPUT_MODE)"

if $DOCKER_DAEMON_UP && [ "$OUTPUT_MODE" = load ]; then
  if $NEED_BUILDX; then
    info "Using docker buildx (load)"
    time docker buildx build --platform "$BUILD_PLATFORM" "${BUILD_ARGS[@]}" --load -t "$IMAGE_TAG" .
  else
    time docker build "${BUILD_ARGS[@]}" -t "$IMAGE_TAG" .
  fi
  succ "Built $IMAGE_TAG (loaded into daemon)"
else
  # Non-load outputs or daemonless path
  if $DOCKER_DAEMON_UP && [ "$OUTPUT_MODE" != load ]; then
    # Use docker buildx --output to artifact
    case "$OUTPUT_MODE" in
      oci) OUT_DEST="${IMAGE_TAG}.oci"; OUT_SPEC="type=oci,dest=${OUT_DEST}";;
      tar) OUT_DEST="${IMAGE_TAG}.tar"; OUT_SPEC="type=docker,dest=${OUT_DEST}";;
    esac
    if $NEED_BUILDX; then
      info "Using buildx (artifact export $OUTPUT_MODE)"
      time docker buildx build --platform "$BUILD_PLATFORM" "${BUILD_ARGS[@]}" --output "$OUT_SPEC" -t "$IMAGE_TAG" .
    else
      # docker build cannot directly export oci/tar unless using buildx; fall back to buildx even if not cross
      if docker buildx version >/dev/null 2>&1; then
        info "Using buildx (artifact export $OUTPUT_MODE)"
        time docker buildx build --platform "$BUILD_PLATFORM" "${BUILD_ARGS[@]}" --output "$OUT_SPEC" -t "$IMAGE_TAG" .
      else
        warn "buildx not available; attempting rootless buildctl"
        DOCKER_DAEMON_UP=false
      fi
    fi
    if [ -f "$OUT_DEST" ]; then succ "Exported $OUT_DEST"; fi
  fi
  if ! $DOCKER_DAEMON_UP; then
    # Rootless buildctl path
      if ! $FALLBACK_ENABLED; then
        err "Fallback disabled (--no-fallback). Aborting because docker daemon/load path unavailable."; exit 6
      fi
      if ! command -v buildctl >/dev/null 2>&1; then
        if [ "${AUTO_INSTALL_BUILDKIT:-0}" = "1" ]; then
          warn "buildctl missing; AUTO_INSTALL_BUILDKIT=1 set – attempting apt-get install buildkit"
          if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update -qq && sudo apt-get install -y -qq buildkit || true
          else
            warn "apt-get not available; cannot auto-install buildkit"
          fi
        else
          warn "buildctl not found. Set AUTO_INSTALL_BUILDKIT=1 to allow auto-install (Debian/Ubuntu) or install manually."
        fi
      fi
      if ! command -v buildctl >/dev/null 2>&1; then
        err "buildctl unavailable. Cannot proceed without docker daemon. Install buildkit or start Docker."; exit 6
      fi
    case "$OUTPUT_MODE" in
      oci) OUT_DEST="${IMAGE_TAG}.oci"; OUT_SPEC="type=oci,dest=${OUT_DEST}";;
      tar) OUT_DEST="${IMAGE_TAG}.tar"; OUT_SPEC="type=docker,dest=${OUT_DEST}";;
      load) err "Internal error: load mode should not reach buildctl path"; exit 7;;
    esac
    info "Using rootless buildctl (output=$OUTPUT_MODE)"
      FRONTEND_OPTS=( --opt target="$TARGET" --opt platform="$BUILD_PLATFORM" )
    FRONTEND_OPTS+=( --opt build-arg:R_BUILD_JOBS="$R_BUILD_JOBS" )
    $DEBUG_PACKAGES && FRONTEND_OPTS+=( --opt build-arg:DEBUG_PACKAGES=true ) || true
    $NO_CACHE && FRONTEND_OPTS+=( --no-cache ) || true
      if [ -n "${BUILDKIT_HOST:-}" ]; then
        info "Using remote buildkit host: $BUILDKIT_HOST"
        BUILDKIT_ADDR_FLAG=( --addr "$BUILDKIT_HOST" )
      else
        BUILDKIT_ADDR_FLAG=()
      fi
      : "${BUILDKIT_PROGRESS:=auto}"  # allow override
      time buildctl "${BUILDKIT_ADDR_FLAG[@]}" build \
          --frontend=dockerfile.v0 \
          --local context=. \
          --local dockerfile=. \
          "${FRONTEND_OPTS[@]}" \
          --progress "$BUILDKIT_PROGRESS" \
          --output "$OUT_SPEC"
    if [ -f "$OUT_DEST" ]; then succ "Exported $OUT_DEST"; else err "Expected artifact $OUT_DEST not found"; exit 8; fi
  fi
fi

# When output was oci/tar, image not loaded. Provide guidance; when load we already have tag.
if [ "$OUTPUT_MODE" != load ]; then
  echo "Artifact created: ${OUT_DEST}"; fi

echo
if [ "$OUTPUT_MODE" = load ]; then
  succ "Quick test: docker run --rm $IMAGE_TAG uname -m"
  [ "$TARGET" = "r-ci" ] && echo "Run R: docker run --rm $IMAGE_TAG R -q -e 'sessionInfo()'" || true
  echo "Push (single-arch): docker tag $IMAGE_TAG ghcr.io/OWNER/research-stack:${TARGET#full} && docker push ghcr.io/OWNER/research-stack:..."
else
  succ "Image not loaded (output=$OUTPUT_MODE). Use buildx to load if needed: docker load -i ${OUT_DEST} (tar only)"
  [ "$OUTPUT_MODE" = tar ] && echo "Load later: docker load -i ${OUT_DEST}" || true
fi
echo "For multi-arch distribution use: ./push-to-ghcr.sh -a"
