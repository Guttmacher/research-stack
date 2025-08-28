### Building the Container

### Simplified Build Workflow (Unified Script)

Best practice for local development is a single, obvious entry point. This repository now uses `build.sh` for all local single-architecture builds.

`build.sh` builds exactly one target (`full` or `r-ci`) for either:
* The host architecture (default)
* linux/amd64 explicitly (`--amd64`), using buildx only when cross-building is required

Examples:
```bash
# Host arch builds (loads into local daemon)
./build.sh full
./build.sh r-ci

# Force amd64 (e.g. on Apple Silicon). Auto-selects safer artifact (OCI) unless --output specified.
./build.sh --amd64 full

# Explicit output modes (avoid daemon load / for CI cache or transfer)
./build.sh --output oci r-ci      # creates r-ci-<arch>.oci/ (OCI layout dir)
./build.sh --output tar full   # creates full-<arch>.tar

# Disable cache / show R package logs / adjust parallel jobs
./build.sh --no-cache full
R_BUILD_JOBS=4 ./build.sh r-ci
./build.sh --debug r-ci

# Deprecated shortcut (equivalent to --output tar)
EXPORT_TAR=1 ./build.sh r-ci
```

### Resource Requirements (Memory / CPU)

Building the `full` target is resource intensive. Peak resident memory during the heavy R package + toolchain compilation stages routinely approaches ~24 GB. To build reliably you should use a machine (or Codespace/VM) with **≥ 32 GB RAM** (or substantial swap configured). On hosts with less memory the build may fail with OOM kills (often mid-way through R package compilation or LaTeX/Haskell layers).

Summary:
* Recommended for `full`: 32 GB RAM (peak ~24 GB, some headroom for kernel + Docker overhead).
* Minimum practical (with swap + reduced parallelism): ~16 GB RAM + 8–16 GB fast swap + `R_BUILD_JOBS=1`.
* `r-ci` (slim CI image) typically fits comfortably within 6–8 GB RAM.

If you must build on a smaller machine:
1. Export artifacts instead of loading: `./build.sh --output oci full` (slightly less daemon pressure).
2. Reduce concurrency: `R_BUILD_JOBS=1 MAKEFLAGS=-j1 ./build.sh full`.
3. Add temporary swap (Linux): create a 8–16 GB swapfile before building.
4. Pre-build intermediate layers (e.g. a stage without full R package set) or build the `r-ci` for day-to-day work.
5. Offload to CI or a beefier remote builder (remote buildkit via `BUILDKIT_HOST`).

If you only need R + a minimal toolchain for CI, prefer `r-ci` to avoid these requirements.

Local image naming remains explicit for clarity:
* `full-arm64`, `full-amd64`
* `r-ci-arm64`, `r-ci-amd64`

Multi-platform (both amd64 + arm64) publishing is still handled by `push-to-ghcr.sh -a`, which uses buildx to create and push a manifest list. This keeps the everyday developer loop fast and simple while still supporting distribution.

#### Cache & Variants Examples
```bash
# Standard host build
./build.sh full

# Cross-build for amd64 from arm64 host
./build.sh --amd64 r-ci

# Clean build (no cache)
./build.sh --no-cache full

# Increase R compile parallelism
R_BUILD_JOBS=6 ./build.sh full

# Artifact outputs
./build.sh --output oci r-ci   # directory (no daemon needed)
./build.sh --output tar full
EXPORT_TAR=1 ./build.sh r-ci   # legacy env (same as --output tar)
```
### Build commands

```bash
# Full development environment (host arch, load)
./build.sh full

# CI-focused R image (host arch, load)
./build.sh r-ci

# Cross-build for linux/amd64 (auto artifact unless --output load specified)
./build.sh --amd64 full
./build.sh --amd64 --output load r-ci   # force load (requires daemon + buildx)
```
To verify loaded images you can run lightweight checks manually, e.g.:
```bash
docker run --rm full-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/;s/arm64/arm64/') R -q -e 'cat("R ok\n")'
```
# Research Stack

A comprehensive, reproducible development environment using VS Code dev containers. Includes essential tools for data science, development, and document preparation.

## Features
- **Development Tools**: Git, R, Python, shell utilities
- **R Packages**: Comprehensive set of packages for data analysis, modeling, and visualization
- **Document Preparation**: LaTeX, Pandoc for typesetting
- **Performance**: Fast rebuilds with BuildKit caching
- **Multi-Architecture**: Supports both AMD64 and ARM64


## Quick Setup

**Prerequisites**: [VS Code](https://code.visualstudio.com/) with [Remote Development](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.vscode-remote-extensionpack) extension

### macOS: Install and Configure Colima

If you're on macOS, you'll need to install and properly configure Colima for correct file permissions:

1. **Install Colima with Homebrew:**
   ```bash
   brew install colima
   ```

2. **Start Colima as a service (persists across reboots):**
   ```bash
   brew services start colima
   ```

3. **Reconfigure for proper UID/GID mapping**
   
   The initial installation uses SSHFS, which causes permission errors when accessing project files from within the container. You need to reconfigure Colima to use the `vz` virtualization framework:
   
   ```bash
   colima stop
   colima delete
   colima start --vm-type vz --mount-type virtiofs
   ```
   
   By default, Colima allocates only 2 CPU cores and 2 GB RAM. For better performance, you can specify more resources, for example:
   ```
   colima stop
   colima delete
   colima start --vm-type vz --mount-type virtiofs --cpu 16 --memory 128
   ```
   Adjust the values to match your system's capabilities.

   Once configured this way, Colima will remember these settings and use `vz` for future starts.

4. **Set Colima as the default Docker context:**
   
   This makes Colima the default for all Docker commands and ensures VS Code's Dev Containers extension works properly:
   
   ```bash
   docker context use colima
   ```
   
   You can verify the active context with:
   ```bash
   docker context ls
   ```

   You can also append to your ~/.zshrc:

   ```zsh
   export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
   ```

### Container Setup

1. **Create `.devcontainer/devcontainer.json` in your project:**

  ### Note on Legacy Scripts

  Older resilient build scripts have been removed in favor of a single, minimal `build.sh`. For cross-architecture distribution use `push-to-ghcr.sh -a` which performs a purpose-built multi-platform build. This separation keeps local iterations fast and maintenance surface small.


```jsonc
{
"name": "Research Stack Development Environment",
  "image": "ghcr.io/Guttmacher/research-stack:latest",

  // For Colima on macOS, use vz for correct UID/GID mapping:
  // colima stop; colima delete; colima start --vm-type vz --mount-type virtiofs

  // Use non-root user "me" (alias of 'vscode' with same UID/GID). Set to "root" if needed.
  "remoteUser": "me",
  "updateRemoteUserUID": true,

  // Mount local Git config for container Git usage
  "mounts": [
    "source=${localEnv:HOME}/.gitconfig,target=/home/me/.gitconfig,type=bind,consistency=cached,readonly"
  ],

  // Set container timezone from host
  "containerEnv": {
    "TZ": "${localEnv:TZ}"
  }
}
```

2. **Open in VS Code:**
   - Open your project folder in VS Code
   - When prompted, click "Reopen in Container"

The container will automatically download and start your development environment.

## Using the Container with an Agentic Coding Tool

To use an agentic coding tool, modify devcontainer.json to include the necessary mounts and post-create commands to install the tool.

### Amazon Q CLI Integration

As an example, here is how to integrate the Amazon Q CLI into your dev container. There are two approaches:

#### Option 1: Custom Docker Image (Recommended)

Build a custom image that extends the base container with Q CLI pre-installed:

1. **Create a Dockerfile** named `Dockerfile.amazonq` in your project root:
   ```dockerfile
# Dockerfile for Research Stack with Amazon Q CLI pre-installed
   FROM ghcr.io/Guttmacher/research-stack:latest

   # Switch to the me user for installation
   USER me
   WORKDIR /home/me

   # Install Amazon Q CLI during image build
   RUN set -e; \
      ARCH="$(uname -m)"; \
      case "$ARCH" in \
        x86_64) Q_ARCH="x86_64" ;; \
        aarch64|arm64) Q_ARCH="aarch64" ;; \
        *) echo "Unsupported arch: $ARCH"; exit 1 ;; \
      esac; \
      URL="https://desktop-release.q.us-east-1.amazonaws.com/latest/q-${Q_ARCH}-linux.zip"; \
      echo "Downloading Amazon Q CLI from $URL"; \
      curl --proto '=https' --tlsv1.2 -fsSL "$URL" -o q.zip; \
      unzip q.zip; \
      chmod +x ./q/install.sh; \
      ./q/install.sh --no-confirm; \
      rm -rf q.zip q

   # Ensure Q CLI is in PATH for all users
   ENV PATH="/home/me/.local/bin:$PATH"
   ```

2. **Build your custom image:**
   ```bash
docker build -f Dockerfile.amazonq -t my-research-stack-amazonq .
   ```

3. **Create folders for persistent configuration:**
   ```bash
   mkdir -p ~/.container-aws ~/.container-amazon-q
   ```

4. **Update your `.devcontainer/devcontainer.json`:**
   ```jsonc
   {
"name": "Research Stack with Amazon Q CLI",
     "image": "my-research-stack-amazonq:latest",
     "remoteUser": "me",
     "updateRemoteUserUID": true,
     "mounts": [
       "source=${localEnv:HOME}/.gitconfig,target=/home/me/.gitconfig,type=bind,readonly",
       "source=${localEnv:HOME}/.container-aws,target=/home/me/.aws,type=bind",
       "source=${localEnv:HOME}/.container-amazon-q,target=/home/me/.local/share/amazon-q,type=bind"
     ],
     "containerEnv": { "TZ": "${localEnv:TZ}" }
   }
   ```

#### Option 2: PostCreateCommand (Simple but slower)

If you prefer not to build a custom image, you can install Q CLI on container startup:

1. **Create folders for persistent configuration:**
   ```bash
   mkdir -p ~/.container-aws ~/.container-amazon-q
   ```

2. **Update your `.devcontainer/devcontainer.json`:**
   ```jsonc
   {
"name": "Research Stack with Amazon Q CLI",
    "image": "ghcr.io/Guttmacher/research-stack:latest",
     "remoteUser": "me",
     "updateRemoteUserUID": true,
     "mounts": [
       "source=${localEnv:HOME}/.gitconfig,target=/home/me/.gitconfig,type=bind,readonly",
       "source=${localEnv:HOME}/.container-aws,target=/home/me/.aws,type=bind",
       "source=${localEnv:HOME}/.container-amazon-q,target=/home/me/.local/share/amazon-q,type=bind"
     ],
     "containerEnv": { "TZ": "${localEnv:TZ}" },
     "postCreateCommand": "ARCH=$(uname -m); case \"$ARCH\" in x86_64) QARCH=x86_64 ;; aarch64|arm64) QARCH=aarch64 ;; *) echo 'Unsupported arch'; exit 1 ;; esac; URL=\"https://desktop-release.q.us-east-1.amazonaws.com/latest/q-${QARCH}-linux.zip\"; curl --proto '=https' --tlsv1.2 -fsSL \"$URL\" -o 'q.zip' && unzip q.zip && ./q/install.sh --no-confirm && rm -rf q.zip q"
   }
   ```

**Note:** Option 1 is recommended as it pre-installs Q CLI during image build, making container startup much faster. Option 2 reinstalls Q CLI every time the container starts.


### User model

As an aesthetic preference, the container contains a non-root user named "me". To retain this design choice while ensuring compatibility with VS Code, the following adjustments are made:

- The image retains the default 'vscode' user required by Dev Containers/VS Code but also creates a 'me' user and 'me' group that share the same UID/GID as 'vscode'.
- Both users have the same home directory: /home/me (the previous /home/vscode is renamed).
- This design ensures compatibility with VS Code while making file listings show owner and group as 'me'.


## Research containers with tmux

For multi-day analyses, keep containers running with tmux sessions to survive disconnections (but not reboots).

**Key practices:**
- Use `--init` for proper signal handling during long runs
- Mount your project directory for data persistence  
- Center workflow around tmux for resilient sessions
- Implement checkpointing for analyses longer than uptime between reboots

### Terminal workflow
```bash
# Set project name from current directory
PROJECT_NAME=$(basename "$(pwd)")

# Start persistent container
docker run -d --name "$PROJECT_NAME" --hostname "$PROJECT_NAME" --restart unless-stopped --init \
  -v "$(pwd)":"/workspaces/$PROJECT_NAME" -w "/workspaces/$PROJECT_NAME" \
ghcr.io/Guttmacher/research-stack:latest sleep infinity

# Work in tmux
docker exec -it "$PROJECT_NAME" bash -lc "tmux new -A -s '$PROJECT_NAME'"
# Inside tmux: Rscript long_analysis.R 2>&1 | tee -a logs/run.log
# Detach: Ctrl-b then d

# When finished, stop the container
docker stop "$PROJECT_NAME" && docker rm "$PROJECT_NAME"
```

If you start the container using the terminal workflow and then open it from VS Code (the "Reopen in Container" action), Code will treat this like connecting to a host without having specified a workspace. Press "Open..." and enter your project directory (`/workspaces/$PROJECT_NAME`).

Configure Git to avoid permission issues:

```bash
git config --global --add safe.directory "/workspaces/$PROJECT_NAME"
```

This allows Git to operate in /workspaces/ when ownership or permissions differ, as is common in containers.

### VS Code workflow
If you began with the terminal workflow, you can attach to the running container from VS Code. Choose "Remote-Containers: Attach to Running Container..." from the Command Palette.

If you use VS Code to create the container, add the following to your `.devcontainer/devcontainer.json` file:

```jsonc
{
  "shutdownAction": "none",
  "init": true,
  "postAttachCommand": "tmux new -A -s analysis"
}
```

**Limitations:** Reboots terminate all processes. Container auto-restarts but jobs must be resumed manually. Use checkpointing for critical work.


## Technical Implementation Details

### Architecture

The container uses a multi-stage build process optimized for Docker layer caching and supports both AMD64 and ARM64 architectures:

- **Base Stage**: Ubuntu 24.04 with essential system packages
- **Development Tools**: Neovim with plugins, Git, shell utilities  
- **Document Preparation**: LaTeX, Pandoc, Haskell (for pandoc-crossref)
- **Programming Languages**: Python 3.13, R 4.5+ with comprehensive packages
- **VS Code Integration**: VS Code Server with extensions (positioned last for optimal caching)

**Platform Detection**: The Dockerfile automatically detects the target architecture using `dpkg --print-architecture` and installs architecture-specific binaries for tools like Go, Neovim, Hadolint, and others.

**Optimization Strategy**: Expensive, stable components (LaTeX, Haskell) are built early, while frequently updated components (VS Code extensions) are positioned late to minimize rebuild times when making changes.

### R Package Management

The container uses [pak](https://pak.r-lib.org/) for R package management, providing:

- **Better Dependency Resolution**: Handles complex dependency graphs more reliably
- **Faster Installation**: Parallel downloads and compilation
- **Caching**: BuildKit cache mounts for faster rebuilds

#### Cache Usage Examples
```bash
# Build with local cache only (default) - host platform
./build.sh full

# Build for AMD64 platform (cross-platform on Apple Silicon)
./build.sh --amd64 full

# Build using registry cache
./build.sh --amd64 full   # cross-build example

# Build and update registry cache
./build.sh r-ci

# Build without cache (clean build)
./build.sh --no-cache full

```

#### Available Build Targets
- `base` - Ubuntu base with system packages
- `base-nvim` - Base + Neovim
- `base-nvim-vscode` - Base + Neovim + VS Code Server
- `base-nvim-vscode-tex` - Base + Neovim + VS Code + LaTeX
- `base-nvim-vscode-tex-pandoc` - Base + Neovim + VS Code + LaTeX + Pandoc
- `base-nvim-vscode-tex-pandoc-haskell` - Base + Neovim + VS Code + LaTeX + Pandoc + Haskell
- `base-nvim-vscode-tex-pandoc-haskell-crossref` - Base + Neovim + VS Code + LaTeX + Pandoc + Haskell + pandoc-crossref
- `base-nvim-vscode-tex-pandoc-haskell-crossref-plus` - Base + additional tools
- `base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r` - Base + R with comprehensive packages via pak
- `base-nvim-vscode-tex-pandoc-haskell-crossref-plus-r-py` - Base + R + Python
- `full` - Complete development environment (default)

### User Model

The container uses a non-root user named "me" for security and compatibility:

- Compatible with VS Code Dev Containers (shares UID/GID with 'vscode' user)
- Home directory: `/home/me`
- Proper file permissions for mounted volumes


## Troubleshooting

### Quick Diagnostics

```bash
# System health check
docker --version && docker buildx version

# pak system check
docker run --rm ghcr.io/Guttmacher/research-stack:latest R -e 'library(pak); pak::pak_config()'

# Check cache usage
docker system df

# Check pak cache (if container exists)
docker run --rm full-arm64 R -e 'pak::cache_summary()' 2>/dev/null || echo "Container not built yet"
```

## License

Licensed under the [MIT License](LICENSE.txt).


## Building the Container

### Platform Support

Single-arch development builds use `build.sh` (host arch by default, `--amd64` to force). Multi-arch publishing is handled by `push-to-ghcr.sh -a`.

Examples:
```bash
./build.sh full          # host arch
./build.sh r-ci             # host arch
./build.sh --amd64 full  # cross-build (if host != amd64)
```

### Image Naming Convention

The build scripts use different naming conventions for local vs. registry images:

- **Local Images**: Include architecture suffix for clarity
  - Examples: `full-arm64`, `r-ci-amd64`, `base-amd64`
  - Built locally by: `./build.sh`

- **Registry Images**: Use multi-architecture manifests (no arch suffix)
  - Examples: `ghcr.io/user/repo:latest` (contains both amd64 and arm64)
  - Created by: `./push-to-ghcr.sh -a` or `docker buildx build --push`

This approach provides clarity during development while following Docker best practices for distribution.

### Build Options

`build.sh` options (summary):
--amd64 (force platform), --no-cache, --debug, --output load|oci|tar, --no-fallback

Additional env vars:
R_BUILD_JOBS (parallel R builds, default 2), TAG_SUFFIX, EXPORT_TAR=1 (deprecated alias for --output tar), AUTO_INSTALL_BUILDKIT=1 (permit apt install of buildkit), BUILDKIT_HOST (remote buildkit), BUILDKIT_PROGRESS=plain.

Examples:
```bash
./build.sh --debug full
./build.sh --no-cache full
./build.sh --output oci r-ci              # produce portable artifact
./build.sh --amd64 --output tar full   # cross-build exported tar
./build.sh --no-fallback --output oci r-ci # fail instead of buildctl fallback if docker unavailable
AUTO_INSTALL_BUILDKIT=1 ./build.sh --output oci r-ci # allow auto install of buildkit if needed
```

Daemonless fallback: If the Docker daemon isn't reachable (or buildx missing for artifact export) and `--no-fallback` is not set, the script will attempt a rootless `buildctl build`. Use `--no-fallback` to force failure (e.g., in CI enforcing daemon usage) or specify `BUILDKIT_HOST` to target a remote buildkitd.

### Publishing Images

- **`./push-to-ghcr.sh`** - Pushes images to GitHub Container Registry (GHCR)
  - **Platform**: Only pushes images built for the **host platform** (default)
  - **Multi-platform**: Use `-a` flag to build and push both AMD64 and ARM64
  - **Default**: Pushes both `full` and `r-ci` if available locally
  - **Examples**:
    ```bash
    ./push-to-ghcr.sh                       # Push both containers (host platform)
    ./push-to-ghcr.sh -a                    # Build and push both containers (both platforms)
    ./push-to-ghcr.sh -t full     # Push specific container (host platform)
    ./push-to-ghcr.sh -a -t r-ci     # Build and push R container (both platforms)
    ./push-to-ghcr.sh -b -t r-ci     # Build and push R container (host platform)
    ```

- **Multi-architecture publishing**:
  ```bash
  # Option 1: Use the -a flag (recommended)
  ./push-to-ghcr.sh -a                     # Build and push both platforms
  ./push-to-ghcr.sh -a -t full   # Build and push specific target, both platforms
  
  # Option 2: Use docker buildx directly
  docker buildx build --platform linux/amd64,linux/arm64 \
    --target full --push -t ghcr.io/user/repo:latest .
  ```

## Multiple container targets

This repository now supports two top-level container targets optimized for different use cases.

- r-ci: a lightweight R-focused image for CI/CD
  - Base: Ubuntu + essential build tools only
  - Includes: R 4.x, pak, JAGS, and packages from R_packages.txt (Stan packages excluded)
  - Skips: Neovim, LaTeX toolchain, Pandoc, Haskell, Python, VS Code server, CmdStan
  - Working directory: /workspaces, ENV CI=true
  - Best for: GitHub Actions / Bitbucket Pipelines / other CI runners

- full: the complete local development environment
  - Includes: Neovim (+plugins), LaTeX, Pandoc (+crossref), Haskell/Stack,
    Python 3.13, R (+pak + packages), VS Code server, dotfiles
  - Working directory: /workspaces
  - Best for: local development, VS Code Dev Containers

### Command recap

```bash
# Host arch (load)
./build.sh full
./build.sh r-ci

# Cross (auto artifact)
./build.sh --amd64 r-ci

# Explicit artifact outputs
./build.sh --output oci r-ci
./build.sh --output tar full

# Force load cross-build (requires daemon + buildx)
./build.sh --amd64 --output load r-ci

# Publish multi-arch
./push-to-ghcr.sh -a
```

**Note**: `push-to-ghcr.sh -a` performs a fresh multi-platform build & push; prior artifact exports are not reused for manifest creation.

Add `--test` to run non-interactive verification inside the built image.

### Using in VS Code Dev Containers (full)

Reference the published image in your project's .devcontainer/devcontainer.json:

{
  "name": "research-stack (full)",
  "image": "ghcr.io/Guttmacher/full:full",
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspaces/project,type=bind",
  "workspaceFolder": "/workspaces/project"
}

### Notes

- Both targets install R packages using pak based on R_packages.txt; the set is shared so R behavior is consistent.
- The r-ci target may install additional apt packages (e.g., pandoc) via pak when needed by R packages.
- The legacy stage name full remains available for backward compatibility and aliases to full.



### r-ci (slim CI image)

This stage is designed for CI/CD. It intentionally excludes heavy toolchains and developer tools to keep the image small and fast:
- No CmdStan; Stan model compilation is not supported in this image
- Stan-related R packages are excluded by default during installation
- Compilers (g++, gcc, gfortran, make) are installed only temporarily for building R packages, then purged
- Not included: LaTeX, Neovim, pandoc-crossref, Go toolchain, Python user tools, and various CLI utilities present in full
- Aggressive cleanup of caches, man pages, docs, and R help files

If you need to compile Stan models, use the full image or a custom derivative.
