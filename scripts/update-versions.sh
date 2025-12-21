#!/bin/bash

# Script to update tool versions in the Dockerfile
# Supports updating Terraform, Go, kubectl, tflint, trivy, terraform-docs, doctl, and asdf

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

# Supported tools and their ARG names in Dockerfile
declare -A TOOL_ARG_NAMES=(
    ["terraform"]="TERRAFORM_VERSION"
    ["golang"]="GOLANG_VERSION"
    ["kubectl"]="KUBECTL_VERSION"
    ["tflint"]="TFLINT_VERSION"
    ["trivy"]="TRIVY_VERSION"
    ["terraform-docs"]="TERRAFORM_DOCS_VERSION"
    ["doctl"]="DOCTL_VERSION"
    ["asdf"]="ASDF_VERSION"
)

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
    latest_version=$(curl -s "https://api.github.com/repos/hashicorp/terraform/releases/latest" | \
                     jq -r '.tag_name' | \
                     sed 's|^v||')
    
    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        print_error "Failed to fetch the latest Terraform version"
        return 1
    fi
    
    echo "$latest_version"
}

# Function to get the latest Go version
get_latest_golang_version() {
    local latest_version
    latest_version=$(curl -s "https://go.dev/VERSION?m=text" | head -n1 | sed 's|^go||')
    
    if [[ -z "$latest_version" ]]; then
        print_error "Failed to fetch the latest Go version"
        return 1
    fi
    
    echo "$latest_version"
}

# Function to get the latest kubectl version
get_latest_kubectl_version() {
    local latest_version
    latest_version=$(curl -L -s "https://dl.k8s.io/release/stable.txt" | sed 's|^v||')
    
    if [[ -z "$latest_version" ]]; then
        print_error "Failed to fetch the latest kubectl version"
        return 1
    fi
    
    echo "$latest_version"
}

# Function to get the latest tflint version
get_latest_tflint_version() {
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/terraform-linters/tflint/releases/latest" | \
                     jq -r '.tag_name' | \
                     sed 's|^v||')
    
    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        print_error "Failed to fetch the latest tflint version"
        return 1
    fi
    
    echo "$latest_version"
}

# Function to get the latest trivy version
get_latest_trivy_version() {
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/aquasecurity/trivy/releases/latest" | \
                     jq -r '.tag_name' | \
                     sed 's|^v||')
    
    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        print_error "Failed to fetch the latest trivy version"
        return 1
    fi
    
    echo "$latest_version"
}

# Function to get the latest terraform-docs version
get_latest_terraform-docs_version() {
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/terraform-docs/terraform-docs/releases/latest" | \
                     jq -r '.tag_name' | \
                     sed 's|^v||')
    
    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        print_error "Failed to fetch the latest terraform-docs version"
        return 1
    fi
    
    echo "$latest_version"
}

# Function to get the latest doctl version
get_latest_doctl_version() {
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/digitalocean/doctl/releases/latest" | \
                     jq -r '.tag_name' | \
                     sed 's|^v||')
    
    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        print_error "Failed to fetch the latest doctl version"
        return 1
    fi
    
    echo "$latest_version"
}

# Function to get the latest asdf version
get_latest_asdf_version() {
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/asdf-vm/asdf/releases/latest" | \
                     jq -r '.tag_name')
    
    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        print_error "Failed to fetch the latest asdf version"
        return 1
    fi
    
    echo "$latest_version"
}

# Function to get the latest version for a tool
get_latest_version() {
    local tool="$1"
    
    case "$tool" in
        terraform)
            get_latest_terraform_version
            ;;
        golang)
            get_latest_golang_version
            ;;
        kubectl)
            get_latest_kubectl_version
            ;;
        tflint)
            get_latest_tflint_version
            ;;
        trivy)
            get_latest_trivy_version
            ;;
        terraform-docs)
            get_latest_terraform-docs_version
            ;;
        doctl)
            get_latest_doctl_version
            ;;
        asdf)
            get_latest_asdf_version
            ;;
        *)
            print_error "Unknown tool: $tool"
            return 1
            ;;
    esac
}

# Function to get current version from Dockerfile
get_current_version() {
    local tool="$1"
    local arg_name="${TOOL_ARG_NAMES[$tool]}"
    local current_version
    
    current_version=$(grep "^ARG ${arg_name}=" "$DOCKERFILE_PATH" | cut -d'=' -f2)
    
    if [[ -z "$current_version" ]]; then
        print_error "Could not find ${arg_name} in Dockerfile"
        return 1
    fi
    
    echo "$current_version"
}

# Function to update version in Dockerfile
update_version() {
    local tool="$1"
    local new_version="$2"
    local current_version="$3"
    local no_backup="$4"
    local arg_name="${TOOL_ARG_NAMES[$tool]}"
    
    print_info "Updating $tool version in Dockerfile from $current_version to $new_version..."
    
    # Create a backup unless disabled
    if [[ "$no_backup" != "true" ]]; then
        cp "$DOCKERFILE_PATH" "${DOCKERFILE_PATH}.backup"
        print_info "Created backup: ${DOCKERFILE_PATH}.backup"
    fi
    
    # Update the Dockerfile
    sed -i "s|^ARG ${arg_name}=.*|ARG ${arg_name}=$new_version|" "$DOCKERFILE_PATH"
    
    # Verify the change
    local updated_version
    updated_version=$(get_current_version "$tool")
    
    if [[ "$updated_version" == "$new_version" ]]; then
        print_success "Successfully updated $tool version from $current_version to $new_version"
        if [[ "$no_backup" != "true" ]]; then
            print_info "Backup created at: ${DOCKERFILE_PATH}.backup"
        fi
    else
        print_error "Failed to update $tool version. Restoring backup..."
        if [[ "$no_backup" != "true" ]]; then
            mv "${DOCKERFILE_PATH}.backup" "$DOCKERFILE_PATH"
        fi
        return 1
    fi
}

# Function to process a single tool
process_tool() {
    local tool="$1"
    local check_only="$2"
    local specific_version="$3"
    local no_backup="$4"
    
    print_info "Processing $tool..."
    
    # Get current version
    local current_version
    current_version=$(get_current_version "$tool") || return 1
    print_info "Current $tool version in Dockerfile: $current_version"
    
    # Get target version (latest or specific)
    local target_version
    if [[ -n "$specific_version" ]]; then
        target_version="$specific_version"
        print_info "Using specified version: $target_version"
    else
        target_version=$(get_latest_version "$tool") || return 1
        print_info "Latest $tool version: $target_version"
    fi
    
    # Check if update is needed
    if [[ "$current_version" == "$target_version" ]]; then
        print_success "$tool is already using version $target_version"
        return 0
    fi
    
    if [[ "$check_only" == "true" ]]; then
        print_info "Check-only mode: $tool can be updated from $current_version to $target_version"
        return 0
    fi
    
    # Perform update
    if [[ "$no_backup" == "true" ]]; then
        print_warning "Skipping backup creation as requested"
    fi
    
    update_version "$tool" "$target_version" "$current_version" "$no_backup" || return 1
}

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Update tool versions in the Dockerfile.

OPTIONS:
    -h, --help              Show this help message
    -t, --tool TOOL         Update specific tool
    -a, --all               Update all supported tools
    -c, --check-only        Only check for updates without making changes
    -v, --version VER       Use specific version instead of latest
    --no-backup            Don't create a backup of the original Dockerfile

EXAMPLES:
    $0 --tool terraform                 # Update Terraform to latest
    $0 --tool golang --version 1.21.5   # Update Go to specific version
    $0 --all                            # Update all tools to latest
    $0 --all --check-only               # Check for updates without applying
    $0 --tool kubectl --no-backup       # Update without creating backup

SUPPORTED TOOLS:
    terraform       - HashiCorp Terraform
    golang          - Go programming language
    kubectl         - Kubernetes CLI
    tflint          - Terraform linter
    trivy           - Container vulnerability scanner
    terraform-docs  - Terraform documentation generator
    doctl           - DigitalOcean CLI
    asdf            - Version manager

EOF
}

# Parse command line arguments
CHECK_ONLY=false
SPECIFIC_VERSION=""
NO_BACKUP=false
UPDATE_ALL=false
TOOL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -t|--tool)
            TOOL="$2"
            shift 2
            ;;
        -a|--all)
            UPDATE_ALL=true
            shift
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
    print_info "Starting version update script..."
    
    # Validate arguments
    if [[ -z "$TOOL" && "$UPDATE_ALL" != "true" ]]; then
        print_error "Either --tool or --all must be specified"
        show_help
        exit 1
    fi
    
    if [[ -n "$TOOL" && "$UPDATE_ALL" == "true" ]]; then
        print_error "Cannot specify both --tool and --all"
        show_help
        exit 1
    fi
    
    if [[ -n "$SPECIFIC_VERSION" && "$UPDATE_ALL" == "true" ]]; then
        print_error "Cannot specify --version with --all (specific version only works with single tool)"
        show_help
        exit 1
    fi
    
    # Validate tool name
    if [[ -n "$TOOL" && ! -v "TOOL_ARG_NAMES[$TOOL]" ]]; then
        print_error "Unknown tool: $TOOL"
        print_error "Supported tools: ${!TOOL_ARG_NAMES[*]}"
        exit 1
    fi
    
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
    
    # Process tools
    local failed_tools=()
    
    if [[ "$UPDATE_ALL" == "true" ]]; then
        for tool in "${!TOOL_ARG_NAMES[@]}"; do
            echo ""
            if ! process_tool "$tool" "$CHECK_ONLY" "" "$NO_BACKUP"; then
                failed_tools+=("$tool")
            fi
        done
    else
        if ! process_tool "$TOOL" "$CHECK_ONLY" "$SPECIFIC_VERSION" "$NO_BACKUP"; then
            failed_tools+=("$TOOL")
        fi
    fi
    
    # Summary
    echo ""
    if [[ ${#failed_tools[@]} -eq 0 ]]; then
        print_success "All updates completed successfully!"
        if [[ "$CHECK_ONLY" != "true" ]]; then
            print_info "You may want to rebuild your Docker image."
        fi
    else
        print_error "Failed to update the following tools: ${failed_tools[*]}"
        exit 1
    fi
}

# Run main function
main "$@"
