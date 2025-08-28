# CLAUDE.md

Note: A concise summary for generic AI assistants (Copilot, etc.) lives in `copilot-instructions.md`. This file is the authoritative, detailed reference; update both when changing assistant guidance.

This file provides guidance to AI assistants when working with code in this repository.

## Repository Overview

Multi-stage R development container for research environments. Primary focus is building Docker images with R, Neovim, VS Code, LaTeX, and Pandoc for data analysis and scientific document preparation.

## Build Commands

**Primary workflow (`build.sh`):**
- Full container (host arch, load): `./build.sh full-container`
- R-only container (host arch, load): `./build.sh r-container`
- Cross-build amd64 (host != amd64 -> auto artifact): `./build.sh --amd64 full-container`
- Explicit artifact outputs (daemonless): `./build.sh --output oci r-container` | `./build.sh --output tar full-container`
- Force load on cross-build (requires daemon+buildx): `./build.sh --amd64 --output load r-container`
- Debug R packages: `./build.sh --debug full-container`
- No cache: `./build.sh --no-cache r-container`
- Parallel jobs: `R_BUILD_JOBS=6 ./build.sh full-container`
- Disable fallback: `./build.sh --no-fallback --output oci r-container`

**Output modes:**
- `load` (default) – load into local Docker daemon (requires daemon; auto-changed to `oci` for cross-build if daemonless)
- `oci` – directory `<tag>.oci/` (portable, fast unpack)
- `tar` – Docker save archive `<tag>.tar` (widely compatible)

**Fallback behavior (docker → buildx → buildctl):**
1. If Docker CLI + daemon reachable and `--output load`: use classic `docker build` (same-arch) or `docker buildx build --load` (cross-arch)
2. If output is artifact (`oci|tar`) and buildx available: `docker buildx build --output ...`
3. If docker/buildx unavailable or daemon down AND fallback enabled: attempt rootless `buildctl build` (local or remote via `BUILDKIT_HOST`)
4. If `--no-fallback` specified and daemon path not viable: fail fast with guidance.

**Additional script:**
- `push-to-ghcr.sh` – Builds (multi-arch when `-a`) & pushes to GHCR.

**Key environment variables:**
- `R_BUILD_JOBS` (default 2) – Parallel R compilation
- `TAG_SUFFIX` – Append suffix to local image tag
- `EXPORT_TAR=1` – Deprecated (alias for `--output tar`)
- `AUTO_INSTALL_BUILDKIT=1` – Allow apt-get install of buildkit when falling back
- `BUILDKIT_HOST` – Remote buildkit endpoint (e.g. `tcp://host:1234`)
- `BUILDKIT_PROGRESS=plain` – Simplify buildctl output (good for CI logs)

**Quick validation / tests:**
- Smoke test R: `docker run --rm full-container-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') R -q -e 'cat("R OK\n")'`
- Pandoc tests (inside full container): `./test_pandoc.sh`
- One-off command: `docker run --rm r-container-<arch> R -q -e 'sessionInfo()'`

**Lint/Format:**
- Dockerfile: `hadolint Dockerfile`
- Shell scripts: `shellcheck <file>; shfmt -w .`
- R code: `R -e "lintr::lint_dir()"` (uses `dotfiles/lintr`)
- Neovim Lua: `stylua dotfiles/config/nvim`

## Architecture

**Multi-stage Docker Build:**
- Stage 1 (base): Ubuntu + R + system tools
- Stage 2 (base-nvim): + Neovim with lazy.nvim plugins
- Stage 3 (base-nvim-vscode): + VS Code server and extensions
- Stage 4 (base-nvim-vscode-tex): + LaTeX/TeX Live
- Stage 5 (base-nvim-vscode-tex-pandoc): + Pandoc and pandoc-crossref
- Stage 6 (base-nvim-vscode-tex-pandoc-plus): + additional tools
- Stage 7 (full-container): + comprehensive R package suite (268 packages from `R_packages.txt`)
- Stage 8 (r-container): Slim CI image with essential R packages only

**Key Components:**
- R package installation via `install_r_packages.sh` with parallel compilation optimizations
- Neovim configured with lazy.nvim plugin manager (`dotfiles/config/nvim/`)
- Development tools: Go, Node.js, Python with language servers
- Document processing: LaTeX + Pandoc + pandoc-crossref
- Container registry support via GitHub Container Registry

**User Environment:**
- Primary user: `me` (UID 1000, shell: zsh)
- R compilation optimized via `~/.R/Makevars`
- Dotfiles structure: `dotfiles/` → `/home/me/.*`
- Support for both development and CI/CD workflows

## GitHub Actions

While initial work was started on GitHub Actions for automated builds and testing, GitHub Actions have been disabled in this repository. The build and deployment workflows are currently handled through local scripts (`build.sh`, `push-to-ghcr.sh`) and manual processes.

## Development Patterns

**Shell Scripts:**
- Use `set -euo pipefail`
- Quote variables, prefer `$(...)` over backticks
- Fail fast with meaningful error messages
- Comprehensive error handling and logging

**Dockerfile:**
- Single-purpose layers, clean apt caches
- Pin versions or fetch latest via API calls
- Use ARGs for build toggles (e.g., `DEBUG_PACKAGES`)
- Multi-stage builds for optimization

**R:**
- Explicit CRAN repos, quiet installs where possible
- Use `require(..., character.only=TRUE)` for package checks
- Parallel compilation via `MAKEFLAGS = -j$(nproc)`
- Optimized package installation with fallback mechanisms

**Naming:**
- kebab-case for scripts
- snake_case for environment variables
- UPPER_SNAKE for constants
- lowercase for image/tag names

## File Structure

- `Dockerfile`: Multi-stage container definition
- `build.sh`: Unified build script (replaces legacy build-* scripts)
- `install_r_packages.sh`: Optimized R package installer with fallback
- `R_packages.txt`: List of CRAN packages (268 total)
- `test_pandoc.sh`: Comprehensive Pandoc testing suite
- `push-to-ghcr.sh`: GitHub Container Registry deployment
- `dotfiles/`: User configuration (tmux, Neovim, R profile, lintr)
- `.devcontainer/`: VS Code development container configuration
- `.amazonq/`: Amazon Q assistant rules and guidelines