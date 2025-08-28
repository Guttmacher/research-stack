#!/bin/bash
# Push container images to GitHub Container Registry (GHCR)
#
# WHY THIS SCRIPT EXISTS:
# After building containers locally, you often want to share them with others or use them
# in production. GitHub Container Registry (ghcr.io) is a free service that stores your
# container images and makes them available to anyone (or just your team, if private).
#
# TWO DIFFERENT MODES:
# 1. DEFAULT MODE: Push existing local images (built with build.sh)
#    - Uses the platform-specific images like "full-arm64"
#    - Each image only works on its specific architecture
#
# 2. MULTI-PLATFORM MODE (-a flag): Build and push multi-platform images
#    - Creates images that work on both arm64 AND amd64 automatically
#    - Docker automatically downloads the right version for each user's architecture
#    - Can't be stored locally - must be pushed directly to registry
#
# AUTHENTICATION REQUIRED:
# Before using this script, you must login to GitHub Container Registry:
#   docker login ghcr.io
# Use your GitHub username and a Personal Access Token (not your password)

set -e  # Exit if any command fails

# Configuration - these variables control where images are pushed
# WHY WE USE VARIABLES: This makes it easy to change settings without editing the whole script
REGISTRY="ghcr.io"  # GitHub Container Registry URL
# Auto-detect repository owner from environment (works in GitHub Actions) or default to Guttmacher
REPO_OWNER="${REPO_OWNER:-${GITHUB_REPOSITORY_OWNER:-Guttmacher}}"
# Convert to lowercase for Docker registry compatibility
REPO_OWNER_LOWER=$(echo "$REPO_OWNER" | tr '[:upper:]' '[:lower:]')
REPOSITORY="${REPO_OWNER_LOWER}/research-stack"  # Full repository path: ghcr.io/username/research-stack
DEFAULT_TAG="latest"  # Default tag if none specified
DEFAULT_TARGET="full"  # Default container type if none specified

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Push Docker images to GitHub Container Registry (GHCR)

OPTIONS:
    -t, --target TARGET     Push specific target only (default: push all targets)
                           Available targets: full, r-ci
    -g, --tag TAG          Tag for the image (default: $DEFAULT_TAG)
    -b, --build            Build the image before pushing
    -f, --force            Force push even if image doesn't exist locally
    -a, --all-platforms    Build and push multi-platform images (linux/amd64,linux/arm64)
    -h, --help             Show this help message

EXAMPLES:
    $0                                         # Push all targets (host platform only)
    $0 -a                                      # Build and push all targets (both platforms)
    $0 -t full                       # Push only full (host platform)
    $0 -a -t full                    # Build and push full (both platforms)
    $0 -t r-ci -g v1.0.0              # Push only r-ci:v1.0.0 (host platform)
    $0 -b                                     # Build and push all targets (host platform)
    $0 -a -b                                  # Build and push all targets (both platforms)

PREREQUISITES:
    1. Docker must be installed and running
    2. You must be logged in to GHCR: docker login ghcr.io
    3. You must have push permissions to the repository
    4. For multi-platform builds: docker buildx with multi-platform support

EOF
}

# Function to check if user is logged in to GHCR
# WHY WE CHECK: Pushing to a registry requires authentication. Better to fail early
# with a clear message than get a confusing error during the push.
check_ghcr_login() {
    print_status "Checking GHCR authentication..."
    
    # Check if credentials exist in Docker config
    # This is a basic check - the actual push will verify if credentials work
    if [[ -f ~/.docker/config.json ]] && grep -q "ghcr.io" ~/.docker/config.json 2>/dev/null; then
        print_success "GHCR authentication found in Docker config"
        return 0
    fi
    
    print_error "Not logged in to GHCR. Please run: docker login ghcr.io"
    print_error "Use your GitHub username and a Personal Access Token (not your password)"
    exit 1
}

# Function to get host architecture for consistent naming
# WHY WE NEED THIS: When pushing existing local images, we need to know which
# architecture-specific image to look for (e.g., "full-arm64" vs "full-amd64")
get_host_arch() {
    case "$(uname -m)" in
        x86_64) echo "amd64" ;;      # Intel/AMD processors (most cloud servers, older Macs)
        aarch64|arm64) echo "arm64" ;; # Apple Silicon Macs, ARM servers
        *) 
            # If running on an unsupported architecture, fail with a clear error
            print_error "Unsupported architecture: $(uname -m)"
            print_error "Supported architectures: x86_64, aarch64, arm64"
            exit 1
            ;;
    esac
}

# Function to get display tag for success messages
get_display_tag() {
    local target="$1"
    local tag="$2"
    
    if [[ "$target" == "r-ci" ]]; then
        echo "r-${tag}"
    else
        echo "${tag}"
    fi
}

# Function to check if local image exists
# WHY WE CHECK: Before trying to push an image, we should verify it exists locally.
# This gives a clear error message instead of a confusing Docker error.
check_local_image() {
    local target="$1"  # e.g., "full"
    local tag="$2"     # e.g., "latest" (though we don't use this currently)
    local host_arch=$(get_host_arch)

    # Check for arch-specific naming pattern (e.g., "full-arm64")
    # This is the naming convention used by our build scripts
    local arch_specific_name="${target}-${host_arch}"
    if docker image inspect "${arch_specific_name}" >/dev/null 2>&1; then
        return 0  # Success: image exists
    fi

    return 1  # Failure: image not found
}

build_image() {
    local target="$1"
    local tag="$2"
    print_status "Building image for target: $target via unified build.sh"
    if [[ -f ./build.sh ]]; then
        case "$target" in
          full) ./build.sh full ;;
          r-ci)    ./build.sh r-ci    ;;
          *) print_error "Unknown target: $target"; return 1;;
        esac
    else
        print_status "Fallback docker build (build.sh missing)"
        docker build --target "$target" -t "${target}-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/;s/arm64/arm64/')" .
    fi
    print_success "Build completed for target: $target"
}

# Function to push a local image to the registry
# WHY THIS IS COMPLEX: We need to handle different naming conventions and tag formats
# for different container types (full vs r-ci)
push_image() {
    local target="$1"   # e.g., "full" or "r-ci"
    local tag="$2"      # e.g., "latest"
    local force="$3"    # "true" if user wants to force push without local image
    local host_arch=$(get_host_arch)
    
    # Determine the registry image name based on target
    local image_name
    if [[ "$target" == "full" ]]; then
        image_name="full"
    elif [[ "$target" == "r-ci" ]]; then
        image_name="r-ci"
    else
        print_error "Unknown target: $target"
        return 1
    fi
    
    local remote_image="${REGISTRY}/${REPOSITORY}/${image_name}:${tag}"
    
    # Check if local image exists (unless forcing)
    if ! check_local_image "$target" "$tag" && [[ "$force" != "true" ]]; then
        print_error "Local image not found. Use -b to build or -f to force."
        return 1
    fi
    
    # Use arch-specific naming (matches our build scripts)
    local source_image="${target}-${host_arch}"  # e.g., "full-arm64"
    
    # Verify the expected image exists
    if ! docker image inspect "${source_image}" >/dev/null 2>&1; then
        print_error "Expected image ${source_image} not found"
        print_error "Make sure to build with the current build scripts that create arch-specific names"
        return 1
    fi
    
    # Tag the local image with the registry name
    # WHY WE TAG: Docker needs to know where to push the image
    print_status "Tagging image: $source_image -> $remote_image"
    docker tag "$source_image" "$remote_image"
    
    # Push to registry
    print_status "Pushing image: $remote_image"
    docker push "$remote_image"
    
    print_success "Successfully pushed: $remote_image"
}

# Function to build and push multi-platform image
# WHY THIS IS DIFFERENT: Multi-platform builds create images that work on both arm64 AND amd64.
# Docker automatically serves the right architecture to each user. However, these images
# can't be stored locally - they must be pushed directly to a registry.
build_and_push_multiplatform() {
    local target="$1"  # e.g., "full"
    local tag="$2"     # e.g., "latest"
    
    # Determine the registry image name based on target
    local image_name
    if [[ "$target" == "full" ]]; then
        image_name="full"
    elif [[ "$target" == "r-ci" ]]; then
        image_name="r-ci"
    else
        print_error "Unknown target: $target"
        return 1
    fi
    
    local remote_image="${REGISTRY}/${REPOSITORY}/${image_name}:${tag}"
    
    print_status "Building and pushing multi-platform image for target: $target"
    print_status "Platforms: linux/amd64,linux/arm64"
    print_status "Destination: $remote_image"
    
    # Build and push multi-platform image directly to registry
    # --platform: build for both architectures
    # --target: which Dockerfile stage to build
    # --push: send directly to registry (can't store locally)
    # WHY --PUSH: Multi-platform manifests can't exist as local images
    if docker buildx build \
        --platform linux/amd64,linux/arm64 \
        --target "$target" \
        --build-arg DEBIAN_FRONTEND=noninteractive \
        --build-arg DEBCONF_NONINTERACTIVE_SEEN=true \
        --push \
        -t "$remote_image" \
        . ; then
        print_success "✅ Multi-platform image pushed successfully: $remote_image"
        return 0
    else
        print_error "❌ Failed to build and push multi-platform image: $remote_image"
        return 1
    fi
}

# Parse command line arguments
TARGET=""  # Empty means push all targets (consistent with build script)
TAG="$DEFAULT_TAG"
BUILD_FIRST=false
PUSH_ALL=true  # Default to pushing all targets
FORCE=false
ALL_PLATFORMS=false  # New option for multi-platform builds

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--target)
            TARGET="$2"
            PUSH_ALL=false  # Specific target means don't push all
            shift 2
            ;;
        -g|--tag)
            TAG="$2"
            shift 2
            ;;
        -b|--build)
            BUILD_FIRST=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -a|--all-platforms)
            ALL_PLATFORMS=true
            print_status "Multi-platform mode enabled (linux/amd64,linux/arm64)"
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate target
TARGETS=("full" "r-ci")
if [[ "$PUSH_ALL" == "false" ]]; then
    # Specific target was provided with -t flag
    if [[ ! " ${TARGETS[@]} " =~ " ${TARGET} " ]]; then
        print_error "Invalid target: $TARGET"
        print_error "Valid targets: ${TARGETS[*]}"
        exit 1
    fi
fi

# Main execution
print_status "Starting GHCR push process..."
print_status "Registry: $REGISTRY"
print_status "Repository: $REPOSITORY"

# Check prerequisites
check_ghcr_login

# Multi-platform builds require buildx and don't use local images
if [[ "$ALL_PLATFORMS" == "true" ]]; then
    print_status "Multi-platform mode: Building and pushing directly to registry..."
    
    # Check if buildx is available
    if ! docker buildx version >/dev/null 2>&1; then
        print_error "docker buildx is required for multi-platform builds"
        exit 1
    fi
    
    if [[ "$PUSH_ALL" == "true" ]]; then
        print_status "Building and pushing all targets (multi-platform)..."
        failed_builds=0
        VALID_TARGETS=("full" "r-ci")
        for target in "${VALID_TARGETS[@]}"; do
            echo
            print_status "Processing target: $target (multi-platform)"
            
            if ! build_and_push_multiplatform "$target" "$TAG"; then
                ((failed_builds++))
                print_error "Failed to build and push $target, continuing..."
            fi
        done
        
        if [ $failed_builds -eq 0 ]; then
            print_success "All multi-platform builds completed successfully!"
        else
            print_error "$failed_builds multi-platform build(s) failed"
            exit 1
        fi
    else
        print_status "Building and pushing single target: $TARGET (multi-platform)"
        
        if ! build_and_push_multiplatform "$TARGET" "$TAG"; then
            print_error "Failed to build and push $TARGET"
            exit 1
        fi
    fi
else
    # Default behavior: push existing local images (host platform)
    if [[ "$PUSH_ALL" == "true" ]]; then
        print_status "Pushing all targets (host platform)..."
        for target in "${TARGETS[@]}"; do
            echo
            print_status "Processing target: $target"
            
            if [[ "$BUILD_FIRST" == "true" ]]; then
                build_image "$target" "$target"
            fi
            
            push_image "$target" "$TAG" "$FORCE"
        done
    else
        print_status "Processing single target: $TARGET (host platform)"
        
        if [[ "$BUILD_FIRST" == "true" ]]; then
            build_image "$TARGET" "$TAG"
        fi
        
        push_image "$TARGET" "$TAG" "$FORCE"
    fi
fi

print_success "All operations completed successfully!"

# Success message
if [[ "$ALL_PLATFORMS" == "true" ]]; then
    if [[ "$PUSH_ALL" == "true" ]]; then
        print_status "Pushed both containers (multi-platform: linux/amd64,linux/arm64):"
        print_status "  - full → ghcr.io/${REPOSITORY}/full:${TAG}"
        print_status "  - r-ci → ghcr.io/${REPOSITORY}/r-ci:${TAG}"
    else
        print_status "Pushed single container (multi-platform: linux/amd64,linux/arm64):"
        local image_name
        if [[ "$TARGET" == "full" ]]; then
            image_name="full"
        else
            image_name="r-ci"
        fi
        print_status "  - ${TARGET} → ghcr.io/${REPOSITORY}/${image_name}:${TAG}"
    fi
else
    if [[ "$PUSH_ALL" == "true" ]]; then
        print_status "Pushed both containers (host platform only):"
        print_status "  - full → ghcr.io/${REPOSITORY}/full:${TAG}"
        print_status "  - r-ci → ghcr.io/${REPOSITORY}/r-ci:${TAG}"
    else
        print_status "Pushed single container (host platform only):"
        local image_name
        if [[ "$TARGET" == "full" ]]; then
            image_name="full"
        else
            image_name="r-ci"
        fi
        print_status "  - ${TARGET} → ghcr.io/${REPOSITORY}/${image_name}:${TAG}"
        echo
        print_status "💡 To push both containers, run without -t flag: $0"
        print_status "💡 To push multi-platform images, add -a flag: $0 -a"
    fi
fi
