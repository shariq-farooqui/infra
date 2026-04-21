data "cloudflare_accounts" "main" {}

# R2 bucket for restic backups. Located in WEUR (western Europe) so the
# Falkenstein host has a short round-trip; R2 egress to the internet is
# free so region choice is about latency, not cost.
resource "cloudflare_r2_bucket" "backups" {
  account_id = data.cloudflare_accounts.main.accounts[0].id
  name       = "homelab"
  location   = "WEUR"
}

# Full S3-compatible URL for restic's r2_repository_url sops secret. Marked
# sensitive because the account ID in the hostname ties the repo to a
# specific Cloudflare account and shouldn't appear in CI logs.
output "restic_r2_repository_url" {
  description = "Paste into the r2_repository_url sops secret in nixos/hosts/homelab/secrets.yaml."
  value       = "s3:https://${data.cloudflare_accounts.main.accounts[0].id}.r2.cloudflarestorage.com/${cloudflare_r2_bucket.backups.name}"
  sensitive   = true
}
