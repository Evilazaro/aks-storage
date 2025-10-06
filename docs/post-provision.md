# AKS Post-Provisioning Script Documentation (`post-provision.sh`)

> **Purpose:** Post-provision setup for an **Azure Kubernetes Service (AKS)** cluster deployed via **Azure Developer CLI (AZD)**.  
> This script configures **Azure Workload Identity**, **Federated Identity Credentials**, and **Storage Account Secrets** for secure pod authentication.

---

## Table of Contents
1. [Overview](#overview)  
2. [Key Features](#key-features)  
3. [Prerequisites](#prerequisites)  
4. [Inputs & Parameters](#inputs--parameters)  
5. [Generated Artifacts](#generated-artifacts)  
6. [Script Flow](#script-flow)  
7. [Constants & Variables](#constants--variables)  
8. [Functions](#functions)  
9. [Inline YAML Manifests](#inline-yaml-manifests)  
10. [Usage](#usage)  
11. [Examples](#examples)  
12. [Troubleshooting](#troubleshooting)  
13. [Security Notes](#security-notes)  
14. [Contributing](#contributing)  
15. [License](#license)

---

## Overview
The script performs post-provisioning setup tasks required to fully enable Azure Workload Identity and access to Azure Storage within an AKS environment.

It:
- Configures `kubectl` for the target AKS cluster.
- Creates or updates a Kubernetes **ServiceAccount** annotated with a Managed Identity Client ID.
- Creates or verifies a **Federated Identity Credential (FIC)** on the specified Managed Identity.
- Creates a **Kubernetes Secret** containing Azure Storage Account credentials (from the AKS Node Resource Group).
- Persists relevant environment variables to the AZD environment `.env` file.

> ✅ The script is **idempotent** — safe to re-run without duplicating existing resources.

---

## Key Features
- **Adds Azure Storage Secret creation** for secure integration with persistent storage or blob mounting.
- **Enhanced validation** of input parameters (now expects 9 parameters).
- **Cross-platform `.env` updates** compatible with macOS and Linux.
- **Logs** with timestamps and log levels (`INFO`, `SUCCESS`, `WARNING`, `ERROR`).
- **Comprehensive verification** of Azure login, cluster connectivity, and existing resources.

---

## Prerequisites
- Azure CLI (`az`)
- `kubectl`
- `jq`
- Authenticated Azure session (`az login`)
- Existing AKS cluster with OIDC enabled
- Existing **User Assigned Managed Identity (UAMI)**
- Existing **Azure Storage Account** (in Node Resource Group)

---

## Inputs & Parameters
The script now expects **9 positional parameters**:

| # | Parameter | Description | Example |
|---|------------|-------------|----------|
| 1 | `AZURE_ENV_NAME` | Name of AZD environment for variable persistence | `dev` |
| 2 | `AZURE_LOCATION` | Azure region | `eastus2` |
| 3 | `RESOURCE_GROUP` | Resource group containing the AKS cluster | `rg-aks-dev` |
| 4 | `SUBSCRIPTION_ID` | Subscription ID | `12345678-1234-1234-1234-123456789012` |
| 5 | `AKS_CLUSTER_NAME` | Name of the AKS cluster | `my-aks-cluster` |
| 6 | `AKS_OIDC_ISSUER` | OIDC issuer URL for the AKS cluster | `https://eastus2.oic.prod-aks.azure.com/abcd1234/` |
| 7 | `IDENTITY_NAME` | Name of the Managed Identity | `my-uami` |
| 8 | `IDENTITY_ID` | Client ID (GUID) of the Managed Identity | `87654321-4321-4321-4321-210987654321` |
| 9 | `AZURE_STORAGE_ACCOUNT_NAME` | Name of the Azure Storage Account | `mystorageaccount` |

---

## Generated Artifacts
After execution, the following resources and files are created/updated:

- **Kubernetes ServiceAccount** with workload identity annotation  
- **Federated Identity Credential** linked to the UAMI  
- **Kubernetes Secret** with Azure Storage Account credentials  
- **AZD environment file** (`.azure/<env>/.env`) with:
  - `SERVICE_ACCOUNT_NAMESPACE`
  - `SERVICE_ACCOUNT_NAME`
  - `FEDERATED_IDENTITY_CREDENTIAL_NAME`

---

## Script Flow
1. **Parameter validation** (expects 9 arguments).  
2. **Azure login validation** using `az account show`.  
3. **Check prerequisites** (`az`, `kubectl`, `jq`).  
4. **Configure kubectl** with cluster credentials.  
5. **Create/verify ServiceAccount** with the correct client ID annotation.  
6. **Create/verify Federated Identity Credential (FIC)**.  
7. **Create Storage Secret** using Node Resource Group and Storage Account Key.  
8. **Persist results** to `.azure/<env>/.env`.  

---

## Constants & Variables
| Name | Default | Description |
|------|----------|-------------|
| `DEFAULT_SERVICE_ACCOUNT_NAMESPACE` | `default` | Default Kubernetes namespace |
| `WORKLOAD_IDENTITY_AUDIENCE` | `api://AzureADTokenExchange` | Audience for federated credential |
| `SERVICE_ACCOUNT_SUFFIX` | `-sa` | Suffix appended to the generated ServiceAccount name |
| `CREDENTIAL_SUFFIX` | `fed-cred` | Suffix appended to the Federated Identity Credential name |
| `IDENTITY_SUFFIX` | `identity` | Reserved for derived identity naming |
| `SCRIPT_DIR` | Path to current directory | Used for relative file operations |

---

## Functions

### Logging Functions
```bash
log_info "message"
log_warning "message"
log_error "message"
log_success "message"
```
Each prepends a timestamp and log level.

---

### `usage()`
Prints usage instructions, arguments, and an example.

---

### `validate_parameters()`
- Ensures 9 parameters are provided.
- Validates all are non-empty.
- Verifies the OIDC issuer begins with `https://`.

---

### `check_prerequisites()`
Checks for:
- `az`
- `kubectl`
- `jq`

Fails if any tool is missing.

---

### `check_azure_login()`
Ensures the user is authenticated to Azure and prints the active subscription name.

---

### `update_env_file()`
Idempotently updates or creates:
```
./.azure/<AZURE_ENV_NAME>/.env
```
Handles macOS/Linux differences in `sed`.

---

### `configure_kubectl()`
Retrieves AKS credentials and tests connectivity with a 30-second timeout:
```bash
az aks get-credentials --overwrite-existing
timeout 30 kubectl cluster-info
```

---

### `create_service_account()`
Creates or updates a ServiceAccount with an Azure Workload Identity annotation.

**Inline YAML:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: "<IDENTITY_ID>"
  name: "<SERVICE_ACCOUNT_NAME>"
  namespace: "default"
```

---

### `create_federated_credential()`
Creates a Federated Identity Credential if missing:
```bash
az identity federated-credential create   --name "<AKS_CLUSTER_NAME>-fed-cred"   --identity-name "<IDENTITY_NAME>"   --issuer "<AKS_OIDC_ISSUER>"   --subject "system:serviceaccount:default:<SERVICE_ACCOUNT_NAME>"   --audience "api://AzureADTokenExchange"
```

---

### `create_azure_storage_secret()`
Retrieves the **Node Resource Group** and **Storage Account Key**, then creates a K8s secret.

```bash
kubectl create secret generic azure-secret   --from-literal=azurestorageaccountname=<AZURE_STORAGE_ACCOUNT_NAME>   --from-literal=azurestorageaccountkey=<STORAGE_KEY>   --namespace=default
```

Displays the YAML output after creation for verification.

---

## Inline YAML Manifests
**Kubernetes ServiceAccount**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: "<IDENTITY_ID>"
  name: "aks-demo-cluster-wi-sa"
  namespace: "default"
```

---

## Usage
Make the script executable and run:

```bash
chmod +x post-provision.sh

./post-provision.sh   <AZURE_ENV_NAME>   <AZURE_LOCATION>   <RESOURCE_GROUP>   <SUBSCRIPTION_ID>   <AKS_CLUSTER_NAME>   <AKS_OIDC_ISSUER>   <IDENTITY_NAME>   <IDENTITY_ID>   <AZURE_STORAGE_ACCOUNT_NAME>
```

---

## Examples
```bash
./post-provision.sh dev eastus2 rg-aks-dev 12345678-1234-1234-1234-123456789012 my-aks-cluster https://eastus2.oic.prod-aks.azure.com/abcd1234/ my-uami 87654321-4321-4321-4321-210987654321 mystorageaccount
```

**Expected output (`.azure/dev/.env`):**
```
SERVICE_ACCOUNT_NAMESPACE="default"
SERVICE_ACCOUNT_NAME="aks-demo-cluster-wi-sa"
FEDERATED_IDENTITY_CREDENTIAL_NAME="my-aks-cluster-fed-cred"
```

---

## Troubleshooting

| Issue | Resolution |
|--------|-------------|
| `Not logged into Azure` | Run `az login` and set subscription with `az account set -s <id>` |
| `kubectl: cluster unreachable` | Check AKS network access or VPN |
| `Missing tools` | Install `azure-cli`, `kubectl`, `jq` |
| `Storage key access denied` | Ensure your principal has `Microsoft.Storage/storageAccounts/listKeys/action` permission |

---

## Security Notes
- The created Kubernetes secret contains **storage keys** — avoid committing it to source control.  
- Consider using **Azure Key Vault CSI Driver** for production workloads.  
- Use **namespace isolation** and **least privilege** for ServiceAccounts and Identities.  
- `.env` file should be excluded via `.gitignore`.

---

## Contributing
Contributions are welcome!  
Please follow conventional commit messages and format PRs with clear testing instructions.

---

## License
This project is licensed under the **MIT License**.  
See `LICENSE` for details.
