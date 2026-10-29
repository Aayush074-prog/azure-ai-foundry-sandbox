# Runbook: Azure AI Foundry Sandbox

Commands are for Windows PowerShell. Run them from the repository root unless a step says otherwise.

## 1. Prerequisites

| Tool | Check | Install |
|---|---|---|
| Azure CLI | `az --version` | `winget install Microsoft.AzureCLI` |
| Terraform ≥ 1.9 | `terraform -version` | `winget install Hashicorp.Terraform` |
| Python ≥ 3.10 | `python --version` | `winget install Python.Python.3.12` |
| Git | `git --version` | `winget install Git.Git` |

Access: **Owner** on the subscription. Owner is needed because the deployment creates role
assignments; Contributor can't do that.

## 2. Pre-flight checks

```powershell
# Sign in to the tenant that holds the subscription (triggers MFA if required)
az login --tenant <tenant-id>
az account show --query "{name:name, id:id, tenant:tenantId}" -o table

# Which regions does policy allow?
az policy assignment list --query "[].displayName" -o table

# Is there model quota in the target region? (Limit > 0 is what matters)
az cognitiveservices usage list -l polandcentral `
  --query "[?contains(name.value,'OpenAI')].{model:name.value, used:currentValue, limit:limit}" -o table

# Providers registered?
az provider show -n Microsoft.CognitiveServices --query registrationState -o tsv
az provider show -n Microsoft.OperationalInsights --query registrationState -o tsv
az provider show -n Microsoft.Insights --query registrationState -o tsv
```

If a provider shows `NotRegistered`: `az provider register -n <namespace>`, then wait 2–3 minutes.

## 3. Deploy

```powershell
cd infra
copy terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars          # set subscription_id, owner, alert_email

terraform init
terraform plan -out tfplan        # review what will be created
terraform apply tfplan            # about 5–10 minutes
terraform output
```

## 4. Verify

```powershell
cd ..
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r app/requirements.txt

python app/chat.py "Explain private endpoints in two sentences."
```

Expected: a short answer, then a line showing the deployment name, latency and token counts.

Also confirm that API keys really are disabled. This should fail:

```powershell
$rg = terraform -chdir=infra output -raw resource_group_name
$ais = terraform -chdir=infra output -raw foundry_name
az cognitiveservices account keys list -g $rg -n $ais
```

## 5. Monitor

- **Metrics:** Portal → Foundry resource → *Metrics* → *Processed Inference Tokens*, *Requests*, *Latency*.
- **Logs (KQL)** in the Log Analytics workspace:

```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| summarize requests = count() by OperationName, bin(TimeGenerated, 15m)
| order by TimeGenerated desc
```

```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES" and toint(ResultSignature) >= 400
| project TimeGenerated, OperationName, ResultSignature, CallerIPAddress
```

Logs take 5–15 minutes to arrive after the first requests.

- **Alerts:** the token-usage alert emails `alert_email` when tokens processed in one hour exceed
  `token_alert_threshold`.
- **Cost:** Portal → Cost Management → Budgets → `budget-*`.

## 6. Access requests

Grant a teammate permission to call models. Add a role assignment in `main.tf` (preferred, since
it's reviewed in Git), or for a one-off:

```powershell
$id = az cognitiveservices account show -g $rg -n $ais --query id -o tsv
az role assignment create --role "Cognitive Services OpenAI User" --assignee <user@domain> --scope $id
```

Remove access with `az role assignment delete` using the same arguments. Use the narrowest role
that works: `Cognitive Services OpenAI User` to call models, `Contributor` only for people who
manage the resource.

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `AADSTS50076` / "No subscriptions found" on `az login` | Tenant requires MFA | `az login --tenant <tenant-id>` and complete MFA |
| `RequestDisallowedByPolicy` on apply | Region not in *Allowed locations* | Set `location` to an allowed region |
| `InsufficientQuota` on the model deployment | No quota for that model/SKU in the region | Check quota (step 2); change `model_name` or lower `model_capacity` |
| `401` / `PermissionDenied` from `chat.py` | Role assignment still propagating, or logged in as a different user | Wait 5 minutes; check `az account show` |
| Budget resource fails to create | Subscription offer doesn't support budgets via API | Set `enable_budget = false` |
| `CustomDomainInUse` / name conflict after a destroy | Foundry resource is soft-deleted | Purge it (step 8) |
| `715-123420` "unusual activity" on the model deployment | Azure fraud protection holds model deployments on some new subscriptions | Don't retry repeatedly. Set `deploy_model = false` so the platform still applies, retry once after a few hours, and raise it on Microsoft Q&A if it persists |
| Model or version not found | Version not offered in region | `az cognitiveservices model list -l <region> --query "[?model.name=='gpt-4.1-mini'].model.version"` |

## 8. Decommission

```powershell
cd infra
terraform destroy

# Foundry resources are soft-deleted; purge to free the name and quota
az cognitiveservices account list-deleted -o table
az cognitiveservices account purge --name <foundry-name> --resource-group <rg-name> --location <region>
```

## Next steps

- Remote state: an Azure Storage account + `backend "azurerm"` block with state locking.
- GitHub OIDC: an app registration with a federated credential, so CI can run `terraform plan`
  without stored secrets.
- Private networking: see `security-checklist.md`.
