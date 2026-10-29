data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

locals {
  suffix = random_string.suffix.result
  base   = "${var.prefix}-${local.suffix}"

  # Every resource gets the same tags so cost, ownership and lifecycle
  # can be reported on and enforced (see the tag policy at the bottom).
  tags = {
    project     = "azure-ai-foundry-sandbox"
    environment = var.environment
    owner       = var.owner
    managed_by  = "terraform"
  }

  foundry_name = "${var.prefix}-ais-${local.suffix}"
  budget_start = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
}

# ---------------------------------------------------------------------------
# Resource group
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.base}"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Observability: Log Analytics workspace
# ---------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "law" {
  name                = "log-${local.base}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 1 # cost guard for a sandbox
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# Azure AI Foundry resource (kind = AIServices)
#   - disableLocalAuth = true  -> API keys are OFF, only Microsoft Entra ID
#   - customSubDomainName      -> required for Entra ID token auth
#   - allowProjectManagement   -> lets us create Foundry projects under it
# Deployed with azapi so the latest ARM properties are available.
# ---------------------------------------------------------------------------

resource "azapi_resource" "foundry" {
  type                      = "Microsoft.CognitiveServices/accounts@2025-06-01"
  name                      = local.foundry_name
  parent_id                 = azurerm_resource_group.rg.id
  location                  = var.location
  tags                      = local.tags
  schema_validation_enabled = false

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "AIServices"
    sku = {
      name = "S0"
    }
    properties = {
      customSubDomainName    = local.foundry_name
      allowProjectManagement = true
      disableLocalAuth       = true
      # Sandbox keeps a public endpoint (protected by Entra ID + RBAC).
      # Production hardening: set to "Disabled" and add a private endpoint.
      # See docs/security-checklist.md.
      publicNetworkAccess = "Enabled"
      networkAcls = {
        defaultAction = "Allow"
      }
    }
  }

  response_export_values = ["properties.endpoint"]
}

resource "azapi_resource" "project" {
  type                      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name                      = "proj-${local.base}"
  parent_id                 = azapi_resource.foundry.id
  location                  = var.location
  tags                      = local.tags
  schema_validation_enabled = false

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      displayName = "Foundry sandbox project"
      description = "Governed sandbox project deployed with Terraform."
    }
  }
}

resource "azapi_resource" "chat_deployment" {
  count                     = var.deploy_model ? 1 : 0
  type                      = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
  name                      = var.model_name
  parent_id                 = azapi_resource.foundry.id
  schema_validation_enabled = false

  body = {
    sku = {
      name     = "GlobalStandard"
      capacity = var.model_capacity
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = var.model_name
        version = var.model_version
      }
    }
  }

  # Account-level operations on the same resource must not run in parallel.
  depends_on = [azapi_resource.project]
}

# ---------------------------------------------------------------------------
# Identity & access (least privilege)
# ---------------------------------------------------------------------------

# Workload identity for an app that will call the model (e.g. a Container
# App or Function). No keys or secrets: it authenticates with Entra ID.
resource "azurerm_user_assigned_identity" "app" {
  name                = "id-app-${local.base}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

# The app identity can only call models on this one resource:
# no management rights, no access to anything else in the subscription.
resource "azurerm_role_assignment" "app_openai_user" {
  scope                = azapi_resource.foundry.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
  principal_type       = "ServicePrincipal"
}

# The person running Terraform gets the same data-plane role so the local
# Python client (DefaultAzureCredential -> Azure CLI login) can call the model.
resource "azurerm_role_assignment" "deployer_openai_user" {
  scope                = azapi_resource.foundry.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------------------
# Monitoring: logs, alerting
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "foundry" {
  name                       = "diag-to-law"
  target_resource_id         = azapi_resource.foundry.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category_group = "allLogs"
  }
}

resource "azurerm_monitor_action_group" "ops" {
  name                = "ag-${local.base}"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "aifsbxops"
  tags                = local.tags

  email_receiver {
    name                    = "owner-email"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

resource "azurerm_monitor_metric_alert" "token_usage" {
  name                = "alert-token-usage-${local.base}"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azapi_resource.foundry.id]
  description         = "Total tokens processed in the last hour exceeded the threshold."
  severity            = 3
  frequency           = "PT15M"
  window_size         = "PT1H"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.CognitiveServices/accounts"
    metric_name      = "TokenTransaction"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.token_alert_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }
}

# ---------------------------------------------------------------------------
# Governance: budget + tag policy
# ---------------------------------------------------------------------------

resource "azurerm_consumption_budget_resource_group" "rg" {
  count             = var.enable_budget ? 1 : 0
  name              = "budget-${local.base}"
  resource_group_id = azurerm_resource_group.rg.id
  amount            = var.monthly_budget_usd
  time_grain        = "Monthly"

  time_period {
    start_date = local.budget_start
  }

  notification {
    enabled        = true
    threshold      = 50
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = [var.alert_email]
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = [var.alert_email]
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = [var.alert_email]
  }

  lifecycle {
    # start_date is computed from the current month on first apply only.
    ignore_changes = [time_period]
  }
}

data "azurerm_policy_definition" "require_tag" {
  display_name = "Require a tag on resources"
}

# Any new resource in this resource group without an "owner" tag is denied.
# Created last so it never blocks this deployment itself.
resource "azurerm_resource_group_policy_assignment" "require_owner_tag" {
  count                = var.enable_tag_policy ? 1 : 0
  name                 = "require-owner-tag"
  display_name         = "Require 'owner' tag on all resources"
  resource_group_id    = azurerm_resource_group.rg.id
  policy_definition_id = data.azurerm_policy_definition.require_tag.id

  parameters = jsonencode({
    tagName = { value = "owner" }
  })

  depends_on = [
    azurerm_log_analytics_workspace.law,
    azapi_resource.foundry,
    azapi_resource.project,
    azapi_resource.chat_deployment,
    azurerm_user_assigned_identity.app,
    azurerm_monitor_action_group.ops,
    azurerm_monitor_metric_alert.token_usage,
  ]
}
