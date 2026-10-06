# Least-privilege identity for the nodes instead of the default compute SA.
resource "google_service_account" "nodes" {
  account_id   = "${var.cluster_name}-nodes"
  display_name = "GKE nodes for ${var.cluster_name}"
}

resource "google_project_iam_member" "nodes" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/artifactregistry.reader",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.zone

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.gke.id

  # Manage nodes in a separate node pool resource.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Lab cluster: allow `terraform destroy` every night to save cost.
  deletion_protection = false

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }

  depends_on = [google_project_service.apis]
}

resource "google_container_node_pool" "general" {
  name     = "general"
  cluster  = google_container_cluster.this.id
  location = var.zone

  node_count = var.node_count

  node_config {
    machine_type    = var.machine_type
    spot            = var.use_spot_nodes
    disk_size_gb    = 50
    disk_type       = "pd-standard"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      pool = "general"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
