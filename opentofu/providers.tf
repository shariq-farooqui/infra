terraform {
  required_version = ">= 1.9"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.11"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      # Pinned to v4 until cloudflare.tf is migrated to v5 syntax
      # (cloudflare_record → cloudflare_dns_record, zone data source
      # changes, etc.). Tracked as a follow-up.
      version = "~> 5.0"
    }
  }
}

# GitHub App auth. The App's PEM signs a fresh 1-hour installation token per
# run, so laptop-side PATs aren't in the loop.
provider "github" {
  owner = "shariq-farooqui"

  app_auth {
    id              = var.github_app_id
    installation_id = var.github_installation_id
    pem_file        = file(var.github_app_pem_path)
  }
}

# Cloudflare provider reads CLOUDFLARE_API_TOKEN from the environment. Token
# scopes needed so far: Account > Workers R2 Storage:Edit (for the R2 bucket).
provider "cloudflare" {}
