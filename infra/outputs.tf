output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "foundry_name" {
  value = azapi_resource.foundry.name
}

output "openai_endpoint" {
  description = "Azure OpenAI-compatible endpoint used by app/chat.py."
  value       = "https://${local.foundry_name}.openai.azure.com/"
}

output "project_endpoint" {
  description = "Foundry project endpoint (for the Foundry SDK / portal)."
  value       = "https://${local.foundry_name}.services.ai.azure.com/api/projects/${azapi_resource.project.name}"
}

output "deployment_name" {
  value = var.deploy_model ? azapi_resource.chat_deployment[0].name : "not-deployed"
}

output "app_identity_client_id" {
  description = "Client ID of the workload managed identity (use as AZURE_CLIENT_ID on Azure compute)."
  value       = azurerm_user_assigned_identity.app.client_id
}

output "log_analytics_workspace_name" {
  value = azurerm_log_analytics_workspace.law.name
}
