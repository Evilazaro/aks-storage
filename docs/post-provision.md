# AKS Post‑Provisioning Script Documentation (`post-provision.sh`)

> **Purpose:** Post‑provision setup for an **Azure Kubernetes Service (AKS)** cluster deployed via **Azure Developer CLI (AZD)**.  
> This script configures **Azure Workload Identity** by creating (idempotently) a Kubernetes ServiceAccount annotated with a managed identity’s client ID and a federated identity credential on the Azure side, then persists useful environment variables to an AZD environment folder for reuse.

---

## Table of Contents

1. [Overview](#overview)  
2. [Key Features](#key-features)  
3. [Prerequisites](#prerequisites)  
4. [Inputs & Parameters](#inputs--parameters)  
5. [Generated Artifacts](#generated-artifacts)  
6. [What the Script Does (Flow)](#what-the-script-does-flow)  
7. [Constants & Variables](#constants--variables)  
8. [Functions](#functions)  
9. [Inline YAML Manifest](#inline-yaml-manifest)  
10. [Usage](#usage)  
11. [Examples](#examples)  
12. [Troubleshooting](#troubleshooting)  
13. [Security & Operational Notes](#security--operational-notes)  
14. [Contributing](#contributing)  
15. [License](#license)

---

## Overview

This script is intended to be run **after** an AKS cluster is provisioned. It performs the post‑provision steps needed to enable **Azure Workload Identity** for workloads:

- Ensures `kubectl` is configured for the newly created cluster.
- Creates or updates a **Kubernetes ServiceAccount** with the `azure.workload.identity/client-id` annotation.
- Creates (if missing) a **Federated Identity Credential** (FIC) on the specified **User‑Assigned Managed Identity** (UAMI), linking the AKS OIDC issuer and the ServiceAccount subject.
- Saves important outputs (ServiceAccount namespace/name, federated credential name) into the AZD environment file: `./.azure/<AZURE_ENV_NAME>/.env`.

> ✅ The script is **idempotent**: rerunning it won’t duplicate ServiceAccount or federated credentials and will keep annotations up to date.

---

## Key Features

- **Robust error handling:** `set -euo pipefail` and safe `IFS` defaults.  
- **Cross‑platform `sed` handling:** macOS & Linux compatible when updating `.env`.  
- **Idempotency:** Checks for existing K8s ServiceAccount and FIC before creating.  
- **Credential verification:** Configures `kubectl` and validates cluster reachability.  
- **Environment persistence:** Writes outputs to `./.azure/<env>/.env` for later use by AZD or scripts.

---

## Prerequisites

- **Azure CLI** (`az`)
- **kubectl**
- **jq**
- **Authenticated Azure session:** `az login` (and `az account set -s <SUBSCRIPTION_ID>` if needed)
- **An AKS cluster already provisioned**, with **OIDC issuer** enabled and available.
- **A User‑Assigned Managed Identity (UAMI)** already created (you’ll pass its *name* and *client ID*).

> Tip: Make sure your user or pipeline principal has rights to read/write on the UAMI and to read the AKS cluster.

---

## Inputs & Parameters

The script expects **8 positional arguments**:

```text
<AZURE_ENV_NAME> <AZURE_LOCATION> <RESOURCE_GROUP> <SUBSCRIPTION_ID> <AKS_CLUSTER_NAME> <AKS_OIDC_ISSUER> <IDENTITY_NAME> <IDENTITY_ID>
```

| # | Name | Description | Example |
|---|------|-------------|---------|
| 1 | `AZURE_ENV_NAME` | AZD environment name (used to persist outputs) | `dev` |
| 2 | `AZURE_LOCATION` | Azure region for resources | `eastus2` |
| 3 | `RESOURCE_GROUP` | Resource group with the AKS cluster and identity | `rg-aks-dev` |
| 4 | `SUBSCRIPTION_ID` | Azure subscription GUID | `12345678-1234-1234-1234-123456789012` |
| 5 | `AKS_CLUSTER_NAME` | Name of the AKS cluster | `my-aks-cluster` |
| 6 | `AKS_OIDC_ISSUER` | **HTTPS** OIDC issuer URL of the AKS cluster | `https://eastus2.oic.prod-aks.azure.com/<guid>/` |
| 7 | `IDENTITY_NAME` | **UAMI resource name** | `my-identity` |
| 8 | `IDENTITY_ID` | **UAMI client ID** (GUID) | `87654321-4321-4321-4321-210987654321` |

**Validation performed:**  
- All 8 parameters are required and non‑empty.  
- `AKS_OIDC_ISSUER` must be a valid `https://` URL.

---

## Generated Artifacts

- **Kubernetes ServiceAccount** in the `default` namespace (name is derived; see [Constants & Variables](#constants--variables)).
- **Federated Identity Credential** on the specified UAMI (name derived from the AKS cluster name).  
- **Environment file updates**: `./.azure/<AZURE_ENV_NAME>/.env` receives/updates:
  - `SERVICE_ACCOUNT_NAMESPACE="default"`
  - `SERVICE_ACCOUNT_NAME="<derived-name>"`
  - `FEDERATED_IDENTITY_CREDENTIAL_NAME="<derived-name>"`

> Existing keys in `.env` are safely de‑duplicated before writing the new values.

---

## What the Script Does (Flow)

1. **Parameter validation** and **Azure auth check** (`az account show`).  
2. **Prerequisite check** for `az`, `kubectl`, `jq`.  
3. **Configure `kubectl`** for the cluster via `az aks get-credentials` and verify connectivity.  
4. **Create/Update ServiceAccount** with the annotation `azure.workload.identity/client-id: "<IDENTITY_ID>"`.  
5. **Create Federated Identity Credential** on the UAMI (if absent) using:
   - **Issuer:** `AKS_OIDC_ISSUER`  
   - **Subject:** `system:serviceaccount:<namespace>:<serviceAccountName>`  
   - **Audience:** `api://AzureADTokenExchange`  
6. **Persist outputs** to the AZD `.env` file for the environment.

---

## Constants & Variables

| Name | Default / Example | Purpose |
|------|--------------------|---------|
| `DEFAULT_SERVICE_ACCOUNT_NAMESPACE` | `default` | Namespace to place the ServiceAccount |
| `WORKLOAD_IDENTITY_AUDIENCE` | `api://AzureADTokenExchange` | Audience used when creating the FIC |
| `SERVICE_ACCOUNT_SUFFIX` | `-sa` | Suffix appended to the generated ServiceAccount name |
| `CREDENTIAL_SUFFIX` | `fed-cred` | Suffix appended to the Federated Identity Credential name |
| Derived `service_account_name` | `aks-demo-cluster-wi-sa` | Default name used by the script |
| Derived `credential_name` | `<AKS_CLUSTER_NAME>-fed-cred` | FIC name derived from cluster name |

> The script also computes `SCRIPT_NAME`, `SCRIPT_DIR`, `TIMESTAMP` for logging, and uses `./.azure/<AZURE_ENV_NAME>/.env` to persist outputs.

---

## Functions

### Logging
```bash
log_info "message"
log_warning "message"
log_error "message"
log_success "message"
```

### `usage()`
Prints help, parameter details, and examples.

### `validate_parameters()`
- Ensures exactly 8 non‑empty parameters.  
- Validates OIDC issuer URL scheme is HTTPS.

### `check_prerequisites()`
Verifies `az`, `kubectl`, `jq` are installed.

### `check_azure_login()`
Confirms Azure CLI is authenticated and logs the active subscription name/ID.

### `update_env_file(env_name, key, value)`
- Ensures `./.azure/<env_name>/.env` exists.
- Removes any existing `key=` entries (macOS/Linux compatible) and appends `key="value"`.

### `configure_kubectl(resource_group, cluster_name)`
- Runs `az aks get-credentials ... --overwrite-existing`.
- Verifies cluster reachability via `kubectl cluster-info` (with timeout).

### `create_service_account(service_account_name, namespace, client_id, env_name)`
- Checks if the SA exists; creates if absent or updates the annotation if the client-id differs.  
- Exports `SERVICE_ACCOUNT_NAMESPACE` and `SERVICE_ACCOUNT_NAME`; persists both to `.env`.

### `create_federated_credential(credential_name, identity_name, resource_group, subscription_id, oidc_issuer, namespace, service_account_name, env_name)`
- Checks for an existing FIC; creates it if missing using the AKS OIDC issuer, SA subject, and audience.  
- Exports and persists `FEDERATED_IDENTITY_CREDENTIAL_NAME` to `.env`.

---

## Inline YAML Manifest

The ServiceAccount is applied via an **inline YAML** here‑document (no external file is required):

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: "<IDENTITY_ID>"
  name: "<SERVICE_ACCOUNT_NAME>"
  namespace: "<NAMESPACE>"
```

> If the ServiceAccount already exists, the script updates the annotation (when needed) instead of recreating the object.

---

## Usage

Make the script executable and run it with 8 arguments:

```bash
chmod +x post-provision.sh

./post-provision.sh \
  <AZURE_ENV_NAME> \
  <AZURE_LOCATION> \
  <RESOURCE_GROUP> \
  <SUBSCRIPTION_ID> \
  <AKS_CLUSTER_NAME> \
  <AKS_OIDC_ISSUER> \
  <IDENTITY_NAME> \
  <IDENTITY_ID>
```

> **Pods usage hint:** Add the following to your Pod spec to use Workload Identity:
>
> ```yaml
> spec:
>   serviceAccountName: <SERVICE_ACCOUNT_NAME>
>   containers:
>     - name: your-container
>       image: your-image
>       env:
>         - name: AZURE_CLIENT_ID
>           value: "<IDENTITY_ID>"
> ```

---

## Examples

```bash
./post-provision.sh dev eastus2 rg-aks-dev 12345678-1234-1234-1234-123456789012 \
  my-aks-cluster https://eastus2.oic.prod-aks.azure.com/1234.../ \
  my-identity 87654321-4321-4321-4321-210987654321
```

After a successful run, expect outputs written to:
```
./.azure/dev/.env
  SERVICE_ACCOUNT_NAMESPACE="default"
  SERVICE_ACCOUNT_NAME="aks-demo-cluster-wi-sa"
  FEDERATED_IDENTITY_CREDENTIAL_NAME="my-aks-cluster-fed-cred"
```

---

## Troubleshooting

- **“Not logged into Azure”** → run `az login` and, if needed, `az account set -s <SUBSCRIPTION_ID>`  
- **kubectl cannot reach cluster** → ensure network access to the cluster, and re‑run the script to refresh credentials.  
- **Missing tools** → install `azure-cli`, `kubectl`, `jq` before running.  
- **OIDC issuer invalid** → confirm OIDC issuer is enabled on the AKS cluster and use the exact HTTPS URL shown by `az aks show --query oidcIssuerProfile.issuerUrl -o tsv`.

---

## Security & Operational Notes

- The ServiceAccount is created in the `default` namespace by default. Consider using a **least‑privilege, app‑specific namespace** in production.  
- The script **does not grant Azure RBAC** to the UAMI; ensure the identity has the minimal roles needed.  
- The `.env` file may contain identifiers; store it in source control only if appropriate for your workflow.  
- Rerunning is safe; objects are created if missing and updated only when needed.

---

## Contributing

Feel free to open issues and PRs for improvements (e.g., adding namespace as a parameter, supporting multiple SAs, or exposing knobs via flags). Please follow conventional commit messages and include tests where feasible.

---

## License

This project is licensed under the **MIT License**. See `LICENSE` for details.

