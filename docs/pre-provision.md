# AKS Pre‑Provision Script — Documentation

> **Script:** `pre-provision.sh`  
> **Purpose:** Pre‑provisioning for Azure Kubernetes Service (AKS). Ensures prerequisites, creates/ensures an Azure Resource Group, provisions an **Azure SSH public key**, creates a **local SSH key pair** if missing, and exports the SSH public key into an **AZD environment `.env`** for downstream use. fileciteturn0file0

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Parameters \& Defaults](#parameters--defaults)
- [What the Script Does (Step-by-Step)](#what-the-script-does-step-by-step)
- [Files Created \& Updated](#files-created--updated)
- [Functions \& Responsibilities](#functions--responsibilities)
- [Idempotency \& Safety](#idempotency--safety)
- [Logging \& Troubleshooting](#logging--troubleshooting)
- [Security Considerations](#security-considerations)
- [Usage Examples](#usage-examples)
- [Integration with Azure Developer CLI (AZD)](#integration-with-azure-developer-cli-azd)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

This script prepares your environment for deploying an **AKS cluster** with **Azure Developer CLI (AZD)**. It validates toolchain prerequisites, verifies Azure authentication, creates or reuses a **Resource Group**, creates or reuses an **Azure SSH key**, ensures a **local SSH key pair** exists, and exports the key to both an environment variable and an AZD environment `.env` file for consumption during cluster provisioning. fileciteturn0file0

> The script is written in **Bash**, follows **`set -euo pipefail`**, and uses a restrictive `IFS` to improve safety and reliability. fileciteturn0file0

---

## Prerequisites

- **Azure CLI** (`az`) — required for resource group \& SSH key commands.  
- **OpenSSH** tools (`ssh-keygen`).  
- **`jq`** — used to render the authenticated subscription name in logs (not strictly required for logic, but used by the script). fileciteturn0file0  
- **`sed`** — used to de‑duplicate `SSH_PUBLIC_KEY` entries in the `.env` file. fileciteturn0file0
- **Bash** (Linux/macOS/WSL).

> You must be **logged into Azure** (`az login`) and have the desired **subscription selected** (`az account set --subscription <id|name>`). The script checks login state. fileciteturn0file0

---

## Installation

Place `pre-provision.sh` in your repo (e.g., under `scripts/`). Make it executable:

```bash
chmod +x scripts/pre-provision.sh
```

Run from the repository root (so that the relative path to `./.azure/<env>/.env` works). fileciteturn0file0

---

## Usage

```bash
./pre-provision.sh <AZURE_ENV_NAME> <AZURE_LOCATION>
# Example:
./pre-provision.sh dev eastus2
```

- `AZURE_ENV_NAME`: A short logical name for your environment (e.g., `dev`, `test`, `prod`).  
- `AZURE_LOCATION`: Azure region short name (e.g., `eastus2`, `westus3`).

The script validates arguments and prints usage help if missing. fileciteturn0file0

---

## Parameters & Defaults

The script computes sensible defaults using your positional parameters: fileciteturn0file0

| Variable | Default | Description |
|---|---|---|
| `DEFAULT_RESOURCE_GROUP` | `contoso-aks-<env>-<location>-RG` | Target Azure Resource Group (created if absent). |
| `DEFAULT_SSH_KEY_NAME` | `aks-SSKey` | Name of the **Azure** SSH Public Key resource. |
| `DEFAULT_SSH_KEY_SIZE` | `4096` | Bit length for local RSA key generation. |
| `DEFAULT_SSH_KEY_TYPE` | `rsa` | Local SSH key type for `ssh-keygen`. |

> The default **local** key path is `~/.ssh/id_rsa`. If this file already exists, the script **does not overwrite** it. fileciteturn0file0

---

## What the Script Does (Step-by-Step)

1. **Validate parameters**: Requires `<AZURE_ENV_NAME>` and `<AZURE_LOCATION>`. fileciteturn0file0  
2. **Check prerequisites**: Ensures `az` and `ssh-keygen` are installed; logs a helpful error if missing. (Consider also installing `jq`.) fileciteturn0file0  
3. **Check Azure login**: Verifies `az account show` succeeds and logs current subscription name. (Uses `jq` for nice formatting.) fileciteturn0file0  
4. **Create/verify Resource Group**: `az group show`/`az group create`. Appends `AZURE_RESOURCE_GROUP_NAME="<rg>"` to `./.azure/<env>/.env`. fileciteturn0file0  
5. **Create/verify Azure SSH key**: `az sshkey show`/`az sshkey create` in the target RG/region. fileciteturn0file0  
6. **Create/verify local SSH key pair**: Uses `ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""`. fileciteturn0file0  
7. **Export SSH public key**: Reads Azure SSH key’s `publicKey`, exports `SSH_PUBLIC_KEY` in the process environment, and writes it to `./.azure/<env>/.env` (de‑duplicated). fileciteturn0file0

All operations are **idempotent**: resources are created **only if missing**, and local keys are preserved. fileciteturn0file0

---

## Files Created & Updated

- `./.azure/<AZURE_ENV_NAME>/.env`  
  - Appended/updated entries:
    - `AZURE_RESOURCE_GROUP_NAME="<rg-name>"` (set during RG creation)  
    - `SSH_PUBLIC_KEY="<public-key>"` (always kept single; previous entry removed if present)  
  - The folder is created if missing. fileciteturn0file0

> **External YAML files**: This script does **not** consume external YAML directly, but its outputs are designed for downstream **AZD** templates/flows that read environment variables from `.env`. If your provisioning pipeline uses YAML (e.g., `azure.yaml`, `infra/azure/aks.bicep` referenced by AZD), ensure it reads `SSH_PUBLIC_KEY` and (optionally) `AZURE_RESOURCE_GROUP_NAME` from the AZD environment. fileciteturn0file0

---

## Functions & Responsibilities

### `log_info`, `log_warning`, `log_error`  
Structured logging with timestamps and levels. Messages go to `stderr` for better scripting/CI behavior. fileciteturn0file0

### `usage`  
Prints a concise help message and examples. Used when parameters are invalid/missing. fileciteturn0file0

### `validate_parameters <env> <location>`  
Ensures two non‑empty arguments are provided; otherwise prints help and exits. fileciteturn0file0

### `check_prerequisites`  
Confirms `az` and `ssh-keygen` availability; suggests installing missing tools and exits on failure. (You may optionally add checks for `jq` and `sed`.) fileciteturn0file0

### `check_azure_login`  
Verifies Azure authentication via `az account show`; logs subscription name for clarity. fileciteturn0file0

### `create_resource_group <rg> <location> <env>`  
Creates the RG if it doesn’t exist; then persists `AZURE_RESOURCE_GROUP_NAME` to `./.azure/<env>/.env`. fileciteturn0file0

### `create_azure_ssh_key <sshKeyName> <rg> <location>`  
Creates the **Azure SSH Public Key** resource if missing. fileciteturn0file0

### `create_local_ssh_key`  
Creates a local RSA key pair at `~/.ssh/id_rsa` only if absent; uses a timestamped comment for traceability. fileciteturn0file0

### `export_ssh_public_key <sshKeyName> <rg> <env>`  
Reads the Azure SSH key’s `publicKey`, exports `SSH_PUBLIC_KEY`, ensures a single entry in `./.azure/<env>/.env`, and logs a short preview for verification. fileciteturn0file0

### `main`  
Coordinates the overall flow: validate → checks → RG → Azure SSH Key → local key → export key. fileciteturn0file0

---

## Idempotency & Safety

- **Resource Group** and **Azure SSH Key** are created only when absent.  
- **Local SSH key** is never overwritten if `~/.ssh/id_rsa` already exists.  
- `.env` updates are **de‑duplicated** to avoid repeated `SSH_PUBLIC_KEY` lines.  
- Strict Bash flags: `set -euo pipefail` and hardened `IFS`. fileciteturn0file0

---

## Logging & Troubleshooting

- Logs include ISO timestamps and levels (`INFO`, `WARNING`, `ERROR`).  
- Common issues:
  - **Not logged in**: run `az login`. Confirm subscription via `az account show`. fileciteturn0file0
  - **Missing tools**: install `azure-cli`, `openssh-client` (for `ssh-keygen`), and `jq`. fileciteturn0file0
  - **Insufficient permissions**: ensure RBAC allows RG and SSH key operations.

You can increase CLI verbosity by setting `AZURE_CORE_ONLY_SHOW_ERRORS=false` and passing `--debug` to `az` manually if investigating. (Not handled by the script.)

---

## Security Considerations

- The **public** key is stored in the AZD environment `.env`. Ensure your repo and CI systems protect this file appropriately.  
- The **private** key is stored locally at `~/.ssh/id_rsa` with default OpenSSH permissions. Do **not** commit or distribute private keys.  
- Consider using **Key Vault** or **managed identities** where appropriate in your broader solution.

---

## Usage Examples

Create an RG and key for a dev environment in East US 2:

```bash
./pre-provision.sh dev eastus2
```

Provision for a prod environment in West US 3:

```bash
./pre-provision.sh prod westus3
```

After running, inspect the AZD environment file:

```bash
cat ./.azure/dev/.env
# Expect lines like:
# AZURE_RESOURCE_GROUP_NAME="contoso-aks-dev-eastus2-RG"
# SSH_PUBLIC_KEY="ssh-rsa AAAA..."
```

---

## Integration with Azure Developer CLI (AZD)

This script writes variables into `./.azure/<env>/.env` so that **AZD** flows can consume them during provisioning. In your **AZD templates** (Bicep/Terraform/ARM), bind `SSH_PUBLIC_KEY` to the AKS cluster or node pool configuration as needed, and optionally use `AZURE_RESOURCE_GROUP_NAME` for consistent resource placement. fileciteturn0file0

> Tip: If your AZD pipeline uses YAML/JSON to compose infra parameters, map `SSH_PUBLIC_KEY` from the environment into those templates or `az deployment` parameters.

---

## Contributing

Contributions, issues, and feature requests are welcome! Please:
1. Open an issue describing the change or problem.
2. For PRs, include clear commit messages, updated docs/tests, and adhere to shell best practices (e.g., `shellcheck`).

---

## License

Unless a project-level license overrides this file, you can license this script under the **MIT License**. Add a `LICENSE` file at the repository root for clarity.

---

### Appendix: Command Reference

Key Azure CLI commands used by the script:

```bash
# Resource Group
az group show --name "<rg>"
az group create --name "<rg>" --location "<region>" --output none

# Azure SSH Public Key
az sshkey show   --name "<sshKeyName>" --resource-group "<rg>"
az sshkey create --name "<sshKeyName>" --resource-group "<rg>" --location "<region>" --output none
```

Local key generation:

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -C "AKS-SSH-Key-<timestamp>"
```
