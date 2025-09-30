#!/bin/bash
# install_r_packages.sh - R package installer with pak support (Phase 1)
# 
# Phase 1 Implementation: Foundation setup with pak integration
# - Installs CRAN packages using pak for better dependency resolution
# - Maintains compatibility with existing special package handling
# - Adds pak-based installation for GitHub packages
# - Preserves current error reporting and debugging features

# Configuration
PACKAGES_FILE="/tmp/packages.txt"
DEBUG_MODE=false
EXCLUDE_PACKAGES=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        --packages-file)
            PACKAGES_FILE="$2"
            shift 2
            ;;
        --exclude-packages)
            EXCLUDE_PACKAGES="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--debug] [--packages-file FILE] [--exclude-packages 'pkg1 pkg2 pkg3']"
            exit 1
            ;;
    esac
done

# Check if packages file exists
if [[ ! -f "$PACKAGES_FILE" ]]; then
    echo "❌ Package file not found: $PACKAGES_FILE"
    exit 1
fi

# Read packages from file, removing empty lines
mapfile -t packages < <(grep -v '^\s*$' "$PACKAGES_FILE")
total_packages=${#packages[@]}

if [[ $total_packages -eq 0 ]]; then
    echo "ℹ️  No packages to install"
    exit 0
fi

echo "📦 Installing $total_packages R packages using pak..."
echo "🕒 Start time: $(date)"
if [[ -n "$EXCLUDE_PACKAGES" ]]; then
    echo "⏭️  Excluding packages: $EXCLUDE_PACKAGES"
fi
echo

# Function to check if a package should be excluded
is_package_excluded() {
    local package="$1"
    if [[ -n "$EXCLUDE_PACKAGES" ]]; then
        # Check if package is in the exclusion list (space-separated)
        for excluded_pkg in $EXCLUDE_PACKAGES; do
            if [[ "$package" == "$excluded_pkg" ]]; then
                return 0  # Package is excluded
            fi
        done
    fi
    return 1  # Package is not excluded
}

start_time=$(date +%s)
installed_count=0
failed_packages=()

# Function to install packages using pak with simple progress reporting
install_packages_with_pak() {
    local packages_list="$1"
    echo "📦 Installing CRAN packages with pak..."
    
    # Create R script for pak installation with proper binary configuration
    local r_script="
    library(pak)
    
    # Configure pak and R for binary packages on AMD64
    if (R.Version()\$arch == 'x86_64' && R.Version()\$os == 'linux-gnu') {
        # The key is to use the correct repository that provides binary packages
        # PPM (Posit Package Manager) provides binary packages for Linux
        ppm_url <- 'https://packagemanager.rstudio.com/cran/__linux__/jammy/latest'
        
        # Configure R options for binary packages
        options(pkgType = 'binary')
        options(install.packages.compile.from.source = 'never')
        options(repos = c(
            CRAN = ppm_url,
            RSPM = ppm_url
        ))
        
        # Configure pak basic settings
        tryCatch({
            pak::pak_config_set('dependencies', TRUE)
            pak::pak_config_set('ask', FALSE)
            cat('Configured pak basic settings\\n')
        }, error = function(e) {
            cat('Warning: pak basic configuration failed\\n')
        })
        
        cat('Configured for binary packages on AMD64 using PPM\\n')
        cat('Repository URL:', ppm_url, '\\n')
    }
    
    # Read packages from file
    packages <- readLines('$PACKAGES_FILE')
    packages <- packages[packages != '']  # Remove empty lines
    
    cat('Installing', length(packages), 'packages with pak...\\n')
    cat('Platform:', R.Version()\$arch, R.Version()\$os, '\\n')
    cat('R Package type preference:', getOption('pkgType'), '\\n')
    cat('Repository:', getOption('repos')[['CRAN']], '\\n')
    
    # Install packages with pak - suppress verbose output unless there's an error
    tryCatch({
        cat('Starting pak installation...\\n')
        pak::pkg_install(packages, ask = FALSE)
        cat('SUCCESS: All CRAN packages installed with pak\\n')
    }, error = function(e) {
        cat('PAK_ERROR:', conditionMessage(e), '\\n')
        cat('Platform details for debugging:\\n')
        cat('Compile from source setting:', getOption('install.packages.compile.from.source'), '\\n')
        quit(status = 1)
    })
    "
    
    # Execute pak installation - capture output to show only on failure
    local pak_output
    pak_output=$(echo "$r_script" | R --slave --no-restore 2>&1)
    local pak_exit_code=$?
    
    if [[ $pak_exit_code -eq 0 ]]; then
        echo "✅ CRAN packages installed successfully with pak"
        # Show just the success message from pak output
        echo "$pak_output" | grep -E "(SUCCESS|Configured|Installing.*packages|Repository:)"
        installed_count=$((installed_count + total_packages))
        return 0
    else
        echo "❌ pak installation failed (exit code: $pak_exit_code), falling back to individual package installation"
        echo "pak error details:"
        echo "$pak_output" | sed 's/^/  /'
        return 1
    fi
}

# Function to install a single package (fallback method)
install_package_individual() {
    local package="$1"
    local r_command="
    pkg <- '$package'
    
    # Configure binary packages on AMD64 (same as Dockerfile configuration)
    if (R.Version()\$arch == 'x86_64' && R.Version()\$os == 'linux-gnu') {
        options(pkgType = 'binary')
        options(install.packages.compile.from.source = 'never')
        options(repos = c(
            CRAN = 'https://cloud.r-project.org/',
            RSPM = 'https://packagemanager.rstudio.com/all/latest'
        ))
    }
    
    if (require(pkg, character.only=TRUE, quietly=TRUE)) { 
        cat('ALREADY_INSTALLED\\n') 
    } else { 
        # Show platform and method info upfront
        cat('INSTALLING_INFO:', R.Version()\$arch, R.Version()\$os, 'pkgType=', getOption('pkgType'), 'compile=', getOption('install.packages.compile.from.source'), '\\n')
        
        start_time <- Sys.time()
        
        # Capture detailed installation output only for debugging failures
        tryCatch({
            # Attempt installation - quiet for successful installs
            install.packages(pkg, repos=getOption('repos'), dependencies=TRUE, quiet=TRUE)
            
            end_time <- Sys.time()
            duration <- round(as.numeric(difftime(end_time, start_time, units = 'secs')), 1)
            
            if (require(pkg, character.only=TRUE, quietly=TRUE)) {
                cat('INSTALL_SUCCESS:', duration, 'seconds\\n')
            } else {
                # Package installed but failed to load - show details
                cat('INSTALL_FAILED: Package installed but failed to load\\n')
            }
        }, error = function(e) {
            # Installation failed - show detailed debug info
            end_time <- Sys.time()
            duration <- round(as.numeric(difftime(end_time, start_time, units = 'secs')), 1)
            cat('INSTALL_ERROR after', duration, 'seconds\\n')
            cat('Error message:', conditionMessage(e), '\\n')
            
            # Try to get more details about the failure
            available_pkgs <- available.packages()
            if (pkg %in% rownames(available_pkgs)) {
                cat('Package found in repository\\n')
            } else {
                cat('WARNING: Package not found in available packages\\n')
            }
        })
    }"
    
    # Extract platform info first to show in the progress line
    local platform_info
    platform_info=$(echo "
    # Configure binary packages on AMD64
    if (R.Version()\$arch == 'x86_64' && R.Version()\$os == 'linux-gnu') {
        options(pkgType = 'binary')
    }
    cat(R.Version()\$arch, R.Version()\$os, 'pkgType=', getOption('pkgType'))
    " | R --slave --no-restore 2>/dev/null | tr '\n' ' ')
    
    echo "📦 Installing $package [$platform_info]..."
    package_start=$(date +%s)
    
    # Capture R output
    local r_output
    r_output=$(echo "$r_command" | R --slave --no-restore 2>&1)
    
    # Show the installation info line
    echo "$r_output" | grep "INSTALLING_INFO:" | sed 's/INSTALLING_INFO: /  Method: /'
    
    # Check if the output contains success indicators
    if echo "$r_output" | grep -q -E "(INSTALL_SUCCESS|ALREADY_INSTALLED)"; then
        local duration
        duration=$(echo "$r_output" | grep "INSTALL_SUCCESS:" | sed 's/.*: //' | sed 's/ seconds/s/')
        if [[ -n "$duration" ]]; then
            echo "  ✅ Success in $duration"
        else
            echo "  ✅ Already installed"
        fi
        ((installed_count++))
        return 0
    else
        echo "  ❌ Failed"
        # Show detailed output only for failed packages
        echo "$r_output" | grep -v "INSTALLING_INFO:" | sed 's/^/    /'
        
        # Extract error message for summary
        local error_msg
        error_msg=$(echo "$r_output" | grep -E "(INSTALL_ERROR|INSTALL_FAILED)" | head -1 | sed 's/.*: //')
        if [[ -n "$error_msg" ]]; then
            failed_packages+=("$package: $error_msg")
        else
            failed_packages+=("$package: Unknown error")
        fi
        return 1
    fi
}

# Try pak installation first, fall back to individual installation if needed
if ! install_packages_with_pak; then
    echo "Falling back to individual package installation..."
    installed_count=0  # Reset counter for individual installation
    
    # Install packages individually
    for package in "${packages[@]}"; do
        # Skip empty lines or lines with only whitespace
        [[ -z "${package// }" ]] && continue
        install_package_individual "$package"
    done
fi

# Install additional packages using pak where possible
echo
echo "📦 Installing additional packages ..."

# Install mcmcplots from CRAN archive using install.packages() (pak fails with this package)
echo -n "📦 Installing mcmcplots from CRAN archive with install.packages()... "
mcmcplots_command="
cat('📦 Building mcmcplots...\\n')
flush.console()
tryCatch({
    start_time <- Sys.time()
    install.packages('https://cran.r-project.org/src/contrib/Archive/mcmcplots/mcmcplots_0.4.3.tar.gz', 
                     repos = NULL, type = 'source', dependencies = TRUE, quiet = TRUE)
    end_time <- Sys.time()
    duration <- round(as.numeric(difftime(end_time, start_time, units = 'secs')), 1)
    if (require('mcmcplots', character.only = TRUE, quietly = TRUE)) {
        cat('✅ Built mcmcplots in', duration, 'seconds\\n')
        cat('SUCCESS\\n')
    } else {
        cat('FAILED TO LOAD\\n')
        quit(status = 1)
    }
}, error = function(e) {
    cat('ERROR:', conditionMessage(e), '\\n')
    quit(status = 1)
})
"

if [[ "$DEBUG_MODE" == "true" ]]; then
    if echo "$mcmcplots_command" | R --slave --no-restore; then
        echo "✅"
        ((installed_count++))
    else
        echo "❌"
        failed_packages+=("mcmcplots")
    fi
else
    if echo "$mcmcplots_command" | R --slave --no-restore >/dev/null 2>&1; then
        echo "✅"
        ((installed_count++))
    else
        echo "❌"
        failed_packages+=("mcmcplots")
    fi
fi

# Install httpgd from GitHub using pak (skip if excluded)
if ! is_package_excluded "httpgd"; then
    echo -n "🌐 Installing httpgd from GitHub with pak... "
    httpgd_command="
    library(pak)
    cat('📦 Building httpgd...\\n')
    flush.console()
    tryCatch({
        start_time <- Sys.time()
        pak::pkg_install('nx10/httpgd')
        end_time <- Sys.time()
        duration <- round(as.numeric(difftime(end_time, start_time, units = 'secs')), 1)
        cat('✅ Built httpgd in', duration, 'seconds\\n')
        cat('SUCCESS\\n')
    }, error = function(e) {
        cat('ERROR:', conditionMessage(e), '\\n')
        quit(status = 1)
    })
    "

    if [[ "$DEBUG_MODE" == "true" ]]; then
        if echo "$httpgd_command" | R --slave --no-restore; then
            echo "✅"
            ((installed_count++))
        else
            echo "❌"
            failed_packages+=("httpgd")
        fi
    else
        if echo "$httpgd_command" | R --slave --no-restore >/dev/null 2>&1; then
            echo "✅"
            ((installed_count++))
        else
            echo "❌"
            failed_packages+=("httpgd")
        fi
    fi
else
    echo "⏭️  Skipping httpgd (excluded)"
fi

# Install colorout from GitHub using pak (skip if excluded)
if ! is_package_excluded "colorout"; then
    echo -n "🎨 Installing colorout from GitHub with pak... "
    colorout_command="
    library(pak)
    cat('📦 Building colorout...\\n')
    flush.console()
    tryCatch({
        start_time <- Sys.time()
        pak::pkg_install('jalvesaq/colorout')
        end_time <- Sys.time()
        duration <- round(as.numeric(difftime(end_time, start_time, units = 'secs')), 1)
        cat('✅ Built colorout in', duration, 'seconds\\n')
        cat('SUCCESS\\n')
    }, error = function(e) {
        cat('ERROR:', conditionMessage(e), '\\n')
        quit(status = 1)
    })
    "

    if [[ "$DEBUG_MODE" == "true" ]]; then
        if echo "$colorout_command" | R --slave --no-restore; then
            echo "✅"
            ((installed_count++))
        else
            echo "❌"
            failed_packages+=("colorout")
        fi
    else
        if echo "$colorout_command" | R --slave --no-restore >/dev/null 2>&1; then
            echo "✅"
            ((installed_count++))
        else
            echo "❌"
            failed_packages+=("colorout")
        fi
    fi
else
    echo "⏭️  Skipping colorout (excluded)"
fi

# Install btw from GitHub using pak (skip if excluded)
if ! is_package_excluded "btw"; then
    echo -n "📊 Installing btw from GitHub with pak... "
    btw_command="
    library(pak)
    cat('📦 Building btw...\\n')
    flush.console()
    tryCatch({
        start_time <- Sys.time()
        pak::pkg_install('posit-dev/btw')
        end_time <- Sys.time()
        duration <- round(as.numeric(difftime(end_time, start_time, units = 'secs')), 1)
        cat('✅ Built btw in', duration, 'seconds\\n')
        cat('SUCCESS\\n')
    }, error = function(e) {
        cat('ERROR:', conditionMessage(e), '\\n')
        quit(status = 1)
    })
    "

    if [[ "$DEBUG_MODE" == "true" ]]; then
        if echo "$btw_command" | R --slave --no-restore; then
            echo "✅"
            ((installed_count++))
        else
            echo "❌"
            failed_packages+=("btw")
        fi
    else
        if echo "$btw_command" | R --slave --no-restore >/dev/null 2>&1; then
            echo "✅"
            ((installed_count++))
        else
            echo "❌"
            failed_packages+=("btw")
        fi
    fi
else
    echo "⏭️  Skipping btw (excluded)"
fi

# Final summary
end_time=$(date +%s)
total_duration=$((end_time - start_time))
total_minutes=$((total_duration / 60))
total_seconds=$((total_duration % 60))
failed_count=${#failed_packages[@]}

echo
echo "=========================================="
echo "📊 R PACKAGE INSTALLATION SUMMARY (Phase 1)"
echo "=========================================="
echo "   ✅ Successfully installed: $installed_count packages"
echo "   ❌ Failed installations: $failed_count packages"
echo "   🕒 Total time: ${total_minutes}m ${total_seconds}s"
echo "   📅 End time: $(date)"
echo "   🔧 Method: pak with fallback to install.packages()"
echo

if [[ $failed_count -gt 0 ]]; then
    echo "❌ FAILED PACKAGES WITH ERROR DETAILS:"
    echo "======================================"
    for pkg_error in "${failed_packages[@]}"; do
        echo "   • $pkg_error"
    done
    echo
    echo "⚠️  Build completed with $failed_count failed package installations."
    echo "    Consider investigating these packages and their system dependencies."
    echo "    Check above for binary vs source installation attempts and specific error messages."
    exit 1
else
    echo "🎉 ALL PACKAGES INSTALLED SUCCESSFULLY!"
    echo "   No failed packages to report."
fi