# idp-on-gcp

A production-style application platform on Google Cloud, built step by step:

1. **Infrastructure as code:** Terraform provisions a VPC, a GKE cluster and Artifact Registry, with remote state in GCS.
2. **CI/CD:** GitHub Actions tests, builds and pushes a container image, then deploys it to GKE.
3. **Observability:** Prometheus, Grafana and Alertmanager, with dashboards for the golden signals and alerts to Slack.

## Repository layout

```
infra/terraform/          GCP network, GKE cluster, Artifact Registry
apps/sample-service/      Python API with /health and /metrics, Dockerfile, Kubernetes manifests
platform/observability/   kube-prometheus-stack values, dashboards, alert rules
.github/workflows/        CI/CD pipeline
docs/                     Learning log, troubleshooting notes, SLO, postmortem
```

## Status

- [ ] Day 1: Terraform → GKE cluster
- [ ] Day 2: App deployed to GKE
- [ ] Day 3: Break and fix (troubleshooting guide)
- [ ] Day 4: CI/CD pipeline
- [ ] Day 5: Prometheus and Grafana
- [ ] Day 6: Alertmanager → Slack, SLO
- [ ] Day 7: Docs, diagram, postmortem
