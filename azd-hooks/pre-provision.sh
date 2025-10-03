#!/bin/bash

#==============================================================================
# AKS Pre-Provision Script
# 
# Purpose: Pre-provisioning setup for Azure Kubernetes Service (AKS) cluster
# This script ensures all prerequisites are met and creates SSH keys for AKS
#
# Usage: ./pre-provision.sh <AZURE_ENV_NAME> <AZURE_LOCATION>
# Example: ./pre-provision.sh dev eastus2
#==============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'        # Secure Internal Field Separator

#==============================================================================
# CONFIGURATION AND CONSTANTS
#==============================================================================

readonly SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# Default configuration values
readonly DEFAULT_RESOURCE_GROUP="contoso-aks-$1-$2-RG"
readonly DEFAULT_SSH_KEY_NAME="aks-SSKey"
readonly DEFAULT_SSH_KEY_SIZE=4096
readonly DEFAULT_SSH_KEY_TYPE="rsa"

#==============================================================================
# LOGGING FUNCTIONS
#==============================================================================

# Log info message
log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] ${*}" >&2
}

# Log error message
log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] ${*}" >&2
}

# Log warning message
log_warning() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARNING] ${*}" >&2
}

#==============================================================================
# UTILITY FUNCTIONS
#==============================================================================

# Display usage information
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} <AZURE_ENV_NAME> <AZURE_LOCATION>

Arguments:
    AZURE_ENV_NAME    Environment name for Azure deployment
    AZURE_LOCATION    Azure region for resource deployment

Examples:
    ${SCRIPT_NAME} dev eastus2
    ${SCRIPT_NAME} prod westus3

EOF
}

# Validate input parameters
validate_parameters() {
    if [[ $# -lt 2 ]]; then
        log_error "Insufficient arguments provided"
        usage
        exit 1
    fi

    if [[ -z "${1:-}" ]] || [[ -z "${2:-}" ]]; then
        log_error "Environment name and location cannot be empty"
        usage
        exit 1
    fi
}

# Check if required tools are installed
check_prerequisites() {
    local missing_tools=()
    
    command -v az >/dev/null 2>&1 || missing_tools+=("azure-cli")
    command -v ssh-keygen >/dev/null 2>&1 || missing_tools+=("ssh-keygen")
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install the missing tools and try again"
        exit 1
    fi
    
    log_info "All prerequisites satisfied"
}

# Check if user is logged into Azure
check_azure_login() {
    log_info "Checking Azure authentication status"
    
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged into Azure. Please run 'az login' first"
        exit 1
    fi
    
    local account_info
    account_info=$(az account show --query "{subscriptionId:id, subscriptionName:name}" -o json)
    log_info "Authenticated to Azure subscription: $(echo "${account_info}" | jq -r '.subscriptionName')"
}

#==============================================================================
# CORE FUNCTIONS
#==============================================================================

# Create Azure resource group (idempotent)
create_resource_group() {
    local resource_group="${1}"
    local location="${2}"
    local env_name="${3}"
    
    log_info "Creating/verifying resource group: ${resource_group}"
    
    if az group show --name "${resource_group}" >/dev/null 2>&1; then
        log_info "Resource group '${resource_group}' already exists"
    else
        log_info "Creating resource group '${resource_group}' in '${location}'"
        az group create \
            --name "${resource_group}" \
            --location "${location}" \
            --output none
        log_info "Resource group '${resource_group}' created successfully"
    fi
    echo "AZURE_RESOURCE_GROUP_NAME=\"${resource_group}\"" >> ./.azure/${env_name}/.env
}

# Create Azure SSH key (idempotent)
create_azure_ssh_key() {
    local ssh_key_name="${1}"
    local resource_group="${2}"
    local location="${3}"
    
    log_info "Creating/verifying Azure SSH key: ${ssh_key_name}"
    
    if az sshkey show --name "${ssh_key_name}" --resource-group "${resource_group}" >/dev/null 2>&1; then
        log_info "Azure SSH key '${ssh_key_name}' already exists"
    else
        log_info "Creating Azure SSH key '${ssh_key_name}'"
        az sshkey create \
            --name "${ssh_key_name}" \
            --resource-group "${resource_group}" \
            --location "${location}" \
            --output none
        log_info "Azure SSH key '${ssh_key_name}' created successfully"
    fi
}

# Create local SSH key pair (idempotent)
create_local_ssh_key() {
    local ssh_key_path="${HOME}/.ssh/id_rsa"
    
    log_info "Creating/verifying local SSH key pair"
    
    if [[ -f "${ssh_key_path}" ]]; then
        log_info "Local SSH key already exists at: ${ssh_key_path}"
    else
        log_info "Creating local SSH key pair at: ${ssh_key_path}"
        ssh-keygen \
            -t "${DEFAULT_SSH_KEY_TYPE}" \
            -b "${DEFAULT_SSH_KEY_SIZE}" \
            -f "${ssh_key_path}" \
            -N "" \
            -C "AKS-SSH-Key-${TIMESTAMP}"
        log_info "Local SSH key pair created successfully"
    fi
}

# Retrieve and export SSH public key
export_ssh_public_key() {
    local ssh_key_name="${1}"
    local resource_group="${2}"
    local env_name="${3}"
    
    log_info "Retrieving SSH public key from Azure"
    
    local ssh_public_key
    ssh_public_key=$(az sshkey show \
        --name "${ssh_key_name}" \
        --resource-group "${resource_group}" \
        --query 'publicKey' \
        --output tsv)
    
    if [[ -z "${ssh_public_key}" ]]; then
        log_error "Failed to retrieve SSH public key"
        exit 1
    fi
    
    # Export to environment
    export SSH_PUBLIC_KEY="${ssh_public_key}"
    log_info "SSH public key exported to environment variable"
    
    # Save to .env file
    local env_dir="./.azure/${env_name}"
    local env_file="${env_dir}/.env"
    
    # Ensure directory exists
    mkdir -p "${env_dir}"
    
    # Remove existing SSH_PUBLIC_KEY entry to avoid duplicates
    if [[ -f "${env_file}" ]]; then
        sed -i '/^SSH_PUBLIC_KEY=/d' "${env_file}" 2>/dev/null || true
    fi
    
    # Append new SSH_PUBLIC_KEY entry
    echo "SSH_PUBLIC_KEY=\"${ssh_public_key}\"" >> "${env_file}"
    log_info "SSH public key saved to: ${env_file}"
    
    # Display key info (first 50 chars for security)
    local key_preview="${ssh_public_key:0:50}..."
    log_info "SSH Public Key Preview: ${key_preview}"
}

#==============================================================================
# MAIN EXECUTION
#==============================================================================

main() {
    log_info "Starting AKS pre-provisioning script"
    log_info "Script: ${SCRIPT_NAME}"
    log_info "Timestamp: ${TIMESTAMP}"
    
    # Validate input parameters
    validate_parameters "${@}"
    
    # Extract and validate parameters
    local azure_env_name="${1}"
    local azure_location="${2}"
    
    log_info "Environment: ${azure_env_name}"
    log_info "Location: ${azure_location}"
    
    # Check prerequisites
    check_prerequisites
    check_azure_login
    
    # Execute main provisioning steps
    create_resource_group "${DEFAULT_RESOURCE_GROUP}" "${azure_location}" "$azure_env_name"
    create_azure_ssh_key "${DEFAULT_SSH_KEY_NAME}" "${DEFAULT_RESOURCE_GROUP}" "${azure_location}"
    create_local_ssh_key
    export_ssh_public_key "${DEFAULT_SSH_KEY_NAME}" "${DEFAULT_RESOURCE_GROUP}" "${azure_env_name}"
    
    log_info "AKS pre-provisioning completed successfully"
}

# Execute main function if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "${@}"
fi