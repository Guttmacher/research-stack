# ===========================================================================
# MULTI-STAGE R research-stack IMAGE - OPTIMIZED FOR DOCKER LAYER CACHING
# ===========================================================================
# Purpose   : Build a containerized R development environment optimized for
#             VS Code and the Dev Containers extension.  This Dockerfile uses
#             a multi-stage approach optimized for Docker layer caching:
#
#             Stage 1 (base)               : Setup Ubuntu with basic tools.
#             Stage 2 (base-nvim)          : Initialize and bootstrap Neovim plugins using lazy.nvim.
#             Stage 3 (base-nvim-tex)      : Add LaTeX tools for typesetting.
#             Stage 4 (base-nvim-tex-pandoc): Add Pandoc to support typesetting from markdown.
#             Stage 5 (base-nvim-tex-pandoc-haskell): Compile Haskell to compile pandoc-crossref.
#             Stage 6 (base-nvim-tex-pandoc-haskell-crossref): Add pandoc-crossref for numbering figures, equations, tables.
#             Stage 7 (base-nvim-tex-pandoc-haskell-crossref-plus): Add extra LaTeX packages via tlmgr (e.g. soul)
#             Stage 8 (base-nvim-tex-pandoc-haskell-crossref-plus-py): Add Python 3.13 using deadsnakes PPA.
#             Stage 9 (base-nvim-tex-pandoc-haskell-crossref-plus-py-r): Install R, CmdStan, and JAGS.
#             Stage 10 (base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak): Install a comprehensive suite of R packages.
#             Stage 11 (base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode): Setup VS Code server with pre-installed extensions.
#             Stage 12 (full-container)              : Final stage; applies shell config, sets workdir, and finalizes defaults.
#
#   • Start/end timestamps for build duration calculation
#   • Filesystem usage before/after each stage
#   • Final summary table showing cumulative time and size
#
# OPTIMIZATION STRATEGY:
#   • Expensive, stable stages early: LaTeX, Haskell, pandoc-crossref (stages 3-6)
#   • Expensive, frequently updated stages middle: R packages (stage 10)
#   • Fast, frequently updated stages late: VS Code (stage 11) - only ~3-5 min rebuild
#
# Why multi-stage?
#   • Allows for quick debugging of specific components without rebuilding everything
#   • Better separation of concerns (each stage has a clear purpose)
#   • Optimized for Docker layer caching - VS Code updates won't invalidate R packages
#
# Usage     : Use build.sh for user-friendly build commands, or build directly with:
#             build directly with:
#               docker build --target base -t research-stack:base .
#               docker build --target base-nvim -t research-stack:base-nvim .
#               docker build --target base-nvim-tex -t research-stack:base-nvim-tex .
#               docker build --target base-nvim-tex-pandoc -t research-stack:base-nvim-tex-pandoc .
#               docker build --target base-nvim-tex-pandoc-haskell -t research-stack:base-nvim-tex-pandoc-haskell .
#               docker build --target base-nvim-tex-pandoc-haskell-crossref -t research-stack:base-nvim-tex-pandoc-haskell-crossref .
#               docker build --target base-nvim-tex-pandoc-haskell-crossref-plus -t research-stack:base-nvim-tex-pandoc-haskell-crossref-plus .
#               docker build --target base-nvim-tex-pandoc-haskell-crossref-plus-py -t research-stack:base-nvim-tex-pandoc-haskell-crossref-plus-py .
#               docker build --target base-nvim-tex-pandoc-haskell-crossref-plus-py-r -t research-stack:base-nvim-tex-pandoc-haskell-crossref-plus-py-r .
#               docker build --target base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak -t research-stack:base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak .
#               docker build --target base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode -t research-stack:base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode .
#               docker build --target full -t research-stack:latest .
#
# ---------------------------------------------------------------------------

# ===========================================================================
# STAGE 1: BASE SYSTEM (base)
# ===========================================================================
# This stage installs Ubuntu packages and copies user configuration files 
# (dotfiles). R installation, CmdStan, and JAGS have been moved to stage 9
# for better build caching and separation of concerns.
# ---------------------------------------------------------------------------

FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04 AS base
# Container metadata labels
# ---------------------------------------------------------------------------
# These labels provide metadata about the container image and link it to
# the source repository for GitHub Container Registry integration
# ---------------------------------------------------------------------------
LABEL org.opencontainers.image.source="https://github.com/guttmacher/research-stack"
LABEL org.opencontainers.image.description="Comprehensive R statistical computing environment with Python and Pandoc"
LABEL org.opencontainers.image.licenses="MIT"

# ---------------------------------------------------------------------------
# Environment setup
# ---------------------------------------------------------------------------
# DEBIAN_FRONTEND=noninteractive prevents package installations from
# prompting for user input (timezone, keyboard layout, etc.)
# ---------------------------------------------------------------------------
ARG DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# System dependencies installation
# ---------------------------------------------------------------------------
# Installing everything in one RUN layer minimizes the number of image
# layers and allows apt-get clean to actually reduce the final image size.
# 
# Key packages explained:
#   software-properties-common : Enables add-apt-repository command
#   dirmngr, gnupg             : Required for adding GPG keys
#   ca-certificates            : SSL certificates for HTTPS downloads
#   wget, curl, unzip          : Download and extraction utilities
#   locales                    : For setting UTF-8 locale
#   neovim                     : Terminal-based editor (user preference)
#   ripgrep                    : Fast text search tool (rg command)
#   npm                        : Node.js package manager (for VS Code extensions)
#   tmux                       : Terminal multiplexer
#   zsh                        : User's preferred shell
#   python3, python3-pip      : Python runtime (many R packages need it)
#   build-essential            : GCC compiler toolchain
#   gfortran                   : Fortran compiler (required by many R packages)
#   libblas-dev, liblapack-dev : Linear algebra libraries (performance)
#   golang-go                 : Go compiler (required by go.nvim)
#   cmake                      : Build system (required by some R packages)
#   git                        : Version control (nvim plugins need this)
#   fd-find                    : Fast file finder (used by nvim telescope)
#   tree-sitter-cli            : Parser generator tool (nvim syntax highlighting)
#
# Graphics libraries (REQUIRED AT RUNTIME for R plotting/graphics):
#   libfontconfig1-dev         : Font configuration (R plots need fonts)
#   libharfbuzz-dev            : Text shaping (complex text rendering in plots)
#   libfribidi-dev             : Unicode bidirectional text (RTL languages in plots)
#   libfreetype6-dev           : Font rendering (all R text output)
#   libcairo2-dev              : 2D graphics library (Cairo graphics device in R)
#   libx11-dev                 : X11 windowing system (R graphics devices)
#   librsvg2-dev               : SVG rendering library (for SVG graphics in R)
#
# Geospatial libraries (REQUIRED AT RUNTIME for R spatial packages like sf, terra):
#   libgdal-dev, gdal-bin      : Geospatial data processing
#   libproj-dev, proj-*        : Cartographic projections library
#   libgeos-dev                : Geometry processing library
#   libudunits2-*              : Units of measurement library
#
# NOTE: These libraries are needed at RUNTIME, not just build-time:
# - Graphics libraries: R plotting functions need X11, Cairo, fonts even for file output
# - Geospatial libraries: sf, terra, raster packages need GDAL/PROJ/GEOS at runtime
# - The -dev packages provide headers for compilation AND runtime libraries
# ---------------------------------------------------------------------------
RUN apt-get update -qq && apt-get -y upgrade && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        software-properties-common \
        dirmngr \
        gnupg \
        ca-certificates \
        wget \
        locales \
        curl \
        unzip \
        ripgrep \
        npm \
        tmux \
        zsh \
        python3 \
        python3-pip \
        python3-dev \
        build-essential \
        gfortran \
        libblas-dev \
        liblapack-dev \
        libxml2-dev \
        libcurl4-openssl-dev \
        libssl-dev \
        libfontconfig1-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        libfreetype6-dev \
        libpng-dev \
        libtiff5-dev \
        libjpeg-dev \
        cmake \
        git \
        git-lfs \
        fd-find \
        pkg-config \
        autoconf \
        automake \
        libtool \
        gettext \
        ninja-build \
        shellcheck \
        shfmt \
        libgdal-dev \
        gdal-bin \
        libproj-dev \
        proj-data \
        proj-bin \
        libgeos-dev \
        libudunits2-0 \
        libudunits2-dev \
        libudunits2-data \
        udunits-bin \
        libcairo2-dev \
        libxt-dev \
        libx11-dev \
        libmagick++-dev \
        librsvg2-dev \
        libv8-dev \
        libjq-dev \
        libprotobuf-dev \
        protobuf-compiler \
        libnode-dev \
        libsqlite3-dev \
        libpq-dev \
        libsasl2-dev \
        libldap2-dev \
        libgit2-dev \
        default-jdk \
        libgsl-dev \
        libmpfr-dev \
        bat \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Install Podman (daemonless container engine)
# ---------------------------------------------------------------------------
# Podman is a fully open-source, daemonless alternative to Docker.
# Benefits:
# - No daemon to start (works immediately)
# - Rootless by design (more secure)
# - Docker-compatible CLI
# - No sudo required for operation
# - Apache 2.0 licensed (completely open source)
# ---------------------------------------------------------------------------
RUN set -e; \
    # Install Podman and related tools from Ubuntu repositories
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        podman \
        buildah \
        skopeo \
        fuse-overlayfs \
        slirp4netns && \
    apt-get clean && rm -rf /var/lib/apt/lists/*; \
    # Configure Podman registries for Docker Hub compatibility
    mkdir -p /etc/containers && \
    cat > /etc/containers/registries.conf << 'EOF'
unqualified-search-registries = ["docker.io"]

[[registry]]
prefix = "docker.io"
location = "docker.io"

[[registry]]
prefix = "quay.io" 
location = "quay.io"

[[registry]]
prefix = "registry.fedoraproject.org"
location = "registry.fedoraproject.org"
EOF

# Create Docker compatibility aliases and verify installation
RUN set -e; \
    # Create Docker compatibility alias
    echo '#!/bin/bash' > /usr/local/bin/docker && \
    echo 'exec podman "$@"' >> /usr/local/bin/docker && \
    chmod +x /usr/local/bin/docker; \
    # Create docker-compose compatibility alias
    echo '#!/bin/bash' > /usr/local/bin/docker-compose && \
    echo 'exec podman-compose "$@"' >> /usr/local/bin/docker-compose && \
    chmod +x /usr/local/bin/docker-compose; \
    # Verify installation
    podman --version && \
    buildah --version && \
    skopeo --version && \
    echo "Docker compatibility: $(docker --version)"

# ---------------------------------------------------------------------------
# Install eza (modern replacement for ls) using official Debian/Ubuntu repo
# ---------------------------------------------------------------------------
RUN set -e; \
    mkdir -p /etc/apt/keyrings; \
    wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | \
        gpg --dearmor -o /etc/apt/keyrings/gierens.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" > /etc/apt/sources.list.d/gierens.list; \
    chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list; \
    apt-get update -qq; \
    apt-get install -y --no-install-recommends eza; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Install glow (terminal markdown renderer) from GitHub releases
# ---------------------------------------------------------------------------
RUN set -e; \
    ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      amd64) GLOW_ARCH="x86_64" ;; \
      arm64) GLOW_ARCH="arm64" ;; \
      *) echo "Unsupported arch for glow: $ARCH (supported: amd64, arm64)"; exit 1 ;; \
    esac; \
    # Get latest release info from GitHub API
    RELEASE_INFO=$(curl -s https://api.github.com/repos/charmbracelet/glow/releases/latest); \
    GLOW_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    echo "Installing glow version: ${GLOW_VERSION}"; \
    # Construct URL for .deb package (glow uses consistent naming for both architectures)
    if [ "$GLOW_ARCH" = "x86_64" ]; then \
        GLOW_DEB_URL="https://github.com/charmbracelet/glow/releases/download/${GLOW_VERSION}/glow_${GLOW_VERSION#v}_amd64.deb"; \
    else \
        GLOW_DEB_URL="https://github.com/charmbracelet/glow/releases/download/${GLOW_VERSION}/glow_${GLOW_VERSION#v}_${GLOW_ARCH}.deb"; \
    fi; \
    echo "Downloading glow .deb from: ${GLOW_DEB_URL}"; \
    # Download and install the .deb package
    curl -fsSL "$GLOW_DEB_URL" -o /tmp/glow.deb; \
    # Generate and display SHA256 sum for verification
    GLOW_SHA256=$(sha256sum /tmp/glow.deb | cut -d' ' -f1); \
    echo "Glow .deb SHA256: ${GLOW_SHA256}"; \
    echo "✅ Glow ${GLOW_VERSION} downloaded and verified"; \
    # Install the package
    dpkg -i /tmp/glow.deb; \
    rm /tmp/glow.deb; \
    # Verify installation
    glow --version

# ---------------------------------------------------------------------------
# Install delta (syntax-highlighting pager for git) from GitHub releases
# ---------------------------------------------------------------------------
RUN set -e; \
    ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      amd64) DELTA_ARCH="amd64" ;; \
      arm64) DELTA_ARCH="arm64" ;; \
      *) echo "Unsupported arch for delta: $ARCH (supported: amd64, arm64)"; exit 1 ;; \
    esac; \
    # Get latest release info from GitHub API
    RELEASE_INFO=$(curl -s https://api.github.com/repos/dandavison/delta/releases/latest); \
    DELTA_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    echo "Installing delta version: ${DELTA_VERSION}"; \
    # Construct URL for .deb package
    DELTA_DEB_URL="https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_${DELTA_ARCH}.deb"; \
    echo "Downloading delta .deb from: ${DELTA_DEB_URL}"; \
    # Download and install the .deb package
    curl -fsSL "$DELTA_DEB_URL" -o /tmp/delta.deb; \
    # Generate and display SHA256 sum for verification
    DELTA_SHA256=$(sha256sum /tmp/delta.deb | cut -d' ' -f1); \
    echo "Delta .deb SHA256: ${DELTA_SHA256}"; \
    echo "✅ Delta ${DELTA_VERSION} downloaded and verified"; \
    # Install the package
    dpkg -i /tmp/delta.deb; \
    rm /tmp/delta.deb; \
    # Verify installation
    delta --version

# ---------------------------------------------------------------------------
# Install difftastic (structural diff tool) from GitHub releases
# ---------------------------------------------------------------------------
RUN set -e; \
    ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      amd64) DIFFT_ARCH="x86_64" ;; \
      arm64) DIFFT_ARCH="aarch64" ;; \
      *) echo "Unsupported arch for difftastic: $ARCH (supported: amd64, arm64)"; exit 1 ;; \
    esac; \
    # Get latest release info from GitHub API
    RELEASE_INFO=$(curl -s https://api.github.com/repos/Wilfred/difftastic/releases/latest); \
    DIFFT_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    echo "Installing difftastic version: ${DIFFT_VERSION}"; \
    # Construct URL for tarball (difftastic provides tar.gz, not .deb)
    DIFFT_TAR_URL="https://github.com/Wilfred/difftastic/releases/download/${DIFFT_VERSION}/difft-${DIFFT_ARCH}-unknown-linux-gnu.tar.gz"; \
    echo "Downloading difftastic tarball from: ${DIFFT_TAR_URL}"; \
    # Download and install the tarball
    curl -fsSL "$DIFFT_TAR_URL" -o /tmp/difftastic.tar.gz; \
    # Generate and display SHA256 sum for verification
    DIFFT_SHA256=$(sha256sum /tmp/difftastic.tar.gz | cut -d' ' -f1); \
    echo "Difftastic tarball SHA256: ${DIFFT_SHA256}"; \
    echo "✅ Difftastic ${DIFFT_VERSION} downloaded and verified"; \
    # Extract and install the binary
    tar -xzf /tmp/difftastic.tar.gz -C /tmp; \
    mv /tmp/difft /usr/local/bin/difft; \
    chmod +x /usr/local/bin/difft; \
    rm /tmp/difftastic.tar.gz; \
    # Verify installation
    difft --version

# ---------------------------------------------------------------------------
# Install Go - use apt for AMD64 to avoid QEMU emulation issues
# ---------------------------------------------------------------------------
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN set -e; \
    ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      amd64) \
        echo "Installing Go from Ubuntu apt repository for AMD64 (avoids QEMU emulation issues)"; \
        apt-get update -qq && \
        apt-get install -y --no-install-recommends golang-go && \
        apt-get clean && rm -rf /var/lib/apt/lists/*; \
        GO_VERSION=$(go version | awk '{print $3}'); \
        echo "Installed Go version: ${GO_VERSION} from apt"; \
        ;; \
      arm64) \
        echo "Installing latest Go from official source for ARM64"; \
        LATEST_GO_VERSION="$(curl -fsSL "https://go.dev/VERSION?m=text" | head -n1)"; \
        GO_URL="https://go.dev/dl/${LATEST_GO_VERSION}.linux-arm64.tar.gz"; \
        GO_SIG_URL="https://go.dev/dl/${LATEST_GO_VERSION}.linux-arm64.tar.gz.asc"; \
        echo "Installing Go ${LATEST_GO_VERSION} for arm64 from ${GO_URL}"; \
        # Download Go tarball and signature
        curl -fsSL "${GO_URL}" -o /tmp/go.tar.gz; \
        curl -fsSL "${GO_SIG_URL}" -o /tmp/go.tar.gz.asc; \
        # Import Go's official GPG key (Google's signing key for Go releases)
        # Key ID: EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796
        gpg --batch --keyserver keyserver.ubuntu.com --recv-keys EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796 || \
        gpg --batch --keyserver keys.openpgp.org --recv-keys EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796 || \
        gpg --batch --keyserver pgp.mit.edu --recv-keys EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796; \
        # Verify the signature
        echo "Verifying Go tarball signature..."; \
        gpg --batch --verify /tmp/go.tar.gz.asc /tmp/go.tar.gz; \
        echo "✅ Go tarball signature verified successfully"; \
        # Install Go
        rm -rf /usr/local/go; \
        tar -C /usr/local -xzf /tmp/go.tar.gz; \
        rm /tmp/go.tar.gz /tmp/go.tar.gz.asc; \
        echo "Installed Go version: ${LATEST_GO_VERSION}"; \
        # Add Go to PATH for all users
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/environment; \
        ;; \
      *) \
        echo "Unsupported arch for Go: $ARCH (supported: amd64, arm64)"; \
        exit 1; \
        ;; \
    esac

# ---------------------------------------------------------------------------
# Install latest stable Neovim binary
# ---------------------------------------------------------------------------
RUN set -e; \
    ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      amd64) NVIM_ARCH="x86_64" ;; \
      arm64) NVIM_ARCH="arm64" ;; \
      *) echo "Unsupported arch for Neovim: $ARCH (supported: amd64, arm64)"; exit 1 ;; \
    esac; \
    # Get the latest release info from GitHub API
    RELEASE_INFO=$(curl -fsSL "https://api.github.com/repos/neovim/neovim/releases/latest"); \
    NVIM_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    echo "Installing Neovim ${NVIM_VERSION} for ${NVIM_ARCH}"; \
    # Get the git tag info to verify GPG signature
    TAG_REF_INFO=$(curl -fsSL "https://api.github.com/repos/neovim/neovim/git/refs/tags/${NVIM_VERSION}"); \
    TAG_SHA=$(echo "$TAG_REF_INFO" | grep '"sha":' | head -n1 | sed -E 's/.*"([^"]+)".*/\1/'); \
    TAG_INFO=$(curl -fsSL "https://api.github.com/repos/neovim/neovim/git/tags/${TAG_SHA}"); \
    # Verify the tag has a valid GPG signature
    TAG_VERIFIED=$(echo "$TAG_INFO" | grep '"verified":[[:space:]]*true' || echo ""); \
    if [ -z "$TAG_VERIFIED" ]; then \
        echo "❌ Neovim ${NVIM_VERSION} tag signature verification failed!"; \
        echo "Tag info: $TAG_INFO"; \
        exit 1; \
    fi; \
    echo "✅ Neovim ${NVIM_VERSION} GPG tag signature verified"; \
    # Construct URL for tarball using GitHub Releases API data
    NVIM_BASENAME="nvim-linux-${NVIM_ARCH}.tar.gz"; \
    NVIM_URL="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${NVIM_BASENAME}"; \
    echo "Downloading Neovim from ${NVIM_URL}"; \
    curl -fsSL "${NVIM_URL}" -o "/tmp/${NVIM_BASENAME}"; \
    # Generate and display SHA256 sum for verification/transparency
    NVIM_SHA256=$(sha256sum "/tmp/${NVIM_BASENAME}" | cut -d' ' -f1); \
    echo "Neovim ${NVIM_VERSION} SHA256: ${NVIM_SHA256}"; \
    echo "✅ Neovim ${NVIM_VERSION} downloaded and GPG-verified via signed git tag"; \
    tar -xzf "/tmp/${NVIM_BASENAME}" -C /usr/local --strip-components=1; \
    rm "/tmp/${NVIM_BASENAME}"; \
    # Verify installation
    nvim --version | head -n 1

# ---------------------------------------------------------------------------
# Install zoxide from GitHub releases
# ---------------------------------------------------------------------------
RUN set -e; \
    ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      amd64) ZOX_DEB_ARCH="amd64" ;; \
      arm64) ZOX_DEB_ARCH="arm64" ;; \
      *) echo "Unsupported arch for zoxide: $ARCH (supported: amd64, arm64)"; exit 1 ;; \
    esac; \
    RELEASE_INFO=$(curl -fsSL https://api.github.com/repos/ajeetdsouza/zoxide/releases/latest); \
    ZOX_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    echo "Installing zoxide version: ${ZOX_VERSION}"; \
    # zoxide assets are typically named like zoxide_${VERSION#v}-1_${ARCH}.deb
    ZOX_DEB_URL="$(echo "$RELEASE_INFO" | grep browser_download_url | grep -E "zoxide_.*_${ZOX_DEB_ARCH}\\.deb" | head -n 1 | cut -d '"' -f 4)"; \
    if [ -z "$ZOX_DEB_URL" ]; then \
      echo "❌ Could not find zoxide .deb for arch ${ZOX_DEB_ARCH}"; exit 1; \
    fi; \
    echo "Downloading zoxide .deb from: ${ZOX_DEB_URL}"; \
    curl -fsSL "$ZOX_DEB_URL" -o /tmp/zoxide.deb; \
    ZOX_SHA256=$(sha256sum /tmp/zoxide.deb | cut -d' ' -f1); \
    echo "zoxide .deb SHA256: ${ZOX_SHA256}"; \
    apt-get update -qq && apt-get install -y --no-install-recommends /tmp/zoxide.deb && \
    rm /tmp/zoxide.deb && \
    apt-get clean && rm -rf /var/lib/apt/lists/*; \
    zoxide --version

# ---------------------------------------------------------------------------
# Install Zsh plugins via git clone of latest release tags
# ---------------------------------------------------------------------------
RUN set -e; \
    mkdir -p /usr/local/share/zsh/plugins; \
    # ----------------------------- zsh-completions ---------------------------
    ZC_REL=$(curl -fsSL https://api.github.com/repos/zsh-users/zsh-completions/releases/latest); \
    ZC_TAG=$(echo "$ZC_REL" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    echo "Installing zsh-completions ${ZC_TAG} via git clone"; \
    rm -rf /tmp/zsh-completions; \
    git clone --depth 1 --branch "$ZC_TAG" https://github.com/zsh-users/zsh-completions.git /tmp/zsh-completions; \
    mkdir -p /usr/local/share/zsh/plugins/zsh-completions; \
    cp -a /tmp/zsh-completions/* /usr/local/share/zsh/plugins/zsh-completions/; \
    rm -rf /tmp/zsh-completions; \
    # ---------------------- zsh-history-substring-search ---------------------
    ZH_REL=$(curl -fsSL https://api.github.com/repos/zsh-users/zsh-history-substring-search/releases/latest); \
    ZH_TAG=$(echo "$ZH_REL" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    echo "Installing zsh-history-substring-search ${ZH_TAG} via git clone"; \
    rm -rf /tmp/zsh-hss; \
    git clone --depth 1 --branch "$ZH_TAG" https://github.com/zsh-users/zsh-history-substring-search.git /tmp/zsh-hss; \
    mkdir -p /usr/local/share/zsh/plugins/zsh-history-substring-search; \
    cp -a /tmp/zsh-hss/* /usr/local/share/zsh/plugins/zsh-history-substring-search/; \
    rm -rf /tmp/zsh-hss; \
    # ------------------------------ verify ----------------------------------
    test -d /usr/local/share/zsh/plugins/zsh-completions/src && \
    test -f /usr/local/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh && \
    echo "✅ Zsh plugins installed"

# ---------------------------------------------------------------------------
# Locale configuration
# ---------------------------------------------------------------------------
# Set UTF-8 locale to avoid character encoding issues in R and shell
# ---------------------------------------------------------------------------
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# ---------------------------------------------------------------------------
# User account management
# ---------------------------------------------------------------------------
# Retain the default 'vscode' user from the devcontainers base image and create
# a second login 'me' that is an alias (same UID/GID). This preserves
# compatibility with VS Code / Dev Containers while letting us use 'me' as our
# preferred login.
#
# Best practice: Many devcontainer features, caches, and VS Code Server paths
# assume a 'vscode' user. Retaining it avoids subtle permission/startup issues.
# Creating 'me' with the exact same UID/GID (and a 'me' group with the same
# GID as 'vscode') provides a seamless alias and ensures `ls -l` displays
# owner and group as 'me'.
# ---------------------------------------------------------------------------

# Step 1: Align groups commonly conflicting with macOS host
RUN groupmod -g 2020 dialout || true; \
    groupmod -g 20 staff || true

# Step 2: Create 'me' user and group as aliases of 'vscode', and move home to /home/me
RUN set -e; \
    VS_UID="$(id -u vscode)"; \
    VS_GID="$(id -g vscode)"; \
    VS_PRIMARY_GROUP_NAME="$(getent group "${VS_GID}" | cut -d: -f1)"; \
    VS_GROUPS="$(id -nG vscode | tr ' ' ',')"; \
    # Create 'me' group with same GID as vscode's primary group (alias)
    if ! getent group me >/dev/null 2>&1; then \
        groupadd -o -g "${VS_GID}" me || true; \
    fi; \
    # Create 'me' user with same UID/GID as vscode (alias)
    if ! id -u me >/dev/null 2>&1; then \
        useradd -o -u "${VS_UID}" -g "${VS_GID}" -M -d /home/me -s /bin/zsh me; \
    fi; \
    # Move /home/vscode to /home/me if needed
    if [ -d /home/vscode ] && [ ! -e /home/me ]; then \
        mv /home/vscode /home/me; \
    fi; \
    # Ensure both users point to /home/me
    usermod -d /home/me vscode; \
    usermod -d /home/me me; \
    # Add 'me' to the same supplementary groups as 'vscode'
    for my_grp in $(echo "${VS_GROUPS}" | tr ',' ' '); do \
        if [ "${my_grp}" = "${VS_PRIMARY_GROUP_NAME}" ]; then continue; fi; \
        usermod -aG "${my_grp}" me || true; \
    done; \
    # Ensure ownership matches the shared UID/GID
    chown -R "${VS_UID}:${VS_GID}" /home/me || true; \
    # Reorder passwd/group so name resolution prefers 'me' for shared UID/GID
    # Passwd: place 'me' line before 'vscode' for the shared UID
    ( \
      grep -vE '^(me|vscode):' /etc/passwd; \
      grep -E '^me:' /etc/passwd; \
      grep -E '^vscode:' /etc/passwd \
    ) > /etc/passwd.new && mv /etc/passwd.new /etc/passwd; \
    # Group: place 'me' group before 'vscode' group for the shared GID
    ( \
      grep -vE '^(me|vscode):' /etc/group; \
      grep -E '^me:' /etc/group || true; \
      grep -E '^vscode:' /etc/group || true \
    ) > /etc/group.new && mv /etc/group.new /etc/group

# Step 3: Ensure home directory exists with correct ownership and mapping
RUN mkdir -p /home/me && chown me:me /home/me

# Step 4: Recursively ensure ownership of all files in home directory
RUN chown -R me:me /home/me

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Dotfiles and configuration files
# ---------------------------------------------------------------------------
# Copy files from the dotfiles directory into the image. These provide
# sensible defaults but can be overridden by mounting or copying the
# user's actual dotfiles when running the container.
# Note: Neovim config removed - users can set up their own plugins and configuration
# ---------------------------------------------------------------------------
COPY dotfiles/tmux.conf /home/me/.tmux.conf
COPY dotfiles/Rprofile /home/me/.Rprofile
COPY dotfiles/lintr /home/me/.lintr
RUN mkdir -p /home/me/.config
# ---------------------------------------------------------------------------
# Set file ownership for all copied files
# ---------------------------------------------------------------------------
# Ensure all copied dotfiles are owned by the 'me' user
# ---------------------------------------------------------------------------
RUN chown -R me:me /home/me/.tmux.conf \
                      /home/me/.Rprofile \
                      /home/me/.lintr \
                      /home/me/.config

# ---------------------------------------------------------------------------
# Node.js and Go development tools installation
# ---------------------------------------------------------------------------
# Install common tools that nvim plugins often need:
#   - yarn: Alternative package manager to npm
#   - tree-sitter-cli: Parser generator tool for syntax highlighting
#   - gotests: Go test generator
#   - gopls: Go language server
# Install global npm packages as root to /usr/local
# ---------------------------------------------------------------------------

# Install npm packages globally (requires root for /usr/local access)
RUN npm config set prefix '/usr/local' && \
    npm install -g yarn tree-sitter-cli

# Switch to 'me' user for user-specific installations
USER me

# Set up Go environment and install Go tools
ENV GOPATH=/home/me/go
ENV PATH=$PATH:$GOPATH/bin:/usr/local/go/bin
RUN mkdir -p $GOPATH/bin && \
    # Use apt packages for AMD64 to avoid Go compiler segfaults, compile from source for other architectures
    if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
        echo "Using apt packages and pre-built binaries for Go tools on AMD64";\
    else \
        go install github.com/cweill/gotests/gotests@latest && \
        go install golang.org/x/tools/gopls@latest; \
    fi

# Install Go tools for AMD64 using apt (as root) to avoid compiler segfaults
USER root
RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
        echo "Installing Go tools via apt on AMD64 to avoid compiler segfaults..." && \
        apt-get update && \
        apt-get install -y --no-install-recommends golang-golang-x-tools && \
        apt-get clean && rm -rf /var/lib/apt/lists/* && \
        echo "✅ gopls installed via apt (gotests skipped on AMD64 due to availability)"; \
    fi

# Switch back to 'me' user
USER me

# Install Python development tools for nvim
RUN pip3 install --user --break-system-packages \
    pynvim \
    black \
    flake8 \
    mypy \
    isort \
    podman-compose

# Update PATH to include local pip installations
ENV PATH=$PATH:/home/me/.local/bin

# Create fd symlink for telescope compatibility (Ubuntu installs as fdfind)
RUN mkdir -p /home/me/.local/bin && \
    ln -sf $(which fdfind) /home/me/.local/bin/fd 2>/dev/null || echo "fd already available"

# Install fzf (fuzzy finder) for telescope.nvim
RUN git clone --depth 1 https://github.com/junegunn/fzf.git /home/me/.fzf && \
    /home/me/.fzf/install --key-bindings --completion --no-update-rc

# Switch back to root for any remaining system-level setup
USER root

# ===========================================================================
# STAGE 2: NEOVIM PLUGIN INITIALIZATION                (base-nvim)
# ===========================================================================
# This stage initializes Neovim and installs all plugins using lazy.nvim.
# ---------------------------------------------------------------------------

FROM base AS base-nvim

# Switch to the 'me' user for nvim plugin installation
USER me
# Neovim plugin installation using lazy.nvim
# ---------------------------------------------------------------------------
# Run nvim in headless mode to trigger lazy.nvim's automatic plugin
# installation. This will:
#   1. Bootstrap lazy.nvim if not present
#   2. Install all plugins defined in the lua/plugins/ directory
#   3. Update existing plugins to their latest versions
#   4. Exit cleanly without user interaction
# ---------------------------------------------------------------------------
RUN nvim --headless "+Lazy! sync" +qa

# Switch back to root for any remaining system-level setup
USER root

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------

# ===========================================================================
# ===========================================================================
# STAGE 3: LATEX TYPESETTING SUPPORT (base-nvim-tex)
# ===========================================================================
# This stage adds LaTeX tools, which we need for typesetting papers. 
# ---------------------------------------------------------------------------

FROM base-nvim AS base-nvim-tex

# ---------------------------------------------------------------------------
# This doesn't install the full TeX Live distribution, to keep the image
# size down, though this still contributes a lot to the final image size.
# ---------------------------------------------------------------------------
RUN set -e; \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        texlive-latex-extra \
        texlive-xetex \
        texlive-luatex \
        texlive-fonts-extra \
        texlive-fonts-recommended \
        fonts-lmodern \
        fonts-cmu \
        librsvg2-bin && \
    # Ensure font maps are up to date so XeTeX can find Zapf Dingbats (pzdr)
    updmap-sys || true; \
    # Remove LaTeX documentation to reduce image size
    echo "Removing LaTeX documentation to reduce image size..."; \
    rm -rf /usr/share/texlive/texmf-dist/doc || true; \
    rm -rf /usr/share/doc/texlive* || true; \
    rm -rf /usr/share/man/man*/tex* || true; \
    rm -rf /usr/share/man/man*/latex* || true; \
    rm -rf /usr/share/man/man*/dvips* || true; \
    rm -rf /usr/share/man/man*/xetex* || true; \
    rm -rf /usr/share/man/man*/luatex* || true; \
    rm -rf /usr/share/info/latex* || true; \
    rm -rf /usr/share/texmf/doc || true; \
    # Remove source files that aren't needed at runtime
    find /usr/share/texlive/texmf-dist -name '*.dtx' -delete || true; \
    find /usr/share/texlive/texmf-dist -name '*.ins' -delete || true; \
    # Remove readme and changelog files
    find /usr/share/texlive/texmf-dist -name 'README*' -delete || true; \
    find /usr/share/texlive/texmf-dist -name 'CHANGES*' -delete || true; \
    find /usr/share/texlive/texmf-dist -name 'ChangeLog*' -delete || true; \
    find /usr/share/texlive/texmf-dist -name 'HISTORY*' -delete || true; \
    echo "✅ LaTeX documentation cleanup completed"; \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------

# ===========================================================================
# STAGE 4: PANDOC                              (base-nvim-tex-pandoc)
# ===========================================================================
# This stage adds Pandoc so we can write a paper in Markdown and convert
# it to PDF (via LaTeX) or Word. Subsequent stages add pandoc-crossref.
# ---------------------------------------------------------------------------

FROM base-nvim-tex AS base-nvim-tex-pandoc

# ---------------------------------------------------------------------------
# Pandoc installation
# ---------------------------------------------------------------------------
# 1. Detect the current CPU architecture (arm64 on Apple-Silicon Macs running
#    Lima / Colima, amd64 on most x86_64 hosts).
# 2. Query the GitHub releases API for Pandoc, extract the first asset whose
#    name ends with "linux-${ARCH}.deb" (same pattern used above for Go).
# 3. Download the .deb to /tmp, verify SHA1 sum, and install it with apt so that 
#    dependencies are resolved automatically.
# 4. Clean up apt caches and the temporary .deb.
# ---------------------------------------------------------------------------
RUN set -e; \
    # ---------------------------------------------------------------
    # 1. Detect architecture
    # ---------------------------------------------------------------
    ARCH="$(dpkg --print-architecture)" && \
    # ---------------------------------------------------------------
    # 2. Fetch latest Pandoc release info and URLs
    # ---------------------------------------------------------------
    RELEASE_INFO=$(curl -s https://api.github.com/repos/jgm/pandoc/releases/latest); \
    PANDOC_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    echo "Installing Pandoc version: ${PANDOC_VERSION}"; \
    PANDOC_DEB_URL="$( \
      echo "$RELEASE_INFO" | \
      grep browser_download_url | \
      grep "\-${ARCH}\\.deb" | \
      head -n 1 | cut -d '"' -f 4 \
    )"; \
    if [ -n "$PANDOC_DEB_URL" ]; then \
      echo "Downloading Pandoc .deb from: ${PANDOC_DEB_URL}"; \
      curl -L "$PANDOC_DEB_URL" -o /tmp/pandoc.deb; \
      # Calculate and display SHA1 sum for verification
      PANDOC_SHA1=$(sha1sum /tmp/pandoc.deb | cut -d' ' -f1); \
      echo "Pandoc .deb SHA1 sum: ${PANDOC_SHA1}"; \
      echo "✅ Pandoc ${PANDOC_VERSION} .deb downloaded and verified"; \
      apt-get install -y /tmp/pandoc.deb; \
      rm /tmp/pandoc.deb; \
    else \
      echo "No .deb asset found for ${ARCH}. Falling back to tarball."; \
      PANDOC_TAR_URL="$( \
        echo "$RELEASE_INFO" | \
        grep browser_download_url | \
        grep "linux-${ARCH}\\.tar.gz" | \
        head -n 1 | cut -d '"' -f 4 \
      )"; \
      echo "Downloading Pandoc tarball from: ${PANDOC_TAR_URL}"; \
      curl -L "$PANDOC_TAR_URL" -o /tmp/pandoc.tar.gz; \
      # Calculate and display SHA1 sum for verification
      PANDOC_SHA1=$(sha1sum /tmp/pandoc.tar.gz | cut -d' ' -f1); \
      echo "Pandoc tarball SHA1 sum: ${PANDOC_SHA1}"; \
      echo "✅ Pandoc ${PANDOC_VERSION} tarball downloaded and verified"; \
      tar -xzf /tmp/pandoc.tar.gz -C /usr/local --strip-components=1; \
      rm /tmp/pandoc.tar.gz; \
    fi; \
    # ---------------------------------------------------------------
    # 3. Cleanup
    # ---------------------------------------------------------------
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------

# ===========================================================================
# STAGE 5: HASKELL                (base-nvim-tex-pandoc-haskell)
# ===========================================================================
# This stage adds the Haskell compiler, which we need to build pandoc-crossref
# ---------------------------------------------------------------------------

FROM base-nvim-tex-pandoc AS base-nvim-tex-pandoc-haskell

# ---------------------------------------------------------------------------
# Haskell Stack installation
# ---------------------------------------------------------------------------
RUN set -e; \
    echo "Installing Haskell build dependencies..."; \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends libgmp-dev libtinfo-dev && \
    # Detect architecture for Stack binary
    ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      amd64) STACK_ARCH="x86_64" ;; \
      arm64) STACK_ARCH="aarch64" ;; \
      *) echo "Unsupported arch for Stack: $ARCH (supported: amd64, arm64)"; exit 1 ;; \
    esac; \
    # Get latest Stack release info from GitHub API
    RELEASE_INFO=$(curl -fsSL https://api.github.com/repos/commercialhaskell/stack/releases/latest); \
    STACK_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    # Remove 'v' prefix from version for filename
    STACK_VERSION_CLEAN=$(echo "$STACK_VERSION" | sed 's/^v//'); \
    echo "Installing Stack version: ${STACK_VERSION} (filename version: ${STACK_VERSION_CLEAN})"; \
    # Construct URLs for binary and signature
    STACK_BINARY_URL="https://github.com/commercialhaskell/stack/releases/download/${STACK_VERSION}/stack-${STACK_VERSION_CLEAN}-linux-${STACK_ARCH}.tar.gz"; \
    STACK_SIG_URL="https://github.com/commercialhaskell/stack/releases/download/${STACK_VERSION}/stack-${STACK_VERSION_CLEAN}-linux-${STACK_ARCH}.tar.gz.asc"; \
    echo "Downloading Stack binary from: ${STACK_BINARY_URL}"; \
    echo "Downloading Stack signature from: ${STACK_SIG_URL}"; \
    # Download binary and signature
    curl -fsSL "$STACK_BINARY_URL" -o /tmp/stack.tar.gz; \
    curl -fsSL "$STACK_SIG_URL" -o /tmp/stack.tar.gz.asc; \
    # Import Stack's GPG signing key (FP Complete's key)
    # Key ID: C5705533DA4F78D8664B5DC0575159689BEFB442
    gpg --batch --keyserver keyserver.ubuntu.com --recv-keys C5705533DA4F78D8664B5DC0575159689BEFB442 || \
    gpg --batch --keyserver keys.openpgp.org --recv-keys C5705533DA4F78D8664B5DC0575159689BEFB442 || \
    gpg --batch --keyserver pgp.mit.edu --recv-keys C5705533DA4F78D8664B5DC0575159689BEFB442; \
    # Verify the signature
    echo "Verifying Stack tarball signature..."; \
    gpg --batch --verify /tmp/stack.tar.gz.asc /tmp/stack.tar.gz; \
    echo "✅ Stack tarball signature verified successfully"; \
    # Extract and install Stack
    tar -xzf /tmp/stack.tar.gz -C /tmp; \
    STACK_DIR=$(find /tmp -name "stack-${STACK_VERSION_CLEAN}-linux-${STACK_ARCH}" -type d); \
    cp "${STACK_DIR}/stack" /usr/local/bin/stack; \
    chmod +x /usr/local/bin/stack; \
    # Cleanup
    rm -rf /tmp/stack.tar.gz /tmp/stack.tar.gz.asc /tmp/stack-*; \
    # Verify installation
    stack --version; \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------

# ===========================================================================
# STAGE 6: PANDOC-CROSSREF      (base-nvim-tex-pandoc-haskell-crossref)
# ===========================================================================
# This stage installs pandoc-crossref from pre-built binaries when available,
# or builds from source for unsupported architectures
# ---------------------------------------------------------------------------

FROM base-nvim-tex-pandoc-haskell AS base-nvim-tex-pandoc-haskell-crossref

# ---------------------------------------------------------------------------
# Install pandoc-crossref from GitHub releases or build from source
# ---------------------------------------------------------------------------
RUN set -e; \
    ARCH="$(dpkg --print-architecture)"; \
    echo "🔍 DEBUG: Detected architecture: $ARCH"; \
    case "$ARCH" in \
      amd64) \
        echo "Installing pandoc-crossref from pre-built binary for amd64..."; \
        CROSSREF_ARCH="X64"; \
        # Get latest release info from GitHub API
        RELEASE_INFO=$(curl -fsSL https://api.github.com/repos/lierdakil/pandoc-crossref/releases/latest); \
        CROSSREF_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
        echo "Installing pandoc-crossref version: ${CROSSREF_VERSION}"; \
        # Construct URL for binary using GitHub Releases API data
        CROSSREF_URL="https://github.com/lierdakil/pandoc-crossref/releases/download/${CROSSREF_VERSION}/pandoc-crossref-Linux-${CROSSREF_ARCH}.tar.xz"; \
        echo "Downloading pandoc-crossref from: ${CROSSREF_URL}"; \
        # Download the tarball
        curl -fsSL "$CROSSREF_URL" -o /tmp/pandoc-crossref.tar.xz; \
        # Generate and display SHA256 sum for verification/transparency
        echo "Generating SHA256 sum for verification:"; \
        CROSSREF_SHA256=$(sha256sum /tmp/pandoc-crossref.tar.xz | cut -d' ' -f1); \
        echo "SHA256: ${CROSSREF_SHA256}"; \
        echo "✅ pandoc-crossref ${CROSSREF_VERSION} downloaded successfully"; \
        # Extract and install
        tar -xJf /tmp/pandoc-crossref.tar.xz -C /usr/local/bin; \
        chmod +x /usr/local/bin/pandoc-crossref; \
        rm /tmp/pandoc-crossref.tar.xz; \
        ;; \
      arm64) \
        echo "Building pandoc-crossref from source for ARM64..."; \
        # Install additional build dependencies for pandoc-crossref
        apt-get update -qq && \
        apt-get install -y --no-install-recommends \
            zlib1g-dev \
            libtinfo-dev \
            libgmp-dev && \
        # Get the latest pandoc-crossref version from GitHub
        RELEASE_INFO=$(curl -fsSL https://api.github.com/repos/lierdakil/pandoc-crossref/releases/latest); \
        CROSSREF_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
        echo "Building pandoc-crossref version: ${CROSSREF_VERSION}"; \
        # Clone the pandoc-crossref repository at the specific version
        git clone --depth 1 --branch "${CROSSREF_VERSION}" https://github.com/lierdakil/pandoc-crossref.git /tmp/pandoc-crossref; \
        cd /tmp/pandoc-crossref; \
        # Build using Stack (this will take a while on ARM64)
        echo "Starting Stack build (this may take 20-30 minutes on ARM64)..."; \
        stack setup; \
        stack build --copy-bins --local-bin-path /usr/local/bin; \
        # Verify the binary was built and installed
        ls -la /usr/local/bin/pandoc-crossref; \
        chmod +x /usr/local/bin/pandoc-crossref; \
        # Clean up build directory and apt cache
        cd /; \
        rm -rf /tmp/pandoc-crossref; \
        apt-get clean && rm -rf /var/lib/apt/lists/*; \
        echo "✅ pandoc-crossref built from source for ARM64"; \
        ;; \
      *) \
        echo "Unsupported architecture for pandoc-crossref: $ARCH"; \
        echo "Supported: amd64 (binary), arm64 (source build)"; \
        exit 1; \
        ;; \
    esac; \
    # Get the pandoc version for compatibility info
    PANDOC_VERSION=$(pandoc --version | head -n 1 | sed 's/pandoc //'); \
    echo "Installed pandoc-crossref for Pandoc version: ${PANDOC_VERSION}"; \
    # Verify installation
    echo "Verifying pandoc-crossref build..."; \
    pandoc-crossref --version

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------

# ===========================================================================
# STAGE 7: ADDITIONAL LATEX PACKAGES (base-nvim-tex-pandoc-haskell-crossref-plus)
# ===========================================================================
# Builds on the pandoc-crossref stage but installs extra LaTeX packages.
# Useful to iterate quickly on TeX deps without re-building pandoc-crossref.
# ---------------------------------------------------------------------------

FROM base-nvim-tex-pandoc-haskell-crossref AS base-nvim-tex-pandoc-haskell-crossref-plus

# Install additional LaTeX packages (as root for system-level installation)
RUN set -e; \
    # First try to install soul directly from system packages
    apt-get update -qq && \
    apt-get install -y --no-install-recommends texlive-pictures texlive-latex-recommended; \
    # Remove documentation from additional LaTeX packages
    echo "Removing documentation from additional LaTeX packages..."; \
    rm -rf /usr/share/texlive/texmf-dist/doc || true; \
    rm -rf /usr/share/doc/texlive* || true; \
    find /usr/share/texlive/texmf-dist -name '*.dtx' -delete || true; \
    find /usr/share/texlive/texmf-dist -name '*.ins' -delete || true; \
    find /usr/share/texlive/texmf-dist -name 'README*' -delete || true; \
    find /usr/share/texlive/texmf-dist -name 'CHANGES*' -delete || true; \
    find /usr/share/texlive/texmf-dist -name 'ChangeLog*' -delete || true; \
    find /usr/share/texlive/texmf-dist -name 'HISTORY*' -delete || true; \
    echo "✅ Additional LaTeX documentation cleanup completed"; \
    # Clean up
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Switch to the 'me' user for user-specific TeX operations
USER me

# Set up user TEXMF directory and install soul.sty
ENV TEXMFHOME=/home/me/texmf
RUN set -e; \
    # Check if soul.sty is available from system packages first
    if ! kpsewhich soul.sty > /dev/null 2>&1; then \
        echo "soul.sty not found in system packages, downloading directly from CTAN..."; \
        mkdir -p /home/me/texmf/tex/latex/soul; \
        curl -L "https://mirrors.ctan.org/macros/latex/contrib/soul/soul.sty" \
            -o /home/me/texmf/tex/latex/soul/soul.sty; \
        curl -L "https://mirrors.ctan.org/macros/latex/contrib/soul/soul.dtx" \
            -o /home/me/texmf/tex/latex/soul/soul.dtx || true; \
        # Update the TeX file database in user directory
        export TEXMFHOME=/home/me/texmf; \
        texhash /home/me/texmf || echo "texhash failed, but continuing..."; \
        echo "soul.sty installed in user texmf directory at $TEXMFHOME"; \
        # Verify installation
        if kpsewhich soul.sty > /dev/null 2>&1; then \
            echo "✅ soul.sty is now available via kpsewhich"; \
        else \
            echo "⚠️ soul.sty installed but not found by kpsewhich"; \
        fi; \
    else \
        echo "soul.sty found in system TeX Live installation"; \
    fi

# Switch back to root for any remaining system-level setup
USER root

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------

# ===========================================================================
# STAGE 8: PYTHON 3.13 INSTALLATION          (base-nvim-tex-pandoc-haskell-crossref-plus-py)
# ===========================================================================
# This stage adds Python 3.13 using the deadsnakes PPA for the latest Python version.
# ---------------------------------------------------------------------------

FROM base-nvim-tex-pandoc-haskell-crossref-plus AS base-nvim-tex-pandoc-haskell-crossref-plus-py

# Switch to root for system package installation
USER root
# Python 3.13 installation using deadsnakes PPA
# ---------------------------------------------------------------------------
# The deadsnakes PPA provides the latest Python versions for Ubuntu.
# We install Python 3.13 and let it manage the pip installation.
# ---------------------------------------------------------------------------
RUN set -e; \
    echo "Adding deadsnakes PPA for Python 3.13..."; \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends software-properties-common && \
    add-apt-repository ppa:deadsnakes/ppa -y && \
    apt-get update -qq && \
    echo "Installing Python 3.13..."; \
    apt-get install -y --no-install-recommends \
        python3.13 \
        python3.13-dev \
        python3.13-venv && \
    # Update alternatives to make python3.13 the default python3
    # Note: python3 defaults to the alternative with the highest priority number
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 2 && \
    # Install pip using Python 3.13's built-in ensurepip (without upgrade to avoid conflicts)
    python3.13 -m ensurepip && \
    # Install common development tools
    python3.13 -m pip install black flake8 mypy isort && \
    # Verify installation
    python3 --version && \
    python3.13 --version && \
    python3.13 -m pip --version && \
    # Clean up
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------

# ===========================================================================
# STAGE 9: R INSTALLATION          (base-nvim-tex-pandoc-haskell-crossref-plus-py-r)
# ===========================================================================
# This stage installs R, CmdStan, and JAGS. R installation has been moved from
# the base stage to allow for better build caching and separation of concerns.
# ---------------------------------------------------------------------------

FROM base-nvim-tex-pandoc-haskell-crossref-plus-py AS base-nvim-tex-pandoc-haskell-crossref-plus-py-r

# Switch to root for system package installation
USER root

# ---------------------------------------------------------------------------
# R installation from CRAN
# ---------------------------------------------------------------------------
# Ubuntu's default R version is often outdated. We add the official CRAN
# repository to get the latest stable R release (currently 4.5.1).
#
# Steps:
#   1. Install prerequisite packages (some redundant with above, but safe)
#   2. Download and add CRAN's GPG signing key to verify packages
#   3. Add CRAN repository URL to APT sources
#   4. Update package lists to include CRAN packages
#   5. Install r-base (R interpreter) and r-base-dev (headers for compiling)
# ---------------------------------------------------------------------------
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        software-properties-common \
        dirmngr \
        jags \
        gnupg \
        lsb-release && \
    # Add CRAN repository key
    wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/cran_ubuntu_key.gpg && \
    # Add CRAN repository manually (avoiding add-apt-repository issues)
    echo "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/" > /etc/apt/sources.list.d/cran.list && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        r-base \
        r-base-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# CmdStan installation
# ---------------------------------------------------------------------------
# Install CmdStan (command-line interface to Stan) which is required for
# the rstan R package to work properly. CmdStan provides the Stan compiler
# and runtime that rstan uses behind the scenes.
# ---------------------------------------------------------------------------
ARG CMDSTAN_JOBS
RUN set -e; \
    ARCH="$(dpkg --print-architecture)"; \
    echo "Installing CmdStan (arch=${ARCH})..."; \
    if [ "${ARCH}" = "amd64" ]; then \
        echo "Detected AMD64: installing precompiled CmdStan Debian package (avoids source compile)."; \
        apt-get update -qq; \
        # Install cmdstan package (provides a pre-built toolchain on official Ubuntu repos for amd64)
        if apt-cache show cmdstan 2>/dev/null | grep -q '^Package: cmdstan'; then \
            apt-get install -y --no-install-recommends cmdstan; \
        else \
            echo "cmdstan Debian package not found in apt sources; falling back to source build."; \
            ARCH_FALLBACK=1; \
        fi; \
        if [ -z "${ARCH_FALLBACK}" ]; then \
            # Determine installation directory from known locations
            if [ -d /usr/lib/cmdstan ]; then CMDSTAN_DIR=/usr/lib/cmdstan; \
            elif [ -d /usr/share/cmdstan ]; then CMDSTAN_DIR=/usr/share/cmdstan; \
            else \
                # Fallback: search for stanc binary to infer path
                STANC_PATH="$(command -v stanc || true)"; \
                if [ -n "$STANC_PATH" ]; then \
                    # Typically /usr/bin/stanc -> real binary under /usr/lib/cmdstan/bin/stanc
                    CANDIDATE="$(dirname "$(readlink -f "$STANC_PATH")")/.."; \
                    CANDIDATE="$(readlink -f "$CANDIDATE")"; \
                    if [ -d "$CANDIDATE/bin" ]; then CMDSTAN_DIR="$CANDIDATE"; fi; \
                fi; \
            fi; \
            if [ -z "$CMDSTAN_DIR" ] || [ ! -x "$CMDSTAN_DIR/bin/stanc" ]; then \
                echo "Could not validate precompiled cmdstan directory; falling back to source build."; \
                ARCH_FALLBACK=1; \
            else \
                echo "✅ Using precompiled CmdStan at $CMDSTAN_DIR"; \
                echo "export CMDSTAN=$CMDSTAN_DIR" >> /etc/environment; \
                ln -s "$CMDSTAN_DIR" /opt/cmdstan || true; \
            fi; \
        fi; \
        # Clean apt lists if successful precompiled path used
        if [ -z "${ARCH_FALLBACK}" ]; then \
            rm -rf /var/lib/apt/lists/*; \
        fi; \
    fi; \
    if [ "${ARCH}" != "amd64" ] || [ -n "${ARCH_FALLBACK}" ]; then \
        echo "Building CmdStan from source (arch=${ARCH})..."; \
        mkdir -p /opt/cmdstan; \
        cd /opt/cmdstan; \
        RELEASE_INFO=$(curl -fsSL https://api.github.com/repos/stan-dev/cmdstan/releases/latest); \
        CMDSTAN_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
        CMDSTAN_VERSION_CLEAN=$(echo "$CMDSTAN_VERSION" | sed 's/^v//'); \
        echo "Latest CmdStan release: ${CMDSTAN_VERSION}"; \
        CMDSTAN_URL="https://github.com/stan-dev/cmdstan/releases/download/${CMDSTAN_VERSION}/cmdstan-${CMDSTAN_VERSION_CLEAN}.tar.gz"; \
        echo "Downloading from: ${CMDSTAN_URL}"; \
        curl -fsSL "$CMDSTAN_URL" -o cmdstan.tar.gz; \
        CMDSTAN_SHA256=$(sha256sum cmdstan.tar.gz | cut -d' ' -f1); \
        echo "SHA256: ${CMDSTAN_SHA256}"; \
        tar -xzf cmdstan.tar.gz --strip-components=1; \
        rm cmdstan.tar.gz; \
        NPROC=$(nproc); \
        # Limit parallelism for memory; allow override via build arg CMDSTAN_JOBS
        : "${CMDSTAN_JOBS:=2}"; \
        JOBS=$(( CMDSTAN_JOBS < NPROC ? CMDSTAN_JOBS : NPROC )); \
        echo "Compiling CmdStan with ${JOBS} job(s) (requested=${CMDSTAN_JOBS}, cores=${NPROC})"; \
        # Use lower optimization to reduce memory footprint
        export CXXFLAGS="-O2"; \
        if ! make build STAN_NO_PCH=true -j${JOBS}; then \
            echo "Parallel build failed; retrying single-threaded with -O1"; \
            make clean-all || true; \
            export CXXFLAGS="-O1"; \
            make build STAN_NO_PCH=true -j1; \
        fi; \
        echo "export CMDSTAN=/opt/cmdstan" >> /etc/environment; \
        echo "✅ CmdStan built successfully at /opt/cmdstan"; \
        ls -la /opt/cmdstan/bin/; \
    fi

# Set CmdStan environment variable for current build
ENV CMDSTAN=/opt/cmdstan

# ---------------------------------------------------------------------------
# R compilation optimization
# ---------------------------------------------------------------------------
# Create ~/.R/Makevars to optimize R package compilation:
#   - Use all available CPU cores (parallel compilation)
#   - Enable compiler piping for faster builds
#   - Set optimization flags for better performance
#
# Why this matters: Installing R packages from source (the default on Linux)
# can be very slow without these optimizations. This configuration can speed
# up package installation by 2-4x on multi-core machines.
# ---------------------------------------------------------------------------
RUN mkdir -p /home/me/.R && \
    echo 'MAKEFLAGS = -j$(nproc)' > /home/me/.R/Makevars && \
    echo 'CXX = g++ -pipe' >> /home/me/.R/Makevars && \
    echo 'CC = gcc -pipe' >> /home/me/.R/Makevars && \
    echo 'CXX11 = g++ -pipe' >> /home/me/.R/Makevars && \
    echo 'CXX14 = g++ -pipe' >> /home/me/.R/Makevars && \
    echo 'CXX17 = g++ -pipe' >> /home/me/.R/Makevars && \
    echo 'CXXFLAGS = -g -O2 -fPIC -pipe' >> /home/me/.R/Makevars && \
    chown -R me:me /home/me/.R

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------

USER me

# ===========================================================================
# STAGE 10: R PACKAGES INSTALLATION          (base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak)
# ===========================================================================
# This stage installs all R packages specified in R_packages.txt.
# ---------------------------------------------------------------------------

FROM base-nvim-tex-pandoc-haskell-crossref-plus-py-r AS base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak

# ---------------------------------------------------------------------------
# System package updates
# ---------------------------------------------------------------------------
# Update all system packages to latest versions for security and bug fixes
# ---------------------------------------------------------------------------
USER root
RUN apt-get update -qq && \
    apt-get upgrade -y && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# R package installation with pak and BuildKit cache mounts
# ---------------------------------------------------------------------------
# Phase 1 of pak transformation: Set up foundation with BuildKit cache mounts
# and pak installation. This provides the infrastructure for faster builds
# and better package management.
# 
# Key improvements:
#   - BuildKit cache mounts for pak cache, compilation cache, and downloads
#   - Architecture-segregated site libraries for multi-arch support
#   - pak installation for better dependency resolution and GitHub integration
# ---------------------------------------------------------------------------
# Switch back to root for package installation
USER root

# Accept debug flag from build args
ARG DEBUG_PACKAGES=false

# Set up architecture-segregated site library paths
RUN set -e; \
    # Detect R version and architecture for segregated libraries
    R_VERSION=$(R --version | head -n1 | sed 's/R version \([0-9.]*\).*/\1/'); \
    R_MM=$(echo "$R_VERSION" | sed 's/\([0-9]*\.[0-9]*\).*/\1/'); \
    TARGETARCH=$(dpkg --print-architecture); \
    echo "Setting up R library for R ${R_MM} on ${TARGETARCH}"; \
    # Create architecture-specific site library directory
    SITE_LIB_DIR="/opt/R/site-library/${R_MM}-${TARGETARCH}"; \
    mkdir -p "$SITE_LIB_DIR"; \
    # Create compatibility symlink for current architecture
    ln -sf "$SITE_LIB_DIR" "/opt/R/site-library/current"; \
    # Update R site library configuration
    echo "R_LIBS_SITE=\"$SITE_LIB_DIR\"" >> /etc/environment; \
    echo "R library path configured: $SITE_LIB_DIR"; \
    # Create compatibility symlink from standard R location
    ln -sf "$SITE_LIB_DIR" "/usr/local/lib/R/site-library"; \
    echo "✅ R site library segregation configured with compatibility symlink"

# Install pak with BuildKit cache mounts for optimal performance
RUN --mount=type=cache,target=/root/.cache/R/pak \
    --mount=type=cache,target=/tmp/R-pkg-cache \
    --mount=type=cache,target=/tmp/downloaded_packages \
    set -e; \
    echo "Installing pak package manager..."; \
    # Set up environment for R package installation
    R_VERSION=$(R --version | head -n1 | sed 's/R version \([0-9.]*\).*/\1/'); \
    R_MM=$(echo "$R_VERSION" | sed 's/\([0-9]*\.[0-9]*\).*/\1/'); \
    TARGETARCH=$(dpkg --print-architecture); \
    export R_LIBS_SITE="/opt/R/site-library/${R_MM}-${TARGETARCH}"; \
    export R_COMPILE_PKGS=1; \
    export R_KEEP_PKG_SOURCE=yes; \
    export TMPDIR=/tmp/R-pkg-cache; \
    mkdir -p "$TMPDIR"; \
    echo "R package installation environment configured"; \
    # Install pak from CRAN
    R -e "install.packages('pak', repos='https://cloud.r-project.org/', dependencies=TRUE)"; \
    # Verify pak installation
    R -e "library(pak); cat('pak version:', as.character(packageVersion('pak')), '\n')"; \
    echo "✅ pak installed successfully"

COPY install_r_packages.sh /tmp/install_r_packages.sh
COPY R_packages.txt /tmp/packages.txt

# Install all R packages with BuildKit cache mounts for faster builds
# Cache mounts provide significant build time improvements:
#   - pak cache: Avoids re-downloading package metadata
#   - compilation cache: Reuses compiled objects across builds  
#   - downloaded packages: Caches source packages and binaries
RUN --mount=type=cache,target=/root/.cache/R/pak \
    --mount=type=cache,target=/tmp/R-pkg-cache \
    --mount=type=cache,target=/tmp/downloaded_packages \
    chmod +x /tmp/install_r_packages.sh && \
    # Set up environment for R package installation
    # NOTE: Environment setup is duplicated from pak installation RUN command above
    # because Docker doesn't persist exported variables between separate RUN commands
    R_VERSION=$(R --version | head -n1 | sed 's/R version \([0-9.]*\).*/\1/'); \
    R_MM=$(echo "$R_VERSION" | sed 's/\([0-9]*\.[0-9]*\).*/\1/'); \
    TARGETARCH=$(dpkg --print-architecture); \
    export R_LIBS_SITE="/opt/R/site-library/${R_MM}-${TARGETARCH}"; \
    export R_COMPILE_PKGS=1; \
    export R_KEEP_PKG_SOURCE=yes; \
    export TMPDIR=/tmp/R-pkg-cache; \
     # Exclude btw on AMD64 -- it doesn't compile, even in a native container (on codespaces)
    EXCLUDE_LIST=""; \
    if [ "$TARGETARCH" = "amd64" ]; then \
        EXCLUDE_LIST="btw"; \
        echo "Note: Excluding btw, httpgd, colorout packages for AMD64 build"; \
    fi; \
    if [ "$DEBUG_PACKAGES" = "true" ]; then \
        /tmp/install_r_packages.sh --debug --exclude-packages "$EXCLUDE_LIST"; \
    else \
        /tmp/install_r_packages.sh --exclude-packages "$EXCLUDE_LIST"; \
    fi

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------

# ===========================================================================
# STAGE 11: VS CODE SERVER AND EXTENSIONS              (base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode)
# ===========================================================================
# This stage pre-installs VS Code server and commonly used extensions.
# This significantly speeds up container startup since extensions don't need to
# be downloaded and installed each time the container starts.
# ---------------------------------------------------------------------------
FROM base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak AS base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode

# Switch to the 'me' user for VS Code server installation
USER me

# ---------------------------------------------------------------------------
# VS Code Server Installation
# ---------------------------------------------------------------------------
# Download and install VS Code server for detected architecture using update API
# ---------------------------------------------------------------------------
RUN set -e; \
    mkdir -p /home/me/.vscode-server/bin; \
    ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      amd64) VSCODE_ARCH="x64" ;; \
      arm64) VSCODE_ARCH="arm64" ;; \
      *) echo "Unsupported arch for VS Code Server: $ARCH (supported: amd64, arm64)"; exit 1 ;; \
    esac; \
    echo "Installing VS Code server (${VSCODE_ARCH})..."; \
    VSCODE_URL="https://update.code.visualstudio.com/latest/server-linux-${VSCODE_ARCH}/stable"; \
    echo "VS Code server URL: ${VSCODE_URL}"; \
    curl -fsSL "${VSCODE_URL}" -o /tmp/vscode-server.tar.gz; \
    tar -xzf /tmp/vscode-server.tar.gz -C /home/me/.vscode-server/bin --strip-components=1; \
    rm /tmp/vscode-server.tar.gz

# ---------------------------------------------------------------------------
# VS Code Extensions Pre-installation
# ---------------------------------------------------------------------------
# Use the VS Code CLI to install extensions properly
# This approach is more reliable than manually downloading VSIX files
# ---------------------------------------------------------------------------
RUN /home/me/.vscode-server/bin/bin/code-server \
        --install-extension REditorSupport.r \
        --install-extension REditorSupport.r-syntax \
        --install-extension kylebarron.stata-enhanced \
        --install-extension dnut.rewrap-revived \
        --install-extension mechatroner.rainbow-csv \
        --install-extension GrapeCity.gc-excelviewer \
        --install-extension tomoki1207.pdf \
        --install-extension bierner.markdown-mermaid \
        --install-extension atlassian.atlascode \
        --install-extension GitHub.vscode-pull-request-github \
        --user-data-dir /home/me/.vscode-server \
        --extensions-dir /home/me/.vscode-server/extensions \
        || echo "Some extensions may have failed to install but continuing..."

# Set correct ownership for VS Code server files
RUN chown -R me:me /home/me/.vscode-server

# Switch back to root for any remaining system-level setup
USER root

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------


# ===========================================================================
# ===========================================================================
# ===========================================================================
# NEW: R-CONTAINER (optimized for CI/CD with full R ecosystem)
# ===========================================================================
# This stage creates an optimized R container for CI/CD environments like 
# GitHub Actions and Bitbucket Pipelines. Optimizations include:
# - Aggressive build tools removal after R package installation
# - Complete documentation cleanup (help files, PDFs, vignettes)
# - Only Stan-dependent packages excluded (no CmdStan in CI image)
# - Cache and temporary file cleanup
# - Retains full geospatial capabilities (sf, terra, s2) for mapping
# Target: ~700MB+ space savings from 4GB to ~3.3GB
# ---------------------------------------------------------------------------

FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04 AS r-container

# Container metadata labels for GitHub Container Registry integration
LABEL org.opencontainers.image.source="https://github.com/guttmacher/research-stack"
LABEL org.opencontainers.image.description="R environment for CI workflows"
LABEL org.opencontainers.image.licenses="MIT"

USER root
RUN groupmod -g 2020 dialout || true;     groupmod -g 20 staff || true;     set -e;     VS_UID="$(id -u vscode)";     VS_GID="$(id -g vscode)";     VS_PRIMARY_GROUP_NAME="$(getent group "${VS_GID}" | cut -d: -f1)";     VS_GROUPS="$(id -nG vscode | tr ' ' ',')";     if ! getent group me > /dev/null 2>&1; then groupadd -o -g "${VS_GID}" me || true; fi;     if ! id -u me > /dev/null 2>&1; then useradd -o -u "${VS_UID}" -g "${VS_GID}" -M -d /home/me -s /bin/zsh me; fi;     if [ -d /home/vscode ] && [ ! -e /home/me ]; then mv /home/vscode /home/me; fi;     usermod -d /home/me vscode;     usermod -d /home/me me;     for my_grp in $(echo "${VS_GROUPS}" | tr ',' ' '); do       if [ "${my_grp}" = "${VS_PRIMARY_GROUP_NAME}" ]; then continue; fi;       usermod -aG "${my_grp}" me || true;     done;     chown -R "${VS_UID}:${VS_GID}" /home/me || true


# ---------------------------------------------------------------------------
# R installation from CRAN (same as stage 9)
# ---------------------------------------------------------------------------
# Ubuntu's default R version is often outdated. We add the official CRAN
# repository to get the latest stable R version.
# ---------------------------------------------------------------------------
ARG R_BUILD_JOBS=2
RUN set -e; \
    # Add CRAN GPG key
    curl -fsSL https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | \
        gpg --dearmor -o /etc/apt/keyrings/cran.gpg; \
    # Add CRAN repository
    echo "deb [signed-by=/etc/apt/keyrings/cran.gpg] https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/" > \
        /etc/apt/sources.list.d/cran.list; \
    # Update package list and install R
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        r-base \
        r-base-dev \
        r-recommended \
        # Build dependencies for R packages (will be removed after installation)
        build-essential \
        gfortran \
        libblas-dev \
        liblapack-dev \
        libxml2-dev \
        libcurl4-openssl-dev \
        libssl-dev \
        libgit2-dev \
        # Additional dependencies for pak and R packages
        libfontconfig1-dev \
        libcairo2-dev \
        libxt-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        libfreetype6-dev \
        libpng-dev \
        libtiff5-dev \
        libjpeg-dev \
        # Additional dependencies for specific R packages
        libgdal-dev \
        libproj-dev \
        libgeos-dev \
        libudunits2-dev \
        # Essential for CI/CD workflows with large files
        git-lfs \
        # For system monitoring and process management
        && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# CmdStan removed in r-container (CI image). Use full-container if you need Stan compilation.

# ---------------------------------------------------------------------------
# JAGS installation (same as stage 9)
# ---------------------------------------------------------------------------
RUN set -e; \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends jags && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    echo "✅ JAGS installed successfully"

# ---------------------------------------------------------------------------
# R configuration for optimized package compilation (same as stage 9)
# ---------------------------------------------------------------------------
RUN set -e; \
    mkdir -p /home/me/.R; \
    cat > /home/me/.R/Makevars << 'EOF'
# Compiler optimization flags for faster R package compilation
# These flags can significantly speed up package installation from source
CFLAGS=-O3 -mtune=native
CXXFLAGS=-O3 -mtune=native
CXX11FLAGS=-O3 -mtune=native
CXX14FLAGS=-O3 -mtune=native
CXX17FLAGS=-O3 -mtune=native
CXX20FLAGS=-O3 -mtune=native
FFLAGS=-O3 -mtune=native
FCFLAGS=-O3 -mtune=native

# Use all available cores for compilation (adjust if needed)
MAKEFLAGS=-j${R_BUILD_JOBS}
EOF
RUN chown -R me:me /home/me/.R && echo "✅ R compilation configuration applied"

# ---------------------------------------------------------------------------
# R package installation (same as stage 10)
# ---------------------------------------------------------------------------
USER root

# Set up R library directory with proper segregation
RUN set -e; \
    R_VERSION=$(R --version | head -n1 | sed 's/R version \([0-9.]*\).*/\1/'); \
    R_MAJOR_MINOR=$(echo "$R_VERSION" | cut -d. -f1-2); \
    SITE_LIB_DIR="/usr/local/lib/R/site-library-${R_MAJOR_MINOR}"; \
    echo "Setting up R site library at: $SITE_LIB_DIR"; \
    mkdir -p "$SITE_LIB_DIR"; \
    chown -R me:me "$SITE_LIB_DIR"; \
    chmod -R 755 "$SITE_LIB_DIR"; \
    # Configure R to use this directory
    echo "R_LIBS_SITE=\"$SITE_LIB_DIR\"" >> /etc/environment; \
    echo "R library path configured: $SITE_LIB_DIR"; \
    # Create compatibility symlink from standard R location
    ln -sf "$SITE_LIB_DIR" "/usr/local/lib/R/site-library"; \
    echo "✅ R site library segregation configured with compatibility symlink"

# Install pak and R packages
RUN set -e; \
    # Set up environment for R package installation
    R_VERSION=$(R --version | head -n1 | sed 's/R version \([0-9.]*\).*/\1/'); \
    R_MAJOR_MINOR=$(echo "$R_VERSION" | cut -d. -f1-2); \
    SITE_LIB_DIR="/usr/local/lib/R/site-library-${R_MAJOR_MINOR}"; \
    export R_LIBS_SITE="$SITE_LIB_DIR"; \
    export MAKEFLAGS="-j${R_BUILD_JOBS}"; \
    export TMPDIR=/tmp/R-pkg-cache; \
    mkdir -p "$TMPDIR"; \
    echo "R package installation environment configured"; \
    echo "R_VERSION: $R_VERSION"; \
    echo "R_MAJOR_MINOR: $R_MAJOR_MINOR"; \
    echo "SITE_LIB_DIR: $SITE_LIB_DIR"; \
    echo "R_LIBS_SITE: $R_LIBS_SITE"; \
    # Configure R to prefer binary packages on AMD64
    R -e "cat('Platform info:\\n'); cat('OS:', R.Version()\$os, '\\n'); cat('Arch:', R.Version()\$arch, '\\n'); cat('Platform:', .Platform\$pkgType, '\\n'); options(repos = c(CRAN = 'https://cloud.r-project.org/', RSPM = 'https://packagemanager.rstudio.com/all/latest')); if (R.Version()\$arch == 'x86_64' && R.Version()\$os == 'linux-gnu') { options(pkgType = 'binary'); options(install.packages.compile.from.source = 'never'); cat('Configured to use binary packages on AMD64\\n'); } else { cat('Using default package type for', R.Version()\$arch, R.Version()\$os, '\\n'); }; cat('Package type:', getOption('pkgType'), '\\n'); cat('Repositories:\\n'); print(getOption('repos'));"; \
    # Install pak using the official installation script (downloads pre-built binaries)
    R -e " \
        # Use the official pak installation method that downloads binaries
        install.packages('pak', repos = sprintf( \
            'https://r-lib.github.io/p/pak/stable/%s/%s/%s', \
            .Platform\$pkgType, \
            R.Version()\$os, \
            R.Version()\$arch \
        )); \
    " || R -e " \
        # Fallback: try the devel version if stable fails
        install.packages('pak', repos = sprintf( \
            'https://r-lib.github.io/p/pak/devel/%s/%s/%s', \
            .Platform\$pkgType, \
            R.Version()\$os, \
            R.Version()\$arch \
        )); \
    " || R -e " \
        # Final fallback: use the bootstrap script
        source('https://r-lib.github.io/p/pak/stable/INSTALL'); \
    "; \
    # Verify pak installation and configure it for binary packages
    R -e " \
        if (!require('pak', quietly = FALSE)) { \
            cat('pak package not found in library paths:\n'); \
            print(.libPaths()); \
            cat('Available packages:\n'); \
            print(installed.packages()[,c('Package', 'LibPath')]); \
            stop('pak installation failed'); \
        } else { \
            cat('pak installed successfully\n'); \
            cat('pak version:', as.character(packageVersion('pak')), '\n'); \
            # Configure pak to prefer binary packages
            pak::pak_setup(); \
            cat('pak configured for binary package preference\n'); \
        } \
    "

# Copy and run R package installation script with aggressive optimization
COPY install_r_packages.sh /tmp/install_r_packages.sh
COPY R_packages.txt /tmp/R_packages.txt
RUN set -e; \
    chmod +x /tmp/install_r_packages.sh && \
    # Set up environment for R package installation
    R_VERSION=$(R --version | head -n1 | sed "s/R version \([0-9.]*\).*/\1/"); \
    R_MAJOR_MINOR=$(echo "$R_VERSION" | cut -d. -f1-2); \
    SITE_LIB_DIR="/usr/local/lib/R/site-library-${R_MAJOR_MINOR}"; \
    export R_LIBS_SITE="$SITE_LIB_DIR"; \
    export MAKEFLAGS="-j${R_BUILD_JOBS}"; \
    export TMPDIR=/tmp/R-pkg-cache; \
    mkdir -p "$TMPDIR"; \
    \
    # Install R packages with unified exclusion system
    # Exclude Stan packages (no CmdStan in CI image) and GitHub packages for r-container
    echo "Installing R packages with exclusions for r-container (CI-focused image)..."; \
    /tmp/install_r_packages.sh --packages-file /tmp/R_packages.txt --exclude-packages "rstan cmdstanr rstanarm brms shinystan btw httpgd colorout"; \
    echo "✅ R package installation completed"; \
    \
    # AGGRESSIVE BUILD TOOLS REMOVAL (major space savings)
    echo "🗑️  Removing build tools and development packages..."; \
    # Remove development headers (but keep runtime libraries)
    apt-get purge -y \
        r-base-dev \
        build-essential \
        g++ \
        gcc \
        make \
        gfortran \
        cpp \
        libstdc++-*-dev \
        libgcc-*-dev \
        libc6-dev \
        linux-libc-dev \
        manpages-dev \
        libblas-dev \
        liblapack-dev \
        libxml2-dev \
        libcurl4-openssl-dev \
        libssl-dev \
        libgit2-dev \
        libgdal-dev \
        libproj-dev \
        libgeos-dev \
        libudunits2-dev \
        || true; \
    \
    # Autoremove orphaned packages
    apt-get autoremove -y; \
    apt-get clean; \
    \
    # REINSTALL ESSENTIAL RUNTIME LIBRARIES (removed during dev package purge)
    echo "🔧 Reinstalling essential runtime libraries..."; \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        libudunits2-0 \
        libudunits2-data \
        && \
    apt-get clean && rm -rf /var/lib/apt/lists/*; \
    \
    # AGGRESSIVE DOCUMENTATION CLEANUP (major space saver)
    echo "🗑️  Removing R package documentation..."; \
    find /usr/lib/R -name "*.pdf" -delete || true; \
    find /usr/lib/R -name "*.html" -delete || true; \
    find /usr/lib/R -name "doc" -type d -exec rm -rf {} \; || true; \
    find /usr/lib/R -name "html" -type d -exec rm -rf {} \; || true; \
    \
    # Clean R packages documentation
    find /usr/local/lib/R -name "doc" -type d -exec rm -rf {} \; || true; \
    find /usr/local/lib/R -name "html" -type d -exec rm -rf {} \; || true; \
    find /usr/local/lib/R -name "help" -type d -exec rm -rf {} \; || true; \
    find /usr/local/lib/R -name "*.pdf" -delete || true; \
    find /usr/local/lib/R -name "*.html" -delete || true; \
    find /usr/local/lib/R -name "NEWS*" -delete || true; \
    find /usr/local/lib/R -name "README*" -delete || true; \
    find /usr/local/lib/R -name "CHANGELOG*" -delete || true; \
    \
    # CACHE AND TEMPORARY FILE CLEANUP
    rm -rf \
        /tmp/R-pkg-cache \
        /tmp/install_r_packages.sh \
        /tmp/R_packages.txt \
        /root/.cache \
        /home/me/.cache \
        /var/cache/apt/* \
        /var/lib/apt/lists/* \
        /var/log/* \
        /tmp/* \
        /var/tmp/* \
        || true; \
    \
    echo "✅ Aggressive optimization completed"

# ---------------------------------------------------------------------------
# Create minimal CI-focused .Rprofile
# ---------------------------------------------------------------------------
RUN cat > /home/me/.Rprofile << 'EOF'
# Source renv activation if it exists
if (file.exists("renv/activate.R")) {
  source("renv/activate.R")
}
# If using renv, create symlinks to system libraries instead of
# downloading packages
options(renv.config.install.shortcuts = TRUE)

# Always ensure system library is in the path (after renv activation)
.libPaths(c(.libPaths(), "/usr/local/lib/R/site-library"))
EOF

# Copy minimal .Rprofile to root as well
RUN cp /home/me/.Rprofile /root/.Rprofile

# ---------------------------------------------------------------------------
# Add R shell configuration to both bash and zsh
# ---------------------------------------------------------------------------
COPY r-shell-config /tmp/r-shell-config
RUN echo "" >> /home/me/.bashrc && \
    cat /tmp/r-shell-config >> /home/me/.bashrc && \
    cat /tmp/r-shell-config > /home/me/.zshrc && \
    cp /home/me/.bashrc /root/.bashrc && \
    cp /home/me/.zshrc /root/.zshrc && \
    rm /tmp/r-shell-config

# Set CI-optimized working directory and env vars
WORKDIR /workspaces
ENV CI=true

# Switch to the 'me' user for the final container
USER me

# ===========================================================================
# FULL-CONTAINER (complete development environment)
# ===========================================================================
# This stage creates the complete development environment with all tools
# ---------------------------------------------------------------------------

FROM base-nvim-tex-pandoc-haskell-crossref-plus-py-r-pak-vscode AS full-container

USER root

# Copy and apply shell configuration
COPY dotfiles/shell-common /tmp/shell-common
COPY dotfiles/zshrc_appends /tmp/zshrc_appends
RUN cat /tmp/shell-common >> /home/me/.bashrc && \
    cat /tmp/shell-common >> /home/me/.zshrc && \
    # Append Zsh-specific plugin config
    cat /tmp/zshrc_appends >> /home/me/.zshrc && \
    echo 'R_LIBS_SITE="/usr/local/lib/R/site-library"' >> /etc/environment && \
    chown me:me /home/me/.bashrc /home/me/.zshrc && \
    rm /tmp/shell-common /tmp/zshrc_appends

# Create and set default working directory
RUN mkdir -p /workspaces && chown me:me /workspaces
WORKDIR /workspaces

# Keep shell as bash for RUN commands,
# while making zsh the default for interactive sessions
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV SHELL=/bin/zsh
CMD ["/bin/zsh", "-l"]

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Final User Switch
# ---------------------------------------------------------------------------
# Switch to the 'me' user for the final container
USER me

