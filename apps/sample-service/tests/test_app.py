from app.main import app


def client():
    app.config["READY"] = True
    return app.test_client()


def test_index_returns_service_info():
    resp = client().get("/")
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["service"] == "sample-service"
    assert "message" in body


def test_health_is_ok():
    assert client().get("/health").status_code == 200


def test_readiness_can_be_toggled():
    c = client()
    assert c.get("/ready").status_code == 200
    c.get("/simulate/unready")
    assert c.get("/ready").status_code == 503
    c.get("/simulate/ready")
    assert c.get("/ready").status_code == 200


def test_items_endpoint():
    resp = client().get("/api/items")
    assert resp.status_code == 200
    assert len(resp.get_json()["items"]) == 5


def test_simulated_error_returns_500():
    assert client().get("/simulate/error").status_code == 500


def test_metrics_are_exposed_and_count_requests():
    c = client()
    c.get("/api/items")
    text = c.get("/metrics").get_data(as_text=True)
    assert "http_requests_total" in text
    assert 'path="/api/items"' in text
    assert "http_request_duration_seconds_bucket" in text


def test_unknown_paths_are_grouped_to_limit_cardinality():
    c = client()
    c.get("/does-not-exist-12345")
    text = c.get("/metrics").get_data(as_text=True)
    assert "does-not-exist-12345" not in text
    assert 'path="other"' in text
