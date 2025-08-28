#!/bin/bash
# parse-docker-error.sh - Make Docker build errors human-readable
#
# Usage: 
#   ./build.sh full 2>&1 | ./parse-docker-error.sh
#   or
#   ./parse-docker-error.sh < error.log

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Docker Build Error Parser${NC}"
echo "=================================="

# Read all input
input=$(cat)

# Check if this is a Docker build error
if echo "$input" | grep -q "ERROR: failed to build"; then
    echo -e "${RED}❌ DOCKER BUILD FAILED${NC}"
    echo
    
    # Extract the failed step
    failed_step=$(echo "$input" | grep -o ">>> .*" | head -1 | sed 's/>>> //')
    if [[ -n "$failed_step" ]]; then
        echo -e "${YELLOW}📍 Failed Step:${NC}"
        echo "   $failed_step"
        echo
    fi
    
    # Extract Dockerfile line number
    dockerfile_line=$(echo "$input" | grep -o "Dockerfile:[0-9]*" | head -1)
    if [[ -n "$dockerfile_line" ]]; then
        echo -e "${YELLOW}📄 Location:${NC}"
        echo "   $dockerfile_line"
        echo
    fi
    
    # Extract the actual command that failed
    echo -e "${YELLOW}💥 Failed Command:${NC}"
    failed_command=$(echo "$input" | grep -o 'process "/bin/sh -c [^"]*"' | sed 's/process "\/bin\/sh -c //' | sed 's/"$//')
    
    if [[ -n "$failed_command" ]]; then
        # Clean up the command for readability
        echo "$failed_command" | sed 's/; */;\n   /g' | sed 's/\\\\/\n   \\\\/g' | while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*echo ]]; then
                echo -e "   ${GREEN}$line${NC}"
            elif [[ "$line" =~ (apt-get|install|curl|wget) ]]; then
                echo -e "   ${BLUE}$line${NC}"
            elif [[ "$line" =~ (rm|find.*-delete) ]]; then
                echo -e "   ${YELLOW}$line${NC}"
            else
                echo "   $line"
            fi
        done
    else
        echo "   (Could not extract command details)"
    fi
    
    echo
    
    # Extract exit code
    exit_code=$(echo "$input" | grep -o "exit code: [0-9]*" | head -1)
    if [[ -n "$exit_code" ]]; then
        echo -e "${RED}🚨 Exit Code:${NC}"
        echo "   $exit_code"
        echo
    fi
    
    # Look for specific error patterns
    echo -e "${YELLOW}🔍 Error Analysis:${NC}"
    
    if echo "$input" | grep -q "pak installation failed"; then
        echo "   • R package installation issue (pak failed)"
        echo "   • Check R package dependencies and binary availability"
    elif echo "$input" | grep -q "Segmentation fault"; then
        echo "   • Segmentation fault detected"
        echo "   • Likely QEMU emulation issue on Apple Silicon"
    elif echo "$input" | grep -q "No space left on device"; then
        echo "   • Disk space issue"
        echo "   • Try: docker system prune -a"
    elif echo "$input" | grep -q "network\|timeout\|connection"; then
        echo "   • Network connectivity issue"
        echo "   • Check internet connection and retry"
    elif echo "$input" | grep -q "permission denied\|Permission denied"; then
        echo "   • Permission issue"
        echo "   • Check file permissions and Docker daemon access"
    else
        echo "   • Generic build failure"
        echo "   • Check the failed command above for specific error details"
    fi
    
else
    # Not a Docker error, just pass through
    echo "$input"
fi
