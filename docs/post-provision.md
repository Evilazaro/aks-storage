# AKS Post-Provision Script Documentation

> Script: `/infra/scripts/post-provision.sh`
>
> Purpose: Idempotent post-provision hook for Azure Kubernetes Service (AKS) environments using **Azure Developer CLI (azd)**. It configures Azure AD Workload Identity by creating (or reusing) a user-assigned managed identity, Kubernetes service account, and a federated identity credential binding the two via the AKS OIDC issuer.

---
## Key Features
- Safe to re-run (idempotent Azure + Kubernetes resource creation)
- Enforces Bash safety (`set -euo pipefail`, hardened `IFS`)
- Structured logging (info / warning / error / success)
- Automatically persists created resource metadata into `.azure/<env>/.env`
- Produces minimal required objects for Workload Identity enablement
- Clearly logs follow‑up pod spec snippet for developers

---
## When It Runs (azd Hook Integration)
Declared in `azure.yaml` as the `postprovision` hook (runs after infrastructure provisioning):

```yaml
hooks:
  postprovision:
    shell: sh
    run: |
      ./infra/scripts/post-provision.sh \
        $AZURE_ENV_NAME \
        $AZURE_LOCATION \
        $AZURE_RESOURCE_GROUP_NAME \
        $AZURE_SUBSCRIPTION_ID \
        $AKS_CLUSTER_NAME \
        $AKS_OIDC_ISSUER
```

Manual execution (for diagnostics):
```bash
bash ./infra/scripts/post-provision.sh dev eastus2 contoso-aks-dev-eastus2-RG 12345678-1234-1234-1234-123456789012 aks-dev-eastus2 https://eastus2.oic.prod-aks.azure.com/12345678-1234-1234-1234-123456789012/
```

---
## Inputs
| Position | Name | Description | Example |
|----------|------|-------------|---------|
| $1 | `AZURE_ENV_NAME` | azd environment logical name | `dev` |
| $2 | `AZURE_LOCATION` | Azure region | `eastus2` |
| $3 | `RESOURCE_GROUP` | Existing resource group containing AKS | `contoso-aks-dev-eastus2-RG` |
| $4 | `SUBSCRIPTION_ID` | Azure subscription GUID | `12345678-1234-...` |
| $5 | `AKS_CLUSTER_NAME` | Target AKS cluster name | `aks-dev-eastus2` |
| $6 | `AKS_OIDC_ISSUER` | AKS OIDC issuer URL | `https://eastus2.oic.prod-aks.azure.com/.../` |

Validation performed:
- Presence & non-empty for all 6 arguments
- `AKS_OIDC_ISSUER` must start with `https://`

---
## Derived Resource Names & Constants
| Symbol | Pattern / Value | Purpose |
|--------|------------------|---------|
| `IDENTITY_SUFFIX` | `identity` | Suffix appended to cluster name for managed identity |
| `SERVICE_ACCOUNT_SUFFIX` | `wi-sa` | Suffix appended for service account name |
| `CREDENTIAL_SUFFIX` | `fed-cred` | Suffix appended for federated credential |
| Managed Identity Name | `<AKS_CLUSTER_NAME>-identity` | User-assigned identity resource |
| Service Account Name | `<AKS_CLUSTER_NAME>-wi-sa` | Kubernetes ServiceAccount |
| Federated Credential Name | `<AKS_CLUSTER_NAME>-fed-cred` | AAD federated identity credential |
| `DEFAULT_SERVICE_ACCOUNT_NAMESPACE` | `default` | Namespace for service account |
| `WORKLOAD_IDENTITY_AUDIENCE` | `api://AzureADTokenExchange` | Azure AD Workload Identity expected audience |

---
## Outputs & Side Effects
| Artifact | Description |
|----------|-------------|
| User-assigned Managed Identity | Created or reused; client ID captured |
| Kubernetes ServiceAccount | Created or updated with `azure.workload.identity/client-id` annotation |
| Federated Identity Credential | Binds OIDC subject to managed identity |
| Environment Variables (exported) | `USER_ASSIGNED_IDENTITY_NAME`, `USER_ASSIGNED_CLIENT_ID`, `SERVICE_ACCOUNT_NAMESPACE`, `SERVICE_ACCOUNT_NAME`, `FEDERATED_IDENTITY_CREDENTIAL_NAME` |
| `.azure/<env>/.env` entries | Same keys persisted for downstream tooling |
| kubectl context | Updated via `az aks get-credentials` |

Subject used for federated credential: `system:serviceaccount:<namespace>:<serviceAccountName>`.

---
## Prerequisites
| Tool | Purpose | Install Reference |
|------|---------|-------------------|
| `az` | Managed identity + federated credential + AKS credentials | https://learn.microsoft.com/cli/azure/install-azure-cli |
| `kubectl` | Interact with Kubernetes API | https://kubernetes.io/docs/tasks/tools/ |
| `jq` (optional) | Pretty subscription name fallback | https://stedolan.github.io/jq/ |

### Azure Authentication
Ensure an authenticated session and correct subscription:
```bash
az login
az account set --subscription <SUBSCRIPTION_ID>
```

### AKS Cluster
The AKS cluster referenced must already exist and have OIDC issuer enabled (AKS Workload Identity requires OIDC).

---
## Environment Configuration (.azure Directory)
The script stores state in `.azure/<AZURE_ENV_NAME>/.env` using an idempotent helper that removes prior key lines before appending. Keys written:
- `USER_ASSIGNED_IDENTITY_NAME`
- `USER_ASSIGNED_CLIENT_ID`
- `SERVICE_ACCOUNT_NAMESPACE`
- `SERVICE_ACCOUNT_NAME`
- `FEDERATED_IDENTITY_CREDENTIAL_NAME`

Keep this file out of version control if it may contain environment‑specific sensitive identifiers.

---
## Function Reference
| Function | Responsibility | Notable Details |
|----------|----------------|-----------------|
| `log_info` / `log_warning` / `log_error` / `log_success` | Structured timestamped logging | All to stderr for clarity |
| `usage` | Prints argument help text | Called on validation failure |
| `validate_parameters` | Validates positional args & OIDC URL | Lists missing params collectively |
| `check_prerequisites` | Ensures `az` & `kubectl` are installed | Could optionally add `jq` check |
| `check_azure_login` | Confirms active Azure session | Uses `jq` for subscription name; falls back to ID |
| `update_env_file` | Idempotently writes key=value into env file | Uses `sed -i` (GNU style) |
| `configure_kubectl` | Fetches AKS credentials, verifies cluster | Uses `az aks get-credentials` + `kubectl cluster-info` |
| `create_managed_identity` | Creates or reuses user-assigned identity | Exports name & client ID |
| `create_service_account` | Creates/updates annotated Kubernetes SA | Applies YAML manifest or updates annotation |
| `create_federated_credential` | Creates federated identity credential | Audience fixed: `api://AzureADTokenExchange` |
| `main` | Orchestrates full flow & logging | Generates deterministic resource names |

---
## Execution Flow
1. Log start metadata
2. Validate & parse arguments
3. Derive resource names with suffixes
4. Check prerequisites + Azure login
5. Configure `kubectl` credentials for cluster
6. Create / ensure managed identity; capture client ID
7. Create / ensure Kubernetes service account with annotation
8. Create / ensure federated identity credential
9. Export and persist environment metadata
10. Output usage guidance for pod manifests

---
## Usage Examples
### Standard Run (after azd provisioning)
```bash
azd up        # Triggers pre & post hooks automatically
```

### Manual Re-run (Safe / Idempotent)
```bash
bash ./infra/scripts/post-provision.sh \
  dev eastus2 contoso-aks-dev-eastus2-RG \
  12345678-1234-1234-1234-123456789012 \
  aks-dev-eastus2 \
  https://eastus2.oic.prod-aks.azure.com/12345678-1234-1234-1234-123456789012/
```

### Inspect Created Identity
```bash
az identity show --resource-group contoso-aks-dev-eastus2-RG --name aks-dev-eastus2-identity -o table
```

### Verify Service Account Annotation
```bash
kubectl get sa aks-dev-eastus2-wi-sa -o yaml | grep -A2 annotations
```

### Verify Federated Credential
```bash
az identity federated-credential list \
  --identity-name aks-dev-eastus2-identity \
  --resource-group contoso-aks-dev-eastus2-RG \
  -o table
```

---
## Adding Workload Identity to a Pod
Add the following to your pod manifest (values auto-generated):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sample-wi-pod
spec:
  serviceAccountName: aks-dev-eastus2-wi-sa
  containers:
    - name: app
      image: your-image
      env:
        - name: AZURE_CLIENT_ID
          value: "${USER_ASSIGNED_CLIENT_ID}"  # Inject from environment or template
```

---
## Troubleshooting
| Symptom | Cause | Resolution |
|---------|-------|-----------|
| `Missing required tools` | `az` or `kubectl` absent | Install tools, re-run |
| `Not logged into Azure` | No active session | Run `az login` & set subscription |
| `Failed to configure kubectl` | RBAC or cluster name mismatch | Verify RG + cluster names; check role assignment |
| `Managed identity creation failed` | Permission or quota issues | Confirm Contributor role & regional quotas |
| `Federated identity credential failed` | OIDC not enabled or wrong issuer URL | Verify AKS OIDC issuer: `az aks show --query oidcIssuerProfile.issuerUrl` |
| SA annotation mismatch persists | Caching / race | Re-run script; ensure cluster reachable |

---
## Security & Operational Notes
- User-assigned identity client ID is logged partially (prefix only) to reduce risk of sensitive exposure.
- Federated credential ties to a specific ServiceAccount subject; renaming requires recreation.
- Audience is fixed; modifying may break Workload Identity token exchange.
- Consider scoping identity role assignments minimally (e.g., only required resource group or specific resources).
- Ensure `.azure/<env>/.env` isn’t committed if containing environment-sensitive identifiers.

---
## Suggested Improvements
| Category | Suggestion |
|----------|-----------|
| Robustness | Detect and adapt `sed -i` differences on macOS |
| Configurability | Accept flags (`--namespace`, `--identity-suffix`, etc.) |
| Validation | Pre-check that AKS OIDC issuer matches cluster value dynamically |
| Observability | Emit JSON summary of created resources for CI ingestion |
| Security | Optional toggle to suppress logging client ID entirely |
| Multi-Env | Support non-`default` namespace via parameter |

---
## Contributing
1. Fork repository
2. Create branch: `git checkout -b feat/enhance-postprovision`
3. Make changes & add/update documentation
4. Open Pull Request describing purpose and testing steps

Please document:
- Any new arguments or environment keys
- Behavioral changes (especially idempotency impacts)
- Required role assignments or permissions

---
## License
Licensed under the **MIT License**. See [`LICENSE`](../LICENSE) for full text.

---
## Azure CLI & kubectl Commands Reference
| Purpose | Command Pattern |
|---------|-----------------|
| Get AKS credentials | `az aks get-credentials --resource-group <rg> --name <cluster>` |
| Show identity | `az identity show --resource-group <rg> --name <name>` |
| Create identity | `az identity create --resource-group <rg> --name <name> --location <loc>` |
| List federated credentials | `az identity federated-credential list --identity-name <id> --resource-group <rg>` |
| Create federated credential | `az identity federated-credential create --identity-name <id> --name <cred> ...` |
| Get ServiceAccount | `kubectl get sa <name> -n <ns> -o yaml` |
| Apply manifest | `kubectl apply -f <file>` |

---
## Quick Reference (Cheat Sheet)
```bash
# Run post-provision manually
bash /infra/scripts/post-provision.sh dev eastus2 contoso-aks-dev-eastus2-RG <SUB_ID> aks-dev-eastus2 <OIDC_ISSUER>

# Show managed identity client ID
az identity show -g contoso-aks-dev-eastus2-RG -n aks-dev-eastus2-identity --query clientId -o tsv

# Verify service account annotation
kubectl get sa aks-dev-eastus2-wi-sa -o jsonpath='{.metadata.annotations.azure\.workload\.identity/client-id}'

# List federated credentials
az identity federated-credential list -g contoso-aks-dev-eastus2-RG --identity-name aks-dev-eastus2-identity -o table
```

---
## Disclaimer
If you alter naming conventions, argument order, or add flags, update this documentation to reflect changes and avoid drift.
