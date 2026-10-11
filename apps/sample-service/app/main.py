"""Sample service for the idp-on-gcp platform.

A small HTTP API that behaves like a real production service:
  /            hello message (text comes from a ConfigMap via APP_MESSAGE)
  /health      liveness probe: "is the process alive?"
  /ready       readiness probe: "can this pod take traffic right now?"
  /metrics     Prometheus metrics (request count, latency, in-flight requests)
  /api/items   a fake business endpoint with some realistic latency

Failure injection, used on Day 3 (troubleshooting) and Day 6 (alerts):
  /simulate/error          returns HTTP 500
  /simulate/slow?ms=1500   responds slowly
  /simulate/unready        flips readiness off, so Kubernetes stops sending traffic
  /simulate/ready          flips readiness back on
"""

import logging
import os
import random
import socket
import time

from flask import Flask, Response, g, jsonify, request
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)

APP_NAME = "sample-service"
VERSION = os.getenv("APP_VERSION", "dev")
MESSAGE = os.getenv("APP_MESSAGE", "Hello from the idp-on-gcp platform")

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format='{"time":"%(asctime)s","level":"%(levelname)s","msg":"%(message)s"}',
)
log = logging.getLogger(APP_NAME)

# --- Prometheus metrics: the four golden signals start here ---------------
REQUESTS = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "path", "status"],
)
LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "path"],
    buckets=(0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)
IN_FLIGHT = Gauge("http_requests_in_flight", "Requests currently being served")

# Paths we label individually; everything else is grouped to keep metric
# cardinality low (a classic Prometheus pitfall worth mentioning in interviews).
KNOWN_PATHS = {
    "/", "/health", "/ready", "/api/items",
    "/simulate/error", "/simulate/slow", "/simulate/unready", "/simulate/ready",
}
SKIP_METRICS = {"/metrics"}

app = Flask(__name__)
app.config["READY"] = True


def _path_label() -> str:
    return request.path if request.path in KNOWN_PATHS else "other"


@app.before_request
def _start_timer():
    if request.path in SKIP_METRICS:
        return
    g.start = time.perf_counter()
    IN_FLIGHT.inc()


@app.after_request
def _record_metrics(response):
    if request.path in SKIP_METRICS or "start" not in g:
        return response
    elapsed = time.perf_counter() - g.start
    path = _path_label()
    LATENCY.labels(request.method, path).observe(elapsed)
    REQUESTS.labels(request.method, path, str(response.status_code)).inc()
    IN_FLIGHT.dec()
    log.info("%s %s %s %.1fms", request.method, request.path, response.status_code, elapsed * 1000)
    return response


# --- Endpoints -------------------------------------------------------------
@app.get("/")
def index():
    return jsonify(
        service=APP_NAME,
        version=VERSION,
        message=MESSAGE,
        pod=socket.gethostname(),
    )


@app.get("/health")
def health():
    return jsonify(status="ok")

@app.get("/version")
def version():
    return jsonify(VERSION)


@app.get("/ready")
def ready():
    if app.config["READY"]:
        return jsonify(status="ready")
    return jsonify(status="not ready"), 503


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


@app.get("/api/items")
def items():
    time.sleep(random.uniform(0.01, 0.08))
    return jsonify(items=[{"id": i, "name": f"item-{i}"} for i in range(1, 6)])


@app.get("/simulate/error")
def simulate_error():
    log.error("simulated failure requested")
    return jsonify(error="simulated failure"), 500


@app.get("/simulate/slow")
def simulate_slow():
    ms = min(int(request.args.get("ms", 1500)), 10_000)
    time.sleep(ms / 1000)
    return jsonify(slept_ms=ms)


@app.get("/simulate/unready")
def simulate_unready():
    app.config["READY"] = False
    log.warning("readiness turned OFF")
    return jsonify(ready=False)


@app.get("/simulate/ready")
def simulate_ready():
    app.config["READY"] = True
    log.warning("readiness turned ON")
    return jsonify(ready=True)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8000")))
