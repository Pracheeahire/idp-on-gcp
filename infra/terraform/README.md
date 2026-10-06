# Infrastructure (Terraform)

Creates the platform's base layer on GCP:

| File | What it creates |
| --- | --- |
| `apis.tf` | Turns on the GCP APIs the platform needs (Compute, GKE, Artifact Registry, IAM) |
| `network.tf` | A custom VPC and subnet, with secondary ranges for pods and services (VPC-native cluster) |
| `gke.tf` | A zonal GKE cluster with Workload Identity, plus a separate Spot node pool running as a least-privilege service account |
| `registry.tf` | An Artifact Registry Docker repo, with a cleanup policy for untagged images |
| `outputs.tf` | Cluster name, registry URL and the `get-credentials` command |
| `versions.tf` | Provider versions and remote state in a GCS bucket |

## Run it (Day 1)

From this folder, in PowerShell:

```powershell
# 1. One-time: your settings
Copy-Item terraform.tfvars.example terraform.tfvars

# 2. Connect to the remote state bucket
terraform init -backend-config="bucket=prachee-idp-lab-tfstate"

# 3. Check formatting and syntax
terraform fmt
terraform validate

# 4. Preview what will be created (read this output carefully)
terraform plan

# 5. Create it (about 10-15 minutes; GKE is the slow part)
terraform apply

# 6. Point kubectl at the cluster and check the nodes
gcloud container clusters get-credentials idp-cluster --zone asia-south1-a --project prachee-idp-lab
kubectl get nodes
```

**Done when:** `kubectl get nodes` shows 2 nodes in `Ready` state.

## Before you sleep: destroy it

```powershell
terraform destroy
```

The state bucket is not managed here, so it survives a destroy. Tomorrow, `terraform apply` rebuilds everything from zero.

## Interview talking points

- **Why remote state in GCS?** Shared, durable, versioned state. GCS backend also locks state during writes, so two `apply` runs can't corrupt it.
- **Why `remove_default_node_pool`?** The default pool can't be changed without recreating the cluster. A separate node pool resource can be resized or replaced on its own.
- **Why a custom node service account?** The default compute service account has the broad Editor role. Nodes only need to write logs and metrics and pull images.
- **Why VPC-native (secondary ranges)?** Pods get real VPC IPs, which is required for features like network policy and is GKE's recommended mode.
- **Why Workload Identity?** Pods get GCP permissions through a Kubernetes service account instead of downloaded JSON keys.
- **Why Spot nodes and a zonal cluster?** Cost. Spot VMs are much cheaper, and one zonal cluster's management fee is covered by GKE's free tier. In production you'd use a regional cluster and on-demand nodes for the critical pools.
