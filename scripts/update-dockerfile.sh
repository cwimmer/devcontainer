#!/bin/bash

# Script to update Dockerfile with the latest Terraform version
# This script fetches the latest Terraform version from HashiCorp's releases API
# and updates the TERRAFORM_VERSION argument in the Dockerfile

set -euo pipefail


# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERFILE_PATH="${SCRIPT_DIR}/../Dockerfile"

# Function to print colored output
print_info() {
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

# Function to get the latest Terraform version
get_latest_terraform_version() {
    local latest_version
    #print_info "Fetching the latest Terraform version from HashiCorp releases API..."
    
    # Get the latest release from GitHub API
    latest_version=$(curl -s "https://api.github.com/repos/hashicorp/terraform/releases/latest" | \
                     jq -r '.tag_name' | \
                     sed 's|^v||')
    
    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        print_error "Failed to fetch the latest Terraform version"
        exit 1
    fi
    
    # print_success "Latest Terraform version: $latest_version"
    echo "$latest_version"
}

# Function to get current Terraform version from Dockerfile
get_current_terraform_version() {
    local current_version
    current_version=$(grep "^ARG TERRAFORM_VERSION=" "$DOCKERFILE_PATH" | cut -d'=' -f2)
    
    if [[ -z "$current_version" ]]; then
        print_error "Could not find TERRAFORM_VERSION in Dockerfile"
        exit 1
    fi
    
    echo "$current_version"
}

# Function to update Terraform version in Dockerfile
update_dockerfile() {
    local new_version="$1"
    local current_version="$2"
    
    print_info "Updating Dockerfile with Terraform version $new_version..."
    
    # Create a backup
    cp "$DOCKERFILE_PATH" "${DOCKERFILE_PATH}.backup"
    print_info "Created backup: ${DOCKERFILE_PATH}.backup"
    
    # Update the Dockerfile
    sed -i "s|^ARG TERRAFORM_VERSION=.*|ARG TERRAFORM_VERSION=$new_version|" "$DOCKERFILE_PATH"
    
    # Verify the change
    local updated_version
    updated_version=$(get_current_terraform_version)
    
    if [[ "$updated_version" == "$new_version" ]]; then
        print_success "Successfully updated Terraform version from $current_version to $new_version"
        print_info "Backup created at: ${DOCKERFILE_PATH}.backup"
    else
        print_error "Failed to update Terraform version. Restoring backup..."
        mv "${DOCKERFILE_PATH}.backup" "$DOCKERFILE_PATH"
        exit 1
    fi
}

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Update Dockerfile with the latest Terraform version.

OPTIONS:
    -h, --help          Show this help message
    -c, --check-only    Only check for updates without making changes
    -v, --version VER   Use specific version instead of latest
    --no-backup        Don't create a backup of the original Dockerfile

EXAMPLES:
    $0                      # Update to latest version
    $0 --check-only         # Check what the latest version is
    $0 --version 1.6.0      # Update to specific version
    $0 --no-backup          # Update without creating backup

EOF
}

# Parse command line arguments
CHECK_ONLY=false
SPECIFIC_VERSION=""
NO_BACKUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--check-only)
            CHECK_ONLY=true
            shift
            ;;
        -v|--version)
            SPECIFIC_VERSION="$2"
            shift 2
            ;;
        --no-backup)
            NO_BACKUP=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
main() {
    print_info "Starting Terraform version update script..."
    
    # Check if Dockerfile exists
    if [[ ! -f "$DOCKERFILE_PATH" ]]; then
        print_error "Dockerfile not found at: $DOCKERFILE_PATH"
        exit 1
    fi
    
    # Check if required tools are available
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not installed"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_error "jq is required but not installed"
        exit 1
    fi
    
    # Get current version
    current_version=$(get_current_terraform_version)
    print_info "Current Terraform version in Dockerfile: $current_version"
    
    # Get target version (latest or specific)
    if [[ -n "$SPECIFIC_VERSION" ]]; then
        target_version="$SPECIFIC_VERSION"
        print_info "Using specified version: $target_version"
    else
        target_version=$(get_latest_terraform_version)
    fi
    
    # Check if update is needed
    if [[ "$current_version" == "$target_version" ]]; then
        print_success "Dockerfile is already using Terraform version $target_version"
        exit 0
    fi
    
    if [[ "$CHECK_ONLY" == true ]]; then
        print_info "Check-only mode: Terraform can be updated from $current_version to $target_version"
        exit 0
    fi
    
    # Perform update
    if [[ "$NO_BACKUP" == true ]]; then
        print_warning "Skipping backup creation as requested"
        sed -i "s|^ARG TERRAFORM_VERSION=.*|ARG TERRAFORM_VERSION=$target_version|" "$DOCKERFILE_PATH"
        print_success "Successfully updated Terraform version from $current_version to $target_version"
    else
        update_dockerfile "$target_version" "$current_version"
    fi
    
    print_success "Update completed! You may want to rebuild your Docker image."
}

# Run main function
main "$@"