variable "subscription_id" {
  description = "Azure subscription to deploy into (az account show --query id -o tsv)."
  type        = string
}

variable "location" {
  description = "Azure region. Must be allowed by the subscription's 'Allowed locations' policy and have model quota."
  type        = string
  default     = "polandcentral"
}

variable "prefix" {
  description = "Short name used in every resource name."
  type        = string
  default     = "aifsbx"

  validation {
    condition     = can(regex("^[a-z0-9]{3,10}$", var.prefix))
    error_message = "prefix must be 3-10 lowercase letters or digits."
  }
}

variable "environment" {
  description = "Environment tag value."
  type        = string
  default     = "sandbox"
}

variable "owner" {
  description = "Owner tag value (your name)."
  type        = string
}

variable "alert_email" {
  description = "Email that receives token-usage alerts and budget notifications."
  type        = string
}

# ---------- Model ----------

variable "deploy_model" {
  description = "Create the model deployment. Set false to deploy only the platform (e.g. while a new subscription's model deployments are held by Azure's fraud protection)."
  type        = bool
  default     = true
}

variable "model_name" {
  description = "OpenAI model to deploy in the Foundry resource."
  type        = string
  default     = "gpt-4.1-mini"
}

variable "model_version" {
  description = "Model version."
  type        = string
  default     = "2025-04-14"
}

variable "model_capacity" {
  description = "Deployment capacity in units of 1,000 tokens per minute (GlobalStandard)."
  type        = number
  default     = 10
}

# ---------- Governance / cost ----------

variable "enable_budget" {
  description = "Create a monthly cost budget on the resource group. Set false if your subscription offer does not support Cost Management budgets."
  type        = bool
  default     = true
}

variable "monthly_budget_usd" {
  description = "Monthly budget amount for the resource group."
  type        = number
  default     = 10
}

variable "enable_tag_policy" {
  description = "Assign the built-in 'Require a tag on resources' policy (owner tag) to the resource group."
  type        = bool
  default     = true
}

variable "token_alert_threshold" {
  description = "Alert when total tokens processed in one hour exceed this number."
  type        = number
  default     = 50000
}
