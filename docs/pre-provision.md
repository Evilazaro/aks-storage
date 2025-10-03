# AKS Pre-Provision Script Documentation

> Script: `/infra/scripts/pre-provision.sh`
>
> Purpose: Idempotent pre-provision hook for Azure Kubernetes Service (AKS) environments using **Azure Developer CLI (azd)**. It validates tooling, ensures Azure authentication, creates (or reuses) a resource group and Azure SSH key, guarantees a local SSH keypair, and exports the SSH public key for downstream use during AKS cluster deployment.

---
## Key Features
- Safe to re-run (idempotent resource and key creation)
- Strict Bash safety flags (`set -euo pipefail`, hardened `IFS`)
- Centralized logging helpers (info / warning / error)
- Automatic population of environment-scoped `.env` file under `.azure/<env>`
- Generates or reuses both Azure-managed and local SSH keys
- Minimal external dependencies

---
## When It Runs (azd Hook Integration)
This script is invoked automatically as the `preprovision` hook declared in `azure.yaml`:

```yaml
hooks:
  preprovision:
    shell: sh
    run: ./infra/scripts/pre-provision.sh $AZURE_ENV_NAME $AZURE_LOCATION
```

You can also execute it manually for debugging:

```bash
bash ./infra/scripts/pre-provision.sh dev eastus2
```

---
## Inputs
| Position | Name              | Description                                      | Example    |
|----------|-------------------|--------------------------------------------------|------------|
| $1       | `AZURE_ENV_NAME`  | Logical environment name (maps to azd env)       | `dev`      |
| $2       | `AZURE_LOCATION`  | Azure region for resource deployment             | `eastus2`  |

> The script exits if either argument is missing or empty.

---
## Derived Defaults
| Variable / Concept          | Value / Pattern                                        | Notes |
|-----------------------------|--------------------------------------------------------|-------|
| Resource Group Name         | `contoso-aks-<env>-<location>-RG`                       | Built early using `$1` & `$2` |
| Azure SSH Key Name          | `aks-SSKey`                                            | Reused if exists |
| Local SSH Key Path          | `$HOME/.ssh/id_rsa`                                    | Generated if absent (RSA) |
| SSH Key Type                | `rsa`                                                   | Hard-coded constant |
| SSH Key Size (bits)         | `4096`                                                  | Adjustable only via code change |
| Environment Config File     | `.azure/<AZURE_ENV_NAME>/.env`                         | Appended / updated |

---
## Outputs & Side Effects
| Artifact | Description |
|----------|-------------|
| Azure Resource Group | Created if not already present. |
| Azure SSH Key | Created in the specified resource group if missing. |
| Local SSH Key Pair | Generated at `$HOME/.ssh/id_rsa` if absent (no passphrase). |
| Environment Variables | `SSH_PUBLIC_KEY` exported in current process. |
| `.env` File Entries | Appends / updates: `AZURE_RESOURCE_GROUP_NAME`, `SSH_PUBLIC_KEY`. |

The SSH public key is truncated in logs for security (`first 50 chars…`).

---
## Prerequisites
| Tool | Purpose | Install Reference |
|------|---------|-------------------|
| `bash` (≥4) | Script interpreter | Built-in (Linux/macOS), Git for Windows includes it |
| `az` (Azure CLI) | Resource group & SSH key operations | https://learn.microsoft.com/cli/azure/install-azure-cli |
| `ssh-keygen` | Local key generation | Provided by OpenSSH |
| `jq` | JSON parsing for subscription name logging | https://stedolan.github.io/jq/ |

> Note: The script currently checks for `azure-cli` and `ssh-keygen` only. You may wish to extend it to verify `jq` is installed.

### Azure Authentication
Login must already be established:
```bash
az login
az account set --subscription <SUBSCRIPTION_ID>
```

---
## Environment Configuration (.azure Directory)
For each azd environment, azd maintains a folder like `.azure/<env>`. This script appends or updates key entries in `.env` inside that folder:

| Key | Meaning |
|-----|---------|
| `AZURE_RESOURCE_GROUP_NAME` | Name of the resource group created / confirmed |
| `SSH_PUBLIC_KEY` | Retrieved Azure-managed SSH public key |

> Ensure `.azure/` (or at least its `.env` files) are excluded from version control if they contain sensitive data. Add to `.gitignore` if not already present.

---
## Function Reference
| Function | Responsibility | Notable Behaviors |
|----------|----------------|-------------------|
| `log_info`, `log_warning`, `log_error` | Structured timestamped logging | Write to stderr for visibility |
| `usage` | Prints usage help | Called on invalid args |
| `validate_parameters` | Ensures two non-empty arguments | Exits with code 1 on failure |
| `check_prerequisites` | Verifies required executables | Currently omits `jq` check |
| `check_azure_login` | Confirms Azure session & logs subscription | Uses `az account show`; requires `jq` |
| `create_resource_group` | Idempotent resource group ensure | Writes `AZURE_RESOURCE_GROUP_NAME` to `.env` |
| `create_azure_ssh_key` | Idempotent Azure SSH key ensure | Uses `az sshkey show/create` |
| `create_local_ssh_key` | Generates local RSA key | Skips if existing private key file found |
| `export_ssh_public_key` | Retrieves Azure public key & persists | Cleans prior `SSH_PUBLIC_KEY` line with `sed -i` |
| `main` | Orchestrates full workflow | Sets log context & sequence |

---
## Execution Flow
1. Log start metadata (script name, timestamp)
2. Validate arguments
3. Set local variables from positional parameters
4. Check tooling prerequisites
5. Verify Azure login state
6. Ensure resource group exists (create if needed)
7. Ensure Azure SSH key exists (create if needed)
8. Ensure local SSH key pair exists
9. Retrieve Azure SSH public key
10. Export & persist key to `.azure/<env>/.env`
11. Finish with success log

---
## Usage Examples
### Manual Run
```bash
bash ./infra/scripts/pre-provision.sh dev eastus2
```

### With Azure Developer CLI (azd)
After creating/setting an environment:
```bash
azd env new dev --location eastus2
azd up   # Will trigger preprovision hook automatically
```

### Testing Idempotency
Run multiple times; no duplicate resource creation should occur:
```bash
for i in 1 2 3; do bash ./infra/scripts/pre-provision.sh dev eastus2; done
```

---
## Troubleshooting
| Symptom | Possible Cause | Resolution |
|---------|----------------|-----------|
| `Missing required tools` | `az` or `ssh-keygen` not installed | Install dependencies, re-run |
| `Not logged into Azure` | No active `az login` session | Run `az login` + select subscription |
| `Failed to retrieve SSH public key` | Azure SSH key creation delayed or permission issue | Verify key exists: `az sshkey list` |
| `sed: command not found` / in-place edit issues (macOS) | BSD `sed` requires `-i ''` | Adjust script for cross-platform compatibility |
| `jq: command not found` | `jq` missing | Install `jq` or remove subscription name log |

---
## Security & Operational Notes
- Local private key is generated without a passphrase for automation simplicity—evaluate organizational policies before adopting.
- Truncation of the public key in logs mitigates inadvertent exposure but the full key still resides in the `.env` file.
- Consider rotating SSH keys periodically (manually delete Azure key + local key to force regeneration).
- Ensure principle of least privilege: the authenticated identity must have rights to create resource groups & ssh keys.

---
## Suggested Improvements (Optional Enhancements)
| Category | Suggestion |
|----------|-----------|
| Robustness | Move construction of `DEFAULT_RESOURCE_GROUP` into `main` after validation |
| Prerequisites | Add `jq` to `check_prerequisites` or refactor to avoid external JSON parser |
| Configurability | Accept flags (e.g. `--rg-name`, `--ssh-key-name`, `--ssh-key-size`) |
| Cross-platform | Handle macOS `sed -i` differences gracefully |
| Observability | Add `--output json` artifacts log or dry-run mode |
| Security | Optionally support ED25519 key type when supported by consuming services |

---
## Contributing
Contributions are welcome! Typical workflow:
1. Fork the repository
2. Create a feature branch: `git checkout -b feat/improve-preprovision`
3. Commit changes with clear messages
4. Open a Pull Request describing motivation & testing

Please include:
- Rationale for changes
- Before/after behavior (especially for idempotency)
- Any new prerequisites

---
## License
This project is licensed under the **MIT License**. See the [`LICENSE`](../LICENSE) file for details.

---
## Reference: Azure CLI Commands Used
| Purpose | Command Pattern |
|---------|-----------------|
| Show subscription | `az account show --query '{subscriptionId:id, subscriptionName:name}' -o json` |
| Show resource group | `az group show --name <rg>` |
| Create resource group | `az group create --name <rg> --location <location>` |
| Show SSH key | `az sshkey show --name <name> --resource-group <rg>` |
| Create SSH key | `az sshkey create --name <name> --resource-group <rg> --location <location>` |
| Show SSH public key | `az sshkey show --query publicKey --output tsv ...` |

---
## Quick Reference (Cheat Sheet)
```bash
# Run pre-provision for dev in eastus2
bash /infra/scripts/pre-provision.sh dev eastus2

# Verify resource group exists
a z group show --name contoso-aks-dev-eastus2-RG

# List Azure SSH keys
a z sshkey list -o table

# Inspect generated .env
cat .azure/dev/.env
```

---
## Disclaimer
This documentation reflects the current implementation of `pre-provision.sh`. If you modify the script (variable names, hooks, tooling), update this file to preserve accuracy.
