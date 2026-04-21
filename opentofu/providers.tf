terraform {
  required_version = ">= 1.9"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.11"
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
