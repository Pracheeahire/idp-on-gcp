output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.this.name
}

output "cluster_zone" {
  description = "Zone the cluster runs in."
  value       = google_container_cluster.this.location
}

output "registry_url" {
  description = "Artifact Registry path to push images to."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.apps.repository_id}"
}

output "get_credentials_command" {
  description = "Run this to point kubectl at the new cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --zone ${var.zone} --project ${var.project_id}"
}
