#!/bin/bash
# This script builds the development container image. It supports building specific Dockerfile targets and optional post-build tests.

# build-container.sh - Build and optionally test the dev container

set -e

CONTAINER_NAME="dev-container"
IMAGE_TAG="latest"
BUILD_TARGET="full" # Default to full build
DEBUG_MODE=""
CACHE_REGISTRY=""
CACHE_MODE=""

# Helpers to reduce duplication in docker run checks
run_in_container() {
    local my_cmd="$1"
    docker run --rm "${CONTAINER_NAME}:${IMAGE_TAG}" bash -lc "$my_cmd"
}

check_cmd() {
    local my_description="$1"
    local my_cmd="$2"
    echo "$my_description"
    if run_in_container "$my_cmd" >/dev/null 2>&1; then
        return 0
    else
        echo "⚠️  ${my_description} failed"
        return 1
    fi
}

test_vscode() {
    echo "📦 Testing VS Code server installation..."
    run_in_container "ls -la /home/me/.vscode-server/bin/" || echo "⚠️  VS Code server test failed"
}

test_latex_basic() {
    echo "📄 Testing LaTeX installation..."
    run_in_container "xelatex --version | head -n 1" || echo "⚠️  XeLaTeX test failed"
}

test_pandoc() {
    echo "📄 Testing Pandoc installation and functionality..."
    run_in_container "pandoc --version | head -n 1" || { echo "⚠️  Pandoc version test failed"; return 1; }
    echo "📝 Running comprehensive Pandoc tests (docx, pdf, citations)..."
    if docker run --rm -v "$(pwd)":/workspace -w /workspace "${CONTAINER_NAME}:${IMAGE_TAG}" ./test_pandoc.sh; then
        return 0
    else
        echo "⚠️  Comprehensive Pandoc tests failed"
        return 1
    fi
}

test_pandoc_plus() {
    echo "🔍 Testing tlmgr soul package..."
    run_in_container "kpsewhich soul.sty" || { echo "⚠️ soul.sty missing"; return 1; }
}

test_nvim_and_plugins() {
    echo "📝 Testing nvim and plugins..."
    run_in_container "nvim --version" || { echo "⚠️  nvim not available"; return 1; }
    run_in_container "ls -la /home/me/.local/share/nvim/lazy/" || { echo "⚠️  lazy.nvim plugins not found"; return 1; }
}

test_dev_tools() {
    echo "🛠️  Testing development tools..."
    local my_fail=0
    check_cmd "Checking Yarn..." "yarn --version" || my_fail=1
    check_cmd "Checking fd..." 'env PATH="/home/me/.local/bin:$PATH" fd --version' || my_fail=1
    check_cmd "Checking eza..." "eza --version" || my_fail=1
    # gotests does not support --version; -h confirms presence
    check_cmd "Checking gotests..." 'env GOPATH="/home/me/go" PATH="/home/me/go/bin:/usr/local/go/bin:$PATH" gotests -h >/dev/null' || my_fail=1
    check_cmd "Checking tree-sitter..." 'env PATH="/home/me/.local/bin:$PATH" tree-sitter --version' || my_fail=1
    return $my_fail
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  --base)
    BUILD_TARGET="base"
    IMAGE_TAG="base"
    echo "🚀 Building base image (system tools only)..."
    shift
    ;;
  --base-nvim)
    BUILD_TARGET="base-nvim"
    IMAGE_TAG="base-nvim"
    echo "📝 Building image with nvim plugins installed..."
    shift
    ;;
  --base-nvim-vscode)
    BUILD_TARGET="base-nvim-vscode"
    IMAGE_TAG="base-nvim-vscode"
    echo "🔧 Building image with nvim + VS Code server and extensions..."
    shift
    ;;
  --base-nvim-vscode-tex)
    BUILD_TARGET="base-nvim-vscode-tex"
    IMAGE_TAG="base-nvim-vscode-tex"
    echo "📚 Building image with LaTeX stack (no Pandoc)..."
    shift
    ;;
  --base-nvim-vscode-tex-pandoc)
    BUILD_TARGET="base-nvim-vscode-tex-pandoc"
    IMAGE_TAG="base-nvim-vscode-tex-pandoc"
    echo "📚 Building image with LaTeX + Pandoc..."
    shift
    ;;
  --base-nvim-vscode-tex-pandoc-plus)
    BUILD_TARGET="base-nvim-vscode-tex-pandoc-plus"
    IMAGE_TAG="base-nvim-vscode-tex-pandoc-plus"
    echo "📚➕ Building image with extra LaTeX packages..."
    shift
    ;;
  --full)
    BUILD_TARGET="full"
    IMAGE_TAG="full"
    echo "🏗️  Building full image..."
    shift
    ;;
  --debug)
    DEBUG_MODE="--build-arg DEBUG_PACKAGES=true"
    echo "🐛 Debug mode enabled - R package logs will be shown"
    shift
    ;;
  --test)
    TEST_CONTAINER=true
    shift
    ;;
  --no-cache)
    NO_CACHE="--no-cache"
    shift
    ;;
  --cache-from)
    CACHE_REGISTRY="$2"
    CACHE_MODE="--cache-from type=registry,ref=${CACHE_REGISTRY}/cache"
    echo "🗂️  Using registry cache from: ${CACHE_REGISTRY}/cache"
    shift 2
    ;;
  --cache-to)
    CACHE_REGISTRY="$2"
    CACHE_MODE="--cache-to type=registry,ref=${CACHE_REGISTRY}/cache,mode=max"
    echo "💾 Pushing cache to: ${CACHE_REGISTRY}/cache"
    shift 2
    ;;
  --cache-from-to)
    CACHE_REGISTRY="$2"
    CACHE_MODE="--cache-from type=registry,ref=${CACHE_REGISTRY}/cache --cache-to type=registry,ref=${CACHE_REGISTRY}/cache,mode=max"
    echo "🔄 Using and updating registry cache: ${CACHE_REGISTRY}/cache"
    shift 2
    ;;
  -h | --help)
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Stage Options:"
    echo "  --base                               Build only the base stage (system tools only)"
    echo "  --base-nvim                          Build base + nvim with plugins installed"
    echo "  --base-nvim-vscode                   Build base + nvim + VS Code server and extensions"
    echo "  --base-nvim-vscode-tex               Build base + nvim + VS Code + LaTeX (no Pandoc)"
    echo "  --base-nvim-vscode-tex-pandoc        Build base + nvim + VS Code + LaTeX + Pandoc"
    echo "  --base-nvim-vscode-tex-pandoc-plus   Build base + nvim + VS Code + LaTeX + Pandoc + extra packages"
    echo "  --full                               Build the full stage"
    echo ""
    echo "Other Options:"
    echo "  --debug                              Show verbose R package installation logs (default: quiet)"
    echo "  --test                               Run tests after building"
    echo "  --no-cache                           Build without using Docker cache"
    echo "  --cache-from <registry>              Use registry cache from specified registry (e.g., ghcr.io/user/repo)"
    echo "  --cache-to <registry>                Push cache to specified registry"
    echo "  --cache-from-to <registry>           Use and update registry cache"
    echo "  -h, --help                           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --base                         # Quick build for testing base system"
    echo "  $0 --base-nvim                    # Build with nvim plugins installed"
    echo "  $0 --base-nvim-vscode --test      # Build with nvim + VS Code and test it"
    echo "  $0 --full --no-cache              # Full clean build"
    echo "  $0 --full --cache-from-to ghcr.io/user/repo  # Use registry cache"
    exit 0
    ;;
  *)
    echo "Unknown option $1"
    echo "Use --help for usage information"
    exit 1
    ;;
  esac
done

echo "🏗️  Building dev container image (target: ${BUILD_TARGET})..."

# Use target-specific cache keys for better cache isolation
TARGET_CACHE_MODE=""
if [ -n "$CACHE_REGISTRY" ]; then
  if [[ "$CACHE_MODE" == *"--cache-from"* ]]; then
    TARGET_CACHE_MODE="--cache-from type=registry,ref=${CACHE_REGISTRY}/cache:${BUILD_TARGET}"
  fi
  if [[ "$CACHE_MODE" == *"--cache-to"* ]]; then
    TARGET_CACHE_MODE="${TARGET_CACHE_MODE} --cache-to type=registry,ref=${CACHE_REGISTRY}/cache:${BUILD_TARGET},mode=max"
  fi
else
  TARGET_CACHE_MODE="$CACHE_MODE"
fi

# Use docker buildx for better caching support
docker buildx build ${NO_CACHE} ${DEBUG_MODE} ${TARGET_CACHE_MODE} \
  --progress=plain \
  --target "${BUILD_TARGET}" \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  -t "${CONTAINER_NAME}:${IMAGE_TAG}" \
  .

echo "✅ Container built successfully!"

# Optionally test the container
if [ "$TEST_CONTAINER" = "true" ]; then
  echo "🧪 Testing container..."
  TEST_FAIL=0

  echo "🔧 Testing basic system tools..."
  run_in_container "which zsh"
  run_in_container "R --version"

  if [ "$BUILD_TARGET" = "base-nvim-vscode" ] || [ "$BUILD_TARGET" = "full" ]; then
    test_vscode || TEST_FAIL=1
  fi

  # LaTeX presence by stages
  if [ "$BUILD_TARGET" = "base-nvim-vscode-tex" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-plus" ] || [ "$BUILD_TARGET" = "full" ]; then
    test_latex_basic || TEST_FAIL=1

    if [ "$BUILD_TARGET" = "base-nvim-vscode-tex" ]; then
      echo "🚫 Verifying Pandoc is NOT installed in tex stage..."
      if run_in_container "which pandoc"; then
        echo "⚠️  Pandoc found but should not be in tex stage"
        TEST_FAIL=1
      else
        echo "✅ Pandoc correctly absent from tex stage"
      fi
    fi
  fi

  # Pandoc tests
  if [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-plus" ] || [ "$BUILD_TARGET" = "full" ]; then
    test_pandoc || TEST_FAIL=1
  fi

  # Extra LaTeX packages
  if [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-plus" ] || [ "$BUILD_TARGET" = "full" ]; then
    test_pandoc_plus || TEST_FAIL=1
  fi

  echo "📋 Checking for copied configuration files..."
  run_in_container 'ls -la /home/me/ | grep -E "\.(zprofile|tmux\.conf|lintr|Rprofile|bash_profile|npmrc)$"'

  # nvim stages and later
  if [ "$BUILD_TARGET" = "base-nvim" ] || [ "$BUILD_TARGET" = "base-nvim-vscode" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-plus" ] || [ "$BUILD_TARGET" = "full" ]; then
    test_nvim_and_plugins || TEST_FAIL=1
  fi

  test_dev_tools || TEST_FAIL=1

  if [ "$BUILD_TARGET" = "full" ]; then
    echo "📦 Testing R package installation..."
    if ! run_in_container 'R -e "cat(\"Installed packages:\", length(.packages(all.available=TRUE)), \"\n\")"'; then
      TEST_FAIL=1
    fi
  fi

  if [ "$TEST_FAIL" -eq 0 ]; then
    echo "✅ Container tests passed!"
  else
    echo "❌ Container tests failed"
    exit 1
  fi
fi

echo "🎉 Done! You can now:"
case "$BUILD_TARGET" in
"base")
  echo "  • Test the base stage with: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Build with nvim plugins next with: ./build-container.sh --base-nvim"
  ;;
"base-nvim")
  echo "  • Test the base-nvim stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test nvim with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} nvim --version"
  echo "  • Build with VS Code next with: ./build-container.sh --base-nvim-vscode"
  ;;
"base-nvim-vscode")
  echo "  • Test the base-nvim-vscode stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test VS Code with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} ls -la /home/me/.vscode-server/bin/"
  echo "  • Build with LaTeX next with: ./build-container.sh --base-nvim-vscode-tex"
  ;;
"base-nvim-vscode-tex")
  echo "  • Test the base-nvim-vscode-tex stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test LaTeX with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} xelatex --version | head -n 1"
  echo "  • Build with LaTeX + Pandoc next with: ./build-container.sh --base-nvim-vscode-tex-pandoc"
  ;;
"base-nvim-vscode-tex-pandoc")
  echo "  • Test the base-nvim-vscode-tex-pandoc stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test Pandoc with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} pandoc --version | head -n 1"
  echo "  • Build with extra LaTeX packages next with: ./build-container.sh --base-nvim-vscode-tex-pandoc-plus"
  ;;
"base-nvim-vscode-tex-pandoc-plus")
  echo "  • Test the base-nvim-vscode-tex-pandoc-plus stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test soul package with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} kpsewhich soul.sty"
  echo "  • Build the texlive-full version with: ./build-container.sh --full"
  ;;
"full")
  echo "  • Test the full stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Tag and push to GitHub Container Registry:"
  echo "    docker tag ${CONTAINER_NAME}:${IMAGE_TAG} ghcr.io/jbearak/${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "    docker push ghcr.io/jbearak/${CONTAINER_NAME}:${IMAGE_TAG}"
  ;;
esac
echo "  • Reference in other projects' devcontainer.json files"
