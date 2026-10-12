# Monitoring and alerting: Prometheus, Grafana, Alertmanager

```
sample-service pods ── /metrics ──┐
kube-state-metrics (pod status) ──┤ scraped every 15s
node-exporter, kubelet (CPU/mem) ─┤
                                  ▼
                            Prometheus ── evaluates PrometheusRule ──► Alertmanager ──► Slack #alerts
                                  │
                                  ▼
                               Grafana  (dashboard: golden signals + SLO)
```

| File | Owner | What it does |
| --- | --- | --- |
| `platform/observability/values.yaml` | Platform | Helm values for kube-prometheus-stack, sized for the lab |
| `platform/observability/dashboards/sample-service-dashboard.yaml` | Platform | Grafana dashboard, auto-loaded by the Grafana sidecar |
| `platform/observability/loadgen.yaml` | Lab | ~10 requests/second of background traffic |
| `platform/observability/alertmanager-slack.example.yaml` | Platform | Slack routing; copy to `.local.yaml` with your webhook |
| `apps/sample-service/deploy/monitoring/servicemonitor.yaml` | App team | Tells Prometheus to scrape the app |
| `apps/sample-service/deploy/monitoring/prometheusrule.yaml` | App team | The app's alert rules |
| `docs/slo.md` | App team | SLIs, SLOs, error budget, burn-rate alerting |

## Runbook

Run from `D:\DevTools\idp-on-gcp` in PowerShell.

### 1. Bring the platform up and deploy the app

```powershell
cd infra\terraform; terraform apply -auto-approve; cd ..\..
gcloud container clusters get-credentials idp-cluster --zone asia-south1-a --project prachiplatform-lab-2026
```

The registry is new and empty after a destroy, so let the pipeline rebuild and deploy: GitHub → **Actions** → **sample-service CI/CD** → **Run workflow** → `main`. Wait for it to go green, then:

```powershell
kubectl -n sample get pods
```

### 2. Install the monitoring stack (3-5 min)

```powershell
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace -f platform/observability/values.yaml --wait --timeout 10m
kubectl -n monitoring get pods
```

With Slack set up (section 6), add `-f platform/observability/alertmanager-slack.local.yaml` to the `helm` command.

### 3. Add the app's monitoring, the dashboard and background traffic

```powershell
kubectl apply -f apps/sample-service/deploy/monitoring/
kubectl apply -f platform/observability/dashboards/
kubectl apply -f platform/observability/loadgen.yaml
```

### 4. Open the three UIs

Each `port-forward` keeps running, so use a separate PowerShell window for each:

```powershell
kubectl -n monitoring port-forward svc/kps-prometheus 9090:9090
kubectl -n monitoring port-forward svc/grafana 3000:80
kubectl -n monitoring port-forward svc/kps-alertmanager 9093:9093
```

| UI | URL | Check |
| --- | --- | --- |
| Prometheus | http://localhost:9090 | **Status → Targets**: `serviceMonitor/sample/sample-service` shows 2/2 UP. **Alerts**: the 5 sample-service rules are listed |
| Grafana | http://localhost:3000 (admin / idp-lab-admin) | **Dashboards → sample-service: golden signals and SLO** |
| Alertmanager | http://localhost:9093 | Firing alerts appear here |

### 5. Drills: break it and watch the alerts

Get the app's IP first:

```powershell
$IP = kubectl -n sample get svc sample-service -o jsonpath="{.status.loadBalancer.ingress[0].ip}"
```

**a) Error spike → `SampleServiceHighErrorRate`** (4 minutes)

```powershell
$end = (Get-Date).AddMinutes(4); while ((Get-Date) -lt $end) { curl.exe -s -o NUL "http://$IP/simulate/error" }
```

Watch: the 500 line in Grafana; Prometheus **Alerts** goes Inactive → **Pending** → **Firing**; the alert appears in Alertmanager (and Slack). After the loop stops, it resolves.

**b) Slow responses → `SampleServiceHighLatencyP95`** (4 minutes, 4 parallel slow callers)

```powershell
1..4 | ForEach-Object { Start-Job -ArgumentList $IP -ScriptBlock { param($ip) $end = (Get-Date).AddMinutes(4); while ((Get-Date) -lt $end) { curl.exe -s -o NUL "http://$ip/simulate/slow?ms=2500" } } }
Get-Job | Wait-Job | Remove-Job
```

Watch p95/p99 climb in Grafana, and in-flight requests rise: slow calls tie up gunicorn's threads, which slows everyone else too.

**c) Crash loop → `SampleServicePodRestarting`** (Day 3, Break 2 again)

```powershell
kubectl -n sample set resources deployment/sample-service --requests=memory=16Mi --limits=memory=20Mi
```

Watch restarts climb in Grafana. Fix with `kubectl -n sample rollout undo deployment/sample-service`.

**d) Total outage → `SampleServiceDown`**

```powershell
kubectl -n sample scale deployment sample-service --replicas=0
```

Wait 2 minutes, watch the alert fire, then restore with `--replicas=2`.

### 6. Slack (optional, 10 min)

1. Create a free workspace at slack.com with a channel `#alerts`.
2. Go to api.slack.com/apps → **Create New App** → **From scratch** → pick your workspace.
3. **Incoming Webhooks** → switch **On** → **Add New Webhook to Workspace** → pick `#alerts` → copy the URL.
4. Create the local config (git-ignored) and paste the URL into it:
   ```powershell
   Copy-Item platform/observability/alertmanager-slack.example.yaml platform/observability/alertmanager-slack.local.yaml
   notepad platform/observability/alertmanager-slack.local.yaml
   ```
5. Re-run the `helm upgrade --install` command with `-f platform/observability/alertmanager-slack.local.yaml` added.

### 7. End of session

```powershell
kubectl delete namespace sample
cd infra\terraform; terraform destroy -auto-approve
```

The monitoring stack lives on the cluster, so destroying the cluster removes it too. No extra load balancers are created: the UIs are reached through `port-forward`.

## Interview talking points

- **Golden signals:** traffic, errors, latency, saturation. The dashboard has one row per signal, plus availability against the SLO.
- **Symptoms, not causes:** page on what users feel (errors, latency, availability); use CPU and memory for diagnosis, not for paging.
- **SLO-based alerting:** multi-window burn-rate alerts page only when the error budget is really at risk. See `docs/slo.md`.
- **`for:` duration:** the alert must stay true for a while before firing (Pending → Firing), which filters out brief blips.
- **Excluding probe traffic:** health checks are constant 200s and would dilute the real error rate.
- **Ownership:** the platform team runs the stack; app teams ship their own `ServiceMonitor` and `PrometheusRule` beside their code. That's why Prometheus selects them from every namespace.
- **Cardinality:** unknown URL paths are grouped into `other`, so a scanner can't create thousands of time series.
- **Histograms:** latency percentiles are calculated from histogram buckets with `histogram_quantile`; averages hide the slow tail.
- **Port-forward instead of public UIs:** monitoring UIs aren't exposed to the internet. In production they'd sit behind SSO, e.g. Identity-Aware Proxy.
