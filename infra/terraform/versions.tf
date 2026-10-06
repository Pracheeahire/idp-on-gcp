terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Remote state in a GCS bucket. The bucket name is passed at init time:
  #   terraform init -backend-config="bucket=<your-state-bucket>"
  backend "gcs" {
    prefix = "idp-on-gcp/infra"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
