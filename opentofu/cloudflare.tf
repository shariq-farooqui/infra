data "cloudflare_accounts" "main" {}

data "cloudflare_zone" "farooqui" {
  name = "farooqui.ai"
}

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

# A records for the public services. CF proxy (orange cloud) terminates
# TLS at the edge and forwards to the origin over the AOP mTLS channel
# configured below, so the homelab's public IP isn't advertised in DNS.
resource "cloudflare_record" "apex" {
  zone_id = data.cloudflare_zone.farooqui.id
  name    = "@"
  type    = "A"
  content = var.homelab_public_ip
  proxied = true
  ttl     = 1 # 1 = "automatic" when proxied
  comment = "Personal site"
}

resource "cloudflare_record" "www" {
  zone_id = data.cloudflare_zone.farooqui.id
  name    = "www"
  type    = "A"
  content = var.homelab_public_ip
  proxied = true
  ttl     = 1
  comment = "Personal site (www alias)"
}

resource "cloudflare_record" "status" {
  zone_id = data.cloudflare_zone.farooqui.id
  name    = "status"
  type    = "A"
  content = var.homelab_public_ip
  proxied = true
  ttl     = 1
  comment = "Gatus uptime page"
}

resource "cloudflare_record" "analytics" {
  zone_id = data.cloudflare_zone.farooqui.id
  name    = "analytics"
  type    = "A"
  content = var.homelab_public_ip
  proxied = true
  ttl     = 1
  comment = "Umami analytics"
}

# Wildcard for tailnet-only services. Points at the homelab's CGNAT
# tailnet address, so every subdomain not explicitly declared above
# resolves to 100.x.y.z. Off-tailnet devices get an unroutable IP and
# the connection times out; tailnet devices reach Traefik via
# WireGuard. Explicit A records (apex, www, status, analytics) take
# DNS precedence over this wildcard, so public services continue to
# flow through Cloudflare's proxy. Not proxied because CF won't
# forward to a non-routable origin.
resource "cloudflare_record" "wildcard_tailnet" {
  zone_id = data.cloudflare_zone.farooqui.id
  name    = "*"
  type    = "A"
  content = var.homelab_tailnet_ip
  proxied = false
  ttl     = 1
  comment = "Tailnet-only services (fallback for unlisted subdomains)"
}

# Authenticated Origin Pulls: CF presents a client cert signed by the
# Origin Pull CA on every fetch; Traefik's TLSOption in the cluster
# requires that client cert. Together these ensure only CF can speak
# TLS to the origin; a direct-IP request fails at the TLS handshake.
resource "cloudflare_authenticated_origin_pulls" "farooqui" {
  zone_id = data.cloudflare_zone.farooqui.id
  enabled = true
}

# Zone-wide "Always Use HTTPS": CF rewrites any inbound http:// URL to
# https:// with a 301, so a typed-wrong link doesn't hit plain HTTP.
resource "cloudflare_zone_settings_override" "farooqui" {
  zone_id = data.cloudflare_zone.farooqui.id
  settings {
    always_use_https = "on"
  }
}
