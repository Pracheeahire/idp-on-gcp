# sample-service SLOs

## Service level indicators (SLIs)

| SLI | Definition | Source |
| --- | --- | --- |
| Availability | Share of requests that don't return 5xx | `http_requests_total` by `status` |
| Latency | Share of requests served in under 1 second | `http_request_duration_seconds` histogram |

Probe traffic (`/health`, `/ready`) is **excluded**. Kubernetes calls those every few seconds and they almost always return 200, so including them would hide real user-facing errors.

## Objectives (SLOs), over a rolling 30 days

| SLO | Target | Error budget |
| --- | --- | --- |
| Availability | 99.5% | 0.5% of requests may fail |
| Latency | 95% of requests < 1s | 5% may be slower |

**What 0.5% means:** 30 days is 43,200 minutes, so 0.5% is about **216 minutes (3.6 hours)** of complete outage per month. At 1 million requests a month, it's 5,000 failed requests.

## Alerting on the error budget

Alerting on every error spike pages people for noise. Alerting when the **error budget burns too fast** pages only when users are really affected.

**Burn rate** = how fast the budget is being used, compared with the allowed pace. Burn rate 1 uses exactly the whole budget in 30 days.

| Alert | Condition | Meaning |
| --- | --- | --- |
| `SampleServiceErrorBudgetFastBurn` | Error ratio > 14.4 × 0.5% over **1h and 5m** | 2% of the month's budget gone in 1 hour; budget empty in ~2 days |

The long window (1h) proves the problem is real; the short window (5m) proves it's still happening, so the alert also clears quickly after a fix. This multi-window, multi-burn-rate approach comes from the Google SRE Workbook.

The simpler `SampleServiceHighErrorRate` (> 5% for 1 minute) is there for fast feedback in the lab.

## Error budget policy

- **Budget left:** ship features normally.
- **Budget spent:** freeze risky releases; reliability work comes first until the budget recovers.
- **One incident uses more than 20% of the budget:** write a blameless postmortem.
