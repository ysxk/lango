from starlette.testclient import TestClient
from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware

REFRESH_PAYLOAD = {"refresh_token": "a" * 32}


def test_trusted_proxy_forwarded_clients_independent_rate_limit(env):
    wrapped_app = ProxyHeadersMiddleware(env.app, trusted_hosts=["127.0.0.1", "172.28.0.10"])
    proxy_client = TestClient(wrapped_app, client=("172.28.0.10", 45678))

    # Client A (203.0.113.1) sends 20 requests to consume auth rate limit (20 req / 60s per IP)
    for _ in range(20):
        resp = proxy_client.post(
            "/api/v1/auth/refresh",
            json=REFRESH_PAYLOAD,
            headers={"x-forwarded-for": "203.0.113.1"},
        )
        assert resp.status_code == 401

    # Client A's 21st request hits 429 rate limit
    resp_blocked = proxy_client.post(
        "/api/v1/auth/refresh",
        json=REFRESH_PAYLOAD,
        headers={"x-forwarded-for": "203.0.113.1"},
    )
    assert resp_blocked.status_code == 429
    assert resp_blocked.json()["detail"] == "Too many requests; try again later"

    # Client B (203.0.113.2) through the same proxy has an independent rate limit
    resp_client_b = proxy_client.post(
        "/api/v1/auth/refresh",
        json=REFRESH_PAYLOAD,
        headers={"x-forwarded-for": "203.0.113.2"},
    )
    assert resp_client_b.status_code == 401


def test_untrusted_source_xff_ignored_and_rate_limited_on_peer(env):
    wrapped_app = ProxyHeadersMiddleware(env.app, trusted_hosts=["127.0.0.1", "172.28.0.10"])
    untrusted_client = TestClient(wrapped_app, client=("198.51.100.50", 54321))

    # Untrusted attacker tries to spoof different X-Forwarded-For headers
    for i in range(20):
        resp = untrusted_client.post(
            "/api/v1/auth/refresh",
            json=REFRESH_PAYLOAD,
            headers={"x-forwarded-for": f"10.0.0.{i}"},
        )
        assert resp.status_code == 401

    # Attacker's 21st request is blocked because rate limit is tracked on real peer IP (198.51.100.50)
    resp_blocked = untrusted_client.post(
        "/api/v1/auth/refresh",
        json=REFRESH_PAYLOAD,
        headers={"x-forwarded-for": "10.0.0.99"},
    )
    assert resp_blocked.status_code == 429
    assert resp_blocked.json()["detail"] == "Too many requests; try again later"


def test_trusted_proxy_multi_hop_xff(env):
    wrapped_app = ProxyHeadersMiddleware(env.app, trusted_hosts=["127.0.0.1", "172.28.0.10"])
    proxy_client = TestClient(wrapped_app, client=("172.28.0.10", 45678))

    # Multi-hop XFF: client, proxy
    for _ in range(20):
        resp = proxy_client.post(
            "/api/v1/auth/refresh",
            json=REFRESH_PAYLOAD,
            headers={"x-forwarded-for": "198.51.100.77, 172.28.0.10"},
        )
        assert resp.status_code == 401

    resp_blocked = proxy_client.post(
        "/api/v1/auth/refresh",
        json=REFRESH_PAYLOAD,
        headers={"x-forwarded-for": "198.51.100.77, 172.28.0.10"},
    )
    assert resp_blocked.status_code == 429


def test_direct_loopback_connection_trusted_by_default(env):
    wrapped_app = ProxyHeadersMiddleware(env.app, trusted_hosts=["127.0.0.1", "::1"])
    loopback_client = TestClient(wrapped_app, client=("127.0.0.1", 12345))

    for _ in range(20):
        resp = loopback_client.post(
            "/api/v1/auth/refresh",
            json=REFRESH_PAYLOAD,
            headers={"x-forwarded-for": "192.168.1.100"},
        )
        assert resp.status_code == 401

    resp_blocked = loopback_client.post(
        "/api/v1/auth/refresh",
        json=REFRESH_PAYLOAD,
        headers={"x-forwarded-for": "192.168.1.100"},
    )
    assert resp_blocked.status_code == 429


def test_trusted_proxy_http_rate_limit_uses_forwarded_client(env, monkeypatch):
    monkeypatch.setattr("lango.security.now", lambda: 1800000000)
    app = ProxyHeadersMiddleware(env.app, trusted_hosts=["172.28.0.10"])
    with TestClient(app, client=("172.28.0.10", 45678)) as client:
        for _ in range(300):
            response = client.get("/missing", headers={"x-forwarded-for": "203.0.113.10"})
            assert response.status_code == 404
        assert (
            client.get("/missing", headers={"x-forwarded-for": "203.0.113.10"}).status_code == 429
        )
        assert (
            client.get("/missing", headers={"x-forwarded-for": "203.0.113.11"}).status_code == 404
        )
