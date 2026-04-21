resource "github_repository" "infra" {
  name        = "infra"
  description = "Declarative infrastructure for my single-node homelab."
  visibility  = "public"
  topics      = ["homelab", "infrastructure-as-code"]

  has_issues      = true
  has_discussions = false
  has_projects    = false
  has_wiki        = false

  # Merge flow is local rebase + `git merge --ff-only` + direct push to main.
  # The UI merge buttons are never used. GitHub refuses to disable all three
  # together when required_linear_history is on, so squash stays enabled and
  # the discipline is "don't click it". Rebase-merge would replay commits as
  # unsigned and fail require_signed_commits; merge-commit would break linear
  # history.
  allow_merge_commit     = false
  allow_rebase_merge     = false
  allow_squash_merge     = true
  allow_auto_merge       = false
  delete_branch_on_merge = true

  lifecycle {
    prevent_destroy = true
  }
}

# main's protection: signed commits, linear history, passing CI. PR reviews
# not required; the merge flow is an ff-push from the laptop, not a UI click.
resource "github_branch_protection" "main" {
  repository_id = github_repository.infra.node_id
  pattern       = "main"

  enforce_admins          = true
  require_signed_commits  = true
  required_linear_history = true
  allows_force_pushes     = false
  allows_deletions        = false

  required_status_checks {
    strict   = true
    contexts = ["pre-commit"]
  }
}
