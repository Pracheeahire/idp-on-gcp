resource "google_artifact_registry_repository" "apps" {
  location      = var.region
  repository_id = "apps"
  description   = "Container images built by CI"
  format        = "DOCKER"

  # Keep the registry small: delete untagged images after 7 days.
  cleanup_policies {
    id     = "delete-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "604800s"
    }
  }

  depends_on = [google_project_service.apis]
}
