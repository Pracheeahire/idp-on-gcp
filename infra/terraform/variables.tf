variable "project_id" {
  description = "GCP project ID to deploy into."
  type        = string
}

variable "region" {
  description = "GCP region for the network and Artifact Registry."
  type        = string
  default     = "asia-south1"
}

variable "zone" {
  description = "Zone for the (zonal) GKE cluster. Zonal keeps the control plane free-tier eligible."
  type        = string
  default     = "asia-south1-a"
}

variable "cluster_name" {
  description = "Name of the GKE cluster."
  type        = string
  default     = "idp-cluster"
}

variable "node_count" {
  description = "Number of nodes in the default node pool."
  type        = number
  default     = 2
}

variable "machine_type" {
  description = "Node machine type. e2-standard-2 is enough for the app plus kube-prometheus-stack."
  type        = string
  default     = "e2-standard-2"
}

variable "use_spot_nodes" {
  description = "Use Spot VMs for nodes (much cheaper; nodes can be reclaimed). Good for a lab."
  type        = bool
  default     = true
}
