# Small, non-root production image for the sample service.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8000

WORKDIR /app

# Install dependencies first so this layer is cached between code changes.
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app/ ./app/

# Run as an unprivileged user (UID 10001), never as root.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
USER 10001

EXPOSE 8000

# gunicorn: one process with 4 threads. A single process keeps Prometheus
# metrics consistent (each process would otherwise keep its own counters);
# Kubernetes scales by adding pods, not processes.
# Graceful shutdown when Kubernetes sends SIGTERM.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "1", "--threads", "4", "--graceful-timeout", "20", "app.main:app"]
