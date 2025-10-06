#!/bin/bash

#==============================================================================
# AKS Post-Provision Script
# 
# Purpose: Post-provisioning setup for Azure Kubernetes Service (AKS) cluster
# This script configures workload identity by creating managed identities,
# service accounts, and federated identity credentials for secure pod authentication
#
# Usage: ./post-provision.sh <AZURE_ENV_NAME> <AZURE_LOCATION> <RESOURCE_GROUP> <SUBSCRIPTION_ID> <AKS_CLUSTER_NAME> <AKS_OIDC_ISSUER> <IDENTITY_NAME> <IDENTITY_ID> <AZURE_STORAGE_ACCOUNT_NAME>
# Example: ./post-provision.sh dev eastus2 rg-aks sub-123 my-aks-cluster https://oidc.issuer.url my-identity client-id storage-account
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
readonly DEFAULT_SERVICE_ACCOUNT_NAMESPACE="default"
readonly WORKLOAD_IDENTITY_AUDIENCE="api://AzureADTokenExchange"
readonly IDENTITY_SUFFIX="identity"
readonly SERVICE_ACCOUNT_SUFFIX="-sa"
readonly CREDENTIAL_SUFFIX="fed-cred"

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

# Log success message
log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] ${*}" >&2
}

#==============================================================================
# UTILITY FUNCTIONS
#==============================================================================

# Display usage information
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} <AZURE_ENV_NAME> <AZURE_LOCATION> <RESOURCE_GROUP> <SUBSCRIPTION_ID> <AKS_CLUSTER_NAME> <AKS_OIDC_ISSUER> <IDENTITY_NAME> <IDENTITY_ID> <AZURE_STORAGE_ACCOUNT_NAME>

Arguments:
    AZURE_ENV_NAME              Environment name for Azure deployment
    AZURE_LOCATION              Azure region for resource deployment
    RESOURCE_GROUP              Azure resource group name
    SUBSCRIPTION_ID             Azure subscription ID
    AKS_CLUSTER_NAME            Name of the AKS cluster
    AKS_OIDC_ISSUER             OIDC issuer URL from AKS cluster
    IDENTITY_NAME               Name of the managed identity
    IDENTITY_ID                 Client ID of the managed identity
    AZURE_STORAGE_ACCOUNT_NAME  Name of the Azure storage account

Examples:
    ${SCRIPT_NAME} dev eastus2 rg-aks-dev 12345678-1234-1234-1234-123456789012 my-aks-cluster https://eastus2.oic.prod-aks.azure.com/12345678-1234-1234-1234-123456789012/ my-identity 87654321-4321-4321-4321-210987654321 mystorageaccount

EOF
}

# Validate input parameters
validate_parameters() {
    if [[ $# -lt 9 ]]; then
        log_error "Insufficient arguments provided (expected 9, got $#)"
        usage
        exit 1
    fi

    local azure_env_name="${1:-}"
    local azure_location="${2:-}"
    local resource_group="${3:-}"
    local subscription_id="${4:-}"
    local aks_cluster_name="${5:-}"
    local aks_oidc_issuer="${6:-}"
    local identity_name="${7:-}"
    local identity_id="${8:-}"
    local azure_storage_account_name="${9:-}"

    # Check for empty parameters
    local empty_params=()
    [[ -z "${azure_env_name}" ]] && empty_params+=("AZURE_ENV_NAME")
    [[ -z "${azure_location}" ]] && empty_params+=("AZURE_LOCATION")
    [[ -z "${resource_group}" ]] && empty_params+=("RESOURCE_GROUP")
    [[ -z "${subscription_id}" ]] && empty_params+=("SUBSCRIPTION_ID")
    [[ -z "${aks_cluster_name}" ]] && empty_params+=("AKS_CLUSTER_NAME")
    [[ -z "${aks_oidc_issuer}" ]] && empty_params+=("AKS_OIDC_ISSUER")
    [[ -z "${identity_name}" ]] && empty_params+=("IDENTITY_NAME")
    [[ -z "${identity_id}" ]] && empty_params+=("IDENTITY_ID")
    [[ -z "${azure_storage_account_name}" ]] && empty_params+=("AZURE_STORAGE_ACCOUNT_NAME")

    if [[ ${#empty_params[@]} -gt 0 ]]; then
        log_error "The following parameters cannot be empty: ${empty_params[*]}"
        usage
        exit 1
    fi

    # Validate OIDC issuer URL format
    if [[ ! "${aks_oidc_issuer}" =~ ^https:// ]]; then
        log_error "AKS OIDC issuer must be a valid HTTPS URL"
        exit 1
    fi
}

# Check if required tools are installed
check_prerequisites() {
    local missing_tools=()
    
    command -v az >/dev/null 2>&1 || missing_tools+=("azure-cli")
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v jq >/dev/null 2>&1 || missing_tools+=("jq")
    
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
    local subscription_name
    subscription_name=$(echo "${account_info}" | jq -r '.subscriptionName // .subscriptionId')
    log_info "Authenticated to Azure subscription: ${subscription_name}"
}

# Update environment file with key-value pair (avoiding duplicates)
update_env_file() {
    local env_name="${1}"
    local key="${2}"
    local value="${3}"
    
    local env_dir="./.azure/${env_name}"
    local env_file="${env_dir}/.env"
    
    # Ensure directory exists
    mkdir -p "${env_dir}"
    
    # Remove existing entry to avoid duplicates
    if [[ -f "${env_file}" ]]; then
        # Use portable sed syntax for both Linux and macOS
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' "/^${key}=/d" "${env_file}" 2>/dev/null || true
        else
            sed -i "/^${key}=/d" "${env_file}" 2>/dev/null || true
        fi
    fi
    
    # Append new entry
    echo "${key}=\"${value}\"" >> "${env_file}"
    log_info "Updated environment file: ${key}=\"${value}\""
}

#==============================================================================
# CORE FUNCTIONS
#==============================================================================

# Configure kubectl with AKS credentials
configure_kubectl() {
    local resource_group="${1}"
    local cluster_name="${2}"
    
    log_info "Configuring kubectl with AKS credentials"
    log_info "Resource Group: ${resource_group}"
    log_info "Cluster: ${cluster_name}"
    
    if az aks get-credentials \
        --resource-group "${resource_group}" \
        --name "${cluster_name}" \
        --overwrite-existing \
        --output none; then
        log_success "Successfully configured kubectl for cluster: ${cluster_name}"
    else
        log_error "Failed to configure kubectl credentials"
        exit 1
    fi
    
    # Verify kubectl connectivity with timeout
    if timeout 30 kubectl cluster-info >/dev/null 2>&1; then
        log_success "Kubectl connectivity verified"
    else
        log_warning "kubectl configured but cluster connectivity could not be verified (may be due to network latency)"
    fi
}

# Create Kubernetes service account with workload identity annotation (idempotent)
create_service_account() {
    local service_account_name="${1}"
    local namespace="${2}"
    local client_id="${3}"
    local env_name="${4}"
    
    log_info "Creating/verifying Kubernetes service account: ${service_account_name}"
    log_info "Namespace: ${namespace}"
    
    # Check if service account already exists
    if kubectl get serviceaccount "${service_account_name}" -n "${namespace}" >/dev/null 2>&1; then
        log_info "Service account '${service_account_name}' already exists"
        
        # Update annotation if needed
        local current_client_id
        current_client_id=$(timeout 30 kubectl get serviceaccount "${service_account_name}" -n "${namespace}" \
            -o jsonpath='{.metadata.annotations.azure\.workload\.identity/client-id}' 2>/dev/null || echo "")
        
        if [[ "${current_client_id}" != "${client_id}" ]]; then
            log_info "Updating service account annotation with new client ID"
            timeout 30 kubectl annotate serviceaccount "${service_account_name}" -n "${namespace}" \
                "azure.workload.identity/client-id=${client_id}" --overwrite
            log_success "Service account annotation updated"
        else
            log_info "Service account annotation is up to date"
        fi
    else
        log_info "Creating service account '${service_account_name}'"
        
        # Create service account with workload identity annotation
        if cat <<EOF | timeout 60 kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: "${client_id}"
  name: "${service_account_name}"
  namespace: "${namespace}"
EOF
        then
            log_success "Service account '${service_account_name}' created successfully"
        else
            log_error "Failed to create service account"
            exit 1
        fi
    fi
    
    # Export to environment and update .env file
    export SERVICE_ACCOUNT_NAMESPACE="${namespace}"
    export SERVICE_ACCOUNT_NAME="${service_account_name}"
    
    update_env_file "${env_name}" "SERVICE_ACCOUNT_NAMESPACE" "${namespace}"
    update_env_file "${env_name}" "SERVICE_ACCOUNT_NAME" "${service_account_name}"
}

# Create federated identity credential (idempotent)
create_federated_credential() {
    local credential_name="${1}"
    local identity_name="${2}"
    local resource_group="${3}"
    local subscription_id="${4}"
    local oidc_issuer="${5}"
    local namespace="${6}"
    local service_account_name="${7}"
    local env_name="${8}"
    
    log_info "Creating/verifying federated identity credential: ${credential_name}"
    
    local subject="system:serviceaccount:${namespace}:${service_account_name}"
    
    # Check if federated credential already exists
    if az identity federated-credential show \
        --name "${credential_name}" \
        --identity-name "${identity_name}" \
        --resource-group "${resource_group}" \
        --subscription "${subscription_id}" >/dev/null 2>&1; then
        log_info "Federated identity credential '${credential_name}' already exists"
    else
        log_info "Creating federated identity credential '${credential_name}'"
        log_info "Subject: ${subject}"
        log_info "Issuer: ${oidc_issuer}"
        
        if az identity federated-credential create \
            --name "${credential_name}" \
            --identity-name "${identity_name}" \
            --resource-group "${resource_group}" \
            --subscription "${subscription_id}" \
            --issuer "${oidc_issuer}" \
            --subject "${subject}" \
            --audience "${WORKLOAD_IDENTITY_AUDIENCE}" \
            --output none; then
            log_success "Federated identity credential '${credential_name}' created successfully"
        else
            log_error "Failed to create federated identity credential"
            exit 1
        fi
    fi
    
    # Export to environment and update .env file
    export FEDERATED_IDENTITY_CREDENTIAL_NAME="${credential_name}"
    update_env_file "${env_name}" "FEDERATED_IDENTITY_CREDENTIAL_NAME" "${credential_name}"
}

create_azure_storage_secret() {
  local resource_group="$1"
  local cluster_name="$2"
  local storage_account="$3"
  local secret_name="$4"
  local namespace="$5"
  
  echo "Getting node resource group for cluster: $cluster_name"
  local node_rg=$(az aks show --resource-group "$resource_group" --name "$cluster_name" --query nodeResourceGroup -o tsv)
  echo "Node Resource Group Name is: $node_rg"
  
  echo "Getting storage account key for: $storage_account"
  local storage_key=$(az storage account keys list --resource-group "$node_rg" --account-name "$storage_account" --query "[0].value" -o tsv)
  echo "Storage key retrieved successfully"
  
  echo "Creating Kubernetes secret: $secret_name"
  kubectl create secret generic "$secret_name" \
    --from-literal=azurestorageaccountname="$storage_account" \
    --from-literal=azurestorageaccountkey="$storage_key" \
    --namespace="$namespace"
  
  echo "Displaying secret YAML:"
  kubectl get secret "$secret_name" -n "$namespace" -o yaml
  echo "Kubernetes secret '$secret_name' created successfully in namespace '$namespace'"
}


#==============================================================================
# MAIN EXECUTION
#==============================================================================

main() {
    log_info "Starting AKS post-provisioning script"
    log_info "Script: ${SCRIPT_NAME}"
    log_info "Timestamp: ${TIMESTAMP}"
    
    # Validate input parameters
    validate_parameters "${@}"
    
    # Extract parameters
    local azure_env_name="${1}"
    local azure_location="${2}"
    local resource_group="${3}"
    local subscription_id="${4}"
    local aks_cluster_name="${5}"
    local aks_oidc_issuer="${6}"
    local identity_name="${7}"
    local identity_id="${8}"
    local azure_storage_account_name="${9}"
    
    # Generate resource names
    local service_account_name="aks-demo-cluster-wi${SERVICE_ACCOUNT_SUFFIX}"
    local credential_name="${aks_cluster_name}-${CREDENTIAL_SUFFIX}"
    
    log_info "Configuration:"
    log_info "  Environment: ${azure_env_name}"
    log_info "  Location: ${azure_location}"
    log_info "  Resource Group: ${resource_group}"
    log_info "  Subscription: ${subscription_id:0:8}..." 2>/dev/null || log_info "  Subscription: [redacted]"
    log_info "  AKS Cluster: ${aks_cluster_name}"
    log_info "  Identity Name: ${identity_name}"
    log_info "  Service Account: ${service_account_name}"
    log_info "  Credential Name: ${credential_name}"
    
    # Check prerequisites
    check_prerequisites
    check_azure_login
    
    # Execute main provisioning steps
    configure_kubectl "${resource_group}" "${aks_cluster_name}"
    create_service_account "${service_account_name}" "${DEFAULT_SERVICE_ACCOUNT_NAMESPACE}" "${identity_id}" "${azure_env_name}"
    create_federated_credential "${credential_name}" "${identity_name}" "${resource_group}" "${subscription_id}" "${aks_oidc_issuer}" "${DEFAULT_SERVICE_ACCOUNT_NAMESPACE}" "${service_account_name}" "${azure_env_name}"
    create_azure_storage_secret "${resource_group}" "${aks_cluster_name}" "${azure_storage_account_name}" "azure-secret" "${DEFAULT_SERVICE_ACCOUNT_NAMESPACE}"

    log_success "AKS post-provisioning completed successfully"
    log_success "Workload identity is now configured for pods using service account: ${service_account_name}"
    log_info "To use workload identity in your pods, add the following to your pod spec:"
    log_info "  spec:"
    log_info "    serviceAccountName: ${service_account_name}"
    log_info "    containers:"
    log_info "    - name: your-container"
    log_info "      image: your-image"
    log_info "      env:"
    log_info "      - name: AZURE_CLIENT_ID"
    log_info "        value: \"${identity_id}\""
}

# Execute main function if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "${@}"
fi
