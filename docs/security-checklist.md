# Network, Identity and Security Checklist

Status: ✅ implemented in this repo · 🟡 accepted for the sandbox (documented risk) · ⏭ production next step

## Identity & access

| Control | Status | How |
|---|---|---|
| API keys disabled; Entra ID only | ✅ | `disableLocalAuth = true` on the Foundry resource |
| Workloads use managed identity, not secrets | ✅ | User-assigned identity `id-app-*` |
| Least-privilege roles | ✅ | `Cognitive Services OpenAI User` scoped to the one Foundry resource |
| No Owner/Contributor for app identities | ✅ | Only data-plane roles are granted |
| MFA for administrators | ✅ | Enforced by the tenant for portal and CLI |
| Access granted via code review | ✅ | Role assignments live in `main.tf` |
| Periodic access review | ⏭ | Entra ID access reviews / PIM for elevated roles |

## Network

| Control | Status | How |
|---|---|---|
| Custom subdomain (required for Entra auth and private endpoints) | ✅ | `customSubDomainName` |
| Public network access | 🟡 | Enabled in the sandbox; access still requires an Entra token + RBAC |
| Private endpoint in a VNet | ⏭ | `Microsoft.Network/privateEndpoints`, group `account` |
| Private DNS zones | ⏭ | `privatelink.cognitiveservices.azure.com`, `privatelink.openai.azure.com`, `privatelink.services.ai.azure.com` |
| Disable public access | ⏭ | `publicNetworkAccess = "Disabled"` once the private endpoint is live |
| Controlled outbound connectivity | ⏭ | Azure Firewall / NAT Gateway with an allow-list |

## Data, logging & monitoring

| Control | Status | How |
|---|---|---|
| Diagnostic logs centralised | ✅ | All log categories → Log Analytics |
| Usage alerting | ✅ | Metric alert on processed tokens → email |
| Log retention defined | ✅ | 30 days, 1 GB/day cap |
| Customer-managed keys | ⏭ | Only if data classification requires it |

## Governance & cost

| Control | Status | How |
|---|---|---|
| Mandatory tagging | ✅ | Tags on every resource + policy requiring `owner` |
| Region restriction | ✅ | Subscription *Allowed locations* policy respected |
| Budget + notifications | ✅ | 50% / 80% actual, 100% forecast |
| Infrastructure is reproducible | ✅ | Terraform; no portal changes |
| IaC security scanning | ✅ | Checkov in CI (soft-fail; findings reviewed) |
| Decommission procedure | ✅ | `terraform destroy` + purge (runbook §8) |
