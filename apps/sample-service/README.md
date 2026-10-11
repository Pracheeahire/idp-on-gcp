# sample-service

A small Flask API that behaves like a production service: health and readiness probes, Prometheus metrics, structured logs, config from a ConfigMap, and failure-injection endpoints for troubleshooting and alerting practice.

| Endpoint | Purpose |
| --- | --- |
| `/` | Service info, including which pod answered |
| `/health` | Liveness probe |
| `/ready` | Readiness probe (returns 503 when switched off) |
| `/metrics` | Prometheus metrics: request count, latency histogram, in-flight requests |
| `/api/items` | Fake business endpoint with realistic latency |
| `/simulate/error` | Returns HTTP 500 |
| `/simulate/slow?ms=1500` | Slow response |
| `/simulate/unready` and `/simulate/ready` | Switch readiness off and on |

## Day 2 runbook

Run from the repo root (`D:\DevTools\idp-on-gcp`) in PowerShell. The cluster from Day 1 must be running.

### 1. Build the image in Google Cloud (no local Docker needed)

```powershell
gcloud services enable cloudbuild.googleapis.com
gcloud builds submit apps/sample-service --tag asia-south1-docker.pkg.dev/prachiplatform-lab-2026/apps/sample-service:v1
```

Cloud Build uploads the folder, runs the Dockerfile on Google's machines and pushes the image to Artifact Registry. It takes 2-3 minutes. Check the image is there:

```powershell
gcloud artifacts docker images list asia-south1-docker.pkg.dev/prachiplatform-lab-2026/apps
```

### 2. Deploy to GKE

```powershell
kubectl apply -f apps/sample-service/deploy/k8s/namespace.yaml
kubectl apply -f apps/sample-service/deploy/k8s/
kubectl -n sample get pods -w
```

Wait until both pods show `1/1 Running`, then press Ctrl+C.

### 3. Get the public IP and call the app

```powershell
kubectl -n sample get service sample-service -w
```

`EXTERNAL-IP` shows `<pending>` for 1-2 minutes. When an IP appears, press Ctrl+C and open these in your browser (replace the IP):

- `http://EXTERNAL-IP/`
- `http://EXTERNAL-IP/api/items`
- `http://EXTERNAL-IP/metrics`

Refresh `/` a few times: the `pod` field changes, because the Service load-balances across both pods.

### 4. Explore

```powershell
kubectl -n sample get all
kubectl -n sample describe deployment sample-service
kubectl -n sample logs deploy/sample-service
kubectl -n sample get endpoints sample-service
```

### 5. Watch readiness in action

```powershell
curl.exe http://EXTERNAL-IP/simulate/unready
kubectl -n sample get pods
kubectl -n sample get endpoints sample-service
```

One pod drops to `0/1` ready and its IP disappears from the endpoints list: Kubernetes stops sending it traffic, but does **not** restart it. That's the difference between readiness and liveness. Turn it back on by calling `/simulate/ready` until both pods are `1/1` again (the load balancer picks a pod at random, so it may take a few calls), or just delete the pod:

```powershell
kubectl -n sample delete pod <the-0/1-pod-name>
```

The Deployment creates a replacement straight away.

## If the build fails with a permission error

Newer projects run Cloud Build as the Compute Engine default service account. Give it the roles it needs, then rerun the build:

```powershell
$PN = gcloud projects describe prachiplatform-lab-2026 --format="value(projectNumber)"
$SA = "$PN-compute@developer.gserviceaccount.com"
foreach ($r in "roles/artifactregistry.writer","roles/logging.logWriter","roles/storage.objectViewer") {
  gcloud projects add-iam-policy-binding prachiplatform-lab-2026 --member="serviceAccount:$SA" --role=$r --condition=None
}
```

## Interview talking points

- **Startup vs liveness vs readiness probes.** Startup protects slow boots; liveness restarts a hung container; readiness removes a pod from the Service without restarting it.
- **Requests vs limits.** Requests are what the scheduler reserves; limits are the ceiling. Going over the memory limit gets the container OOMKilled; going over the CPU limit only throttles it.
- **`maxUnavailable: 0, maxSurge: 1`.** Zero-downtime rollouts: a new pod must be ready before an old one is removed.
- **Container hardening.** Non-root user, read-only root filesystem, all Linux capabilities dropped, no privilege escalation.
- **Why one gunicorn process with threads?** Each process would keep its own Prometheus counters, so scrapes would jump between values. Kubernetes scales by adding pods.
- **Metric cardinality.** Unknown paths are grouped as `other`, so a scanner hitting random URLs can't create thousands of time series.
- **Cloud Build instead of local Docker.** Builds run on Google's machines, close to the registry; this is the same step a CI pipeline will run on Day 4.
