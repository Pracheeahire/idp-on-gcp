# CI/CD: GitHub Actions → Artifact Registry → GKE

Every push to `main` that touches the app is tested, built into an image tagged with the commit SHA, pushed to Artifact Registry and deployed to GKE. If the rollout fails, the pipeline rolls back automatically. No GCP keys are stored anywhere.

```
git push (main)
   │
   ▼
[test]  pytest ───────────────── fails? stop here; nothing is built
   │
   ▼
[build] GitHub OIDC token ──► Workload Identity Federation ──► acts as github-deployer SA
        docker build → push  asia-south1-docker.pkg.dev/<project>/apps/sample-service:<sha>
   │
   ▼
[deploy] get GKE credentials → set image to <sha> → kubectl apply
         rollout status (180s) ── fails? → kubectl rollout undo
```

Pull requests run only the `test` job.

## What you set up once

| Piece | Where | Why |
| --- | --- | --- |
| Workload Identity pool + provider | `infra/github-oidc` | Lets GCP trust GitHub's short-lived OIDC tokens, but only from this repo's `main` branch |
| `github-deployer` service account | `infra/github-oidc` | What the pipeline acts as. Only `artifactregistry.writer` and `container.developer` |
| Repo variables | GitHub → Settings → Secrets and variables → Actions → **Variables** | `GCP_PROJECT_ID`, `GCP_WIF_PROVIDER`, `GCP_DEPLOYER_SA`. These are identifiers, not secrets |

`infra/github-oidc` has its own Terraform state and is **never destroyed**. It costs nothing, and GCP soft-deletes identity pools for 30 days, so a destroyed pool ID can't be recreated straight away.

## Runbook (CI/CD day)

### 1. One-time: create the keyless identity

```powershell
cd D:\DevTools\idp-on-gcp\infra\github-oidc
Copy-Item terraform.tfvars.example terraform.tfvars
terraform init -backend-config="bucket=igp-gcp"
terraform apply
```

Copy the two outputs.

### 2. One-time: add three repo variables on GitHub

Repo → **Settings → Secrets and variables → Actions → Variables tab → New repository variable**:

| Name | Value |
| --- | --- |
| `GCP_PROJECT_ID` | `prachee-idp-lab` |
| `GCP_WIF_PROVIDER` | the `workload_identity_provider` output (starts with `projects/`) |
| `GCP_DEPLOYER_SA` | the `deployer_service_account` output |

### 3. Each session: bring the platform up

```powershell
cd D:\DevTools\idp-on-gcp\infra\terraform
terraform apply
```

The pipeline needs the cluster and registry to exist. If they don't, the build job stops with a clear message.

### 4. Trigger a deploy

Change the message in `apps/sample-service/deploy/k8s/configmap.yaml` or any code, then:

```powershell
git add .
git commit -m "Change app message"
git push
```

Watch it on GitHub → **Actions**. The run summary shows the app's URL.

### 5. Break it on purpose

- **Failing test:** change an assert in `tests/test_app.py` and push. The pipeline stops at `test`, and nothing is deployed.
- **Bad rollout:** change the readiness probe path in `deployment.yaml` to `/nope` and push. The rollout times out, and the pipeline rolls back to the previous version.

Then fix both and push again.

### 6. End of session

```powershell
kubectl delete namespace sample
cd D:\DevTools\idp-on-gcp\infra\terraform
terraform destroy
```

## Interview talking points

- **Keyless auth (Workload Identity Federation).** GitHub issues a short-lived OIDC token per run; GCP exchanges it for temporary credentials. There's no JSON key to leak or rotate. The provider only accepts tokens from this repo's `main` branch.
- **Least privilege.** The deployer can push images and deploy to GKE, nothing else.
- **Immutable tags.** Images are tagged with the commit SHA, never `latest`, so every running pod maps to an exact commit and rollbacks are precise.
- **Quality gate.** Tests run first; a failing test blocks build and deploy. Pull requests get tests only.
- **Safe rollout.** `maxUnavailable: 0` plus readiness probes mean traffic only moves to healthy pods. If the rollout doesn't finish in 180s, the pipeline runs `kubectl rollout undo`.
- **Separate state for separate lifecycles.** Long-lived identity setup and short-lived lab infrastructure live in different Terraform roots.
- **What I'd add in production:** a staging environment with a manual approval before prod, image vulnerability scanning, and GitOps (e.g. Argo CD) so the cluster pulls changes instead of CI pushing them.
