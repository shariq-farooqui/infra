variable "github_app_id" {
  type        = string
  description = "Numeric App ID of the GitHub App used for authentication."
}

variable "github_installation_id" {
  type        = string
  description = "Installation ID of the GitHub App on this account."
}

variable "github_app_pem_path" {
  type        = string
  description = "Absolute path to the App's private key PEM on the operator's machine."
}
