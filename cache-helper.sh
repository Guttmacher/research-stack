#!/bin/bash
# cache-helper.sh - Utilities for managing Docker build cache

set -e

# Configuration - REPO_OWNER and REGISTRY can be overridden with environment variables
REPO_OWNER="${REPO_OWNER:-${GITHUB_REPOSITORY_OWNER:-Guttmacher}}"  # Auto-detects in GitHub Actions
REGISTRY="${REGISTRY:-ghcr.io/${REPO_OWNER}/research-stack}"
TARGETS=("base" "base-nvim" "base-nvim-vscode" "base-nvim-vscode-tex" "base-nvim-vscode-tex-pandoc" "base-nvim-vscode-tex-pandoc-plus" "full")

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  clean               Remove all local cache"
    echo "  clean-registry      Remove all registry cache (requires push access)"
    echo "  list                List available cache images in registry"
    echo "  warm <target>       Pre-warm cache for specific target"
    echo "  warm-all            Pre-warm cache for all targets"
    echo "  inspect <target>    Show cache image details"
    echo ""
    echo "Options:"
    echo "  --registry <url>    Override default registry (${REGISTRY})"
    echo ""
    echo "Examples:"
    echo "  $0 warm base                                    # Warm cache for base target"
    echo "  $0 --registry ghcr.io/user/repo warm-all       # Warm all targets for custom registry"
    echo "  $0 list                                         # List available cache images"
}

clean_local_cache() {
    echo "🧹 Cleaning local Docker build cache..."
    docker builder prune -f
    echo "✅ Local cache cleaned"
}

clean_registry_cache() {
    echo "🗑️  Removing registry cache images..."
    for target in "${TARGETS[@]}"; do
        echo "  Removing cache for target: $target"
        # Note: This requires the GitHub CLI or registry API access
        # For GitHub Container Registry, you'd typically use:
        # gh api --method DELETE /user/packages/container/PACKAGE_NAME/versions/VERSION_ID
        echo "  ⚠️  Manual cleanup required for ${REGISTRY}/cache:${target}"
    done
    echo "ℹ️  Registry cache cleanup requires manual intervention or API access"
}

list_cache() {
    echo "📋 Available cache images in registry:"
    for target in "${TARGETS[@]}"; do
        echo "  ${REGISTRY}/cache:${target}"
    done
}

warm_cache() {
    local target="$1"
    echo "🔥 Warming cache for target: $target"
    ./build.sh "${target}"
    echo "✅ Cache warmed for target: $target"
}

warm_all_cache() {
    echo "🔥 Warming cache for all targets..."
    for target in "${TARGETS[@]}"; do
        warm_cache "$target"
    done
    echo "✅ All caches warmed"
}

inspect_cache() {
    local target="$1"
    echo "🔍 Inspecting cache for target: $target"
    docker buildx imagetools inspect "${REGISTRY}/cache:${target}" || echo "⚠️  Cache not found for target: $target"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --registry)
            REGISTRY="$2"
            shift 2
            ;;
        clean)
            clean_local_cache
            exit 0
            ;;
        clean-registry)
            clean_registry_cache
            exit 0
            ;;
        list)
            list_cache
            exit 0
            ;;
        warm)
            if [ -z "$2" ]; then
                echo "Error: warm command requires a target"
                usage
                exit 1
            fi
            warm_cache "$2"
            exit 0
            ;;
        warm-all)
            warm_all_cache
            exit 0
            ;;
        inspect)
            if [ -z "$2" ]; then
                echo "Error: inspect command requires a target"
                usage
                exit 1
            fi
            inspect_cache "$2"
            exit 0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
done

usage
