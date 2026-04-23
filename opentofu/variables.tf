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

variable "homelab_public_ip" {
  type        = string
  description = "Public IPv4 of the homelab's Hetzner host. Referenced by Cloudflare A records for farooqui.ai subdomains. Set via TF_VAR_homelab_public_ip in .envrc so the value doesn't land in source."
}

variable "homelab_tailnet_ip" {
  type        = string
  description = "Tailnet (100.x.y.z) IPv4 of the homelab host. Backs the wildcard farooqui.ai record so private services resolve to a CGNAT address only routable from the tailnet. Set via TF_VAR_homelab_tailnet_ip in .envrc."
}
