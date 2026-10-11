# Keyless authentication from GitHub Actions to GCP (Workload Identity Federation).
#
# This lives in its own folder with its own state, separate from infra/terraform,
# because it has a different lifecycle: apply it ONCE and leave it. It costs nothing.
# The main infra is destroyed every night; if this were destroyed too, the pool ID
# could not be reused for 30 days (GCP soft-deletes identity pools).

terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # terraform init -backend-config="bucket=<your-state-bucket>"
  backend "gcs" {
    prefix = "idp-on-gcp/github-oidc"
  }
}

provider "google" {
  project = var.project_id
}

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository allowed to deploy, as owner/name."
  type        = string
}

resource "google_project_service" "apis" {
  for_each = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

# 1. A pool that holds identities coming from outside GCP.
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"

  depends_on = [google_project_service.apis]
}

# 2. A provider that trusts GitHub's OIDC tokens, but ONLY from your repo's main branch.
resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  display_name                       = "GitHub Actions OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  attribute_condition = "assertion.repository == '${var.github_repo}' && assertion.ref == 'refs/heads/main'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# 3. The service account the pipeline acts as, with only the roles it needs.
resource "google_service_account" "deployer" {
  account_id   = "github-deployer"
  display_name = "GitHub Actions deployer"
}

resource "google_project_iam_member" "deployer" {
  for_each = toset([
    "roles/artifactregistry.writer", # push images
    "roles/container.developer",     # deploy to GKE
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

# 4. Allow identities from your repo (via the pool) to act as that service account.
resource "google_service_account_iam_member" "github_can_impersonate" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

output "workload_identity_provider" {
  description = "Paste into GitHub repo variable GCP_WIF_PROVIDER."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "deployer_service_account" {
  description = "Paste into GitHub repo variable GCP_DEPLOYER_SA."
  value       = google_service_account.deployer.email
}
