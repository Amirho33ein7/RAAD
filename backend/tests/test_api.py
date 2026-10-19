import httpx
from fastapi.testclient import TestClient

from app import main as api


def _mock_provider(monkeypatch, status_code=200, payload=None):
    api._cache.clear()
    real_async_client = httpx.AsyncClient

    def handler(request):
        return httpx.Response(
            status_code,
            json=payload if payload is not None else {"success": True, "data": {"nickname": "TestPlayer", "level": 99}},
            request=request,
        )

    def client_factory(*args, **kwargs):
        kwargs["transport"] = httpx.MockTransport(handler)
        return real_async_client(*args, **kwargs)

    monkeypatch.setattr(api.httpx, "AsyncClient", client_factory)


def test_health_endpoint_is_local_and_simple():
    response = TestClient(api.app).get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_capabilities_are_honest_about_missing_stats():
    response = TestClient(api.app).get("/api/v1/capabilities")
    assert response.status_code == 200
    result = response.json()
    assert result["profile_lookup"] is True
    assert result["automatic_match_history"] is False
    assert result["kills_deaths_wins"] is False


def test_profile_endpoint_normalizes_only_returned_fields(monkeypatch):
    _mock_provider(
        monkeypatch,
        payload={
            "success": True,
            "data": {
                "nickname": "TestPlayer",
                "level": 99,
                "rating": 1234,
                "unlistedField": "must not leak through",
            },
        },
    )
    response = TestClient(api.app).get("/api/v1/codm/profile?q=TestPlayer")
    assert response.status_code == 200
    profile = response.json()
    assert profile["nickname"] == "TestPlayer"
    assert profile["level"] == 99
    assert profile["rating"] == 1234
    assert "unlistedField" not in profile
    assert profile["data_source"] == "unofficial"


def test_profile_endpoint_handles_missing_profile(monkeypatch):
    _mock_provider(monkeypatch, status_code=404, payload={"message": "not found"})
    response = TestClient(api.app).get("/api/v1/codm/profile?q=MissingPlayer")
    assert response.status_code == 404



def test_profile_endpoint_rejects_blank_query_before_provider_call():
    response = TestClient(api.app).get("/api/v1/codm/profile?q=%20%20")
    assert response.status_code == 400


def test_profile_endpoint_maps_rate_limit(monkeypatch):
    _mock_provider(monkeypatch, status_code=429, payload={"message": "rate limited"})
    response = TestClient(api.app).get("/api/v1/codm/profile?q=LimitedPlayer")
    assert response.status_code == 429


def test_profile_endpoint_maps_provider_5xx_to_bad_gateway(monkeypatch):
    _mock_provider(monkeypatch, status_code=503, payload={"message": "upstream outage"})
    response = TestClient(api.app).get("/api/v1/codm/profile?q=OutagePlayer")
    assert response.status_code == 502


def test_profile_endpoint_rejects_unexpected_redirect(monkeypatch):
    _mock_provider(monkeypatch, status_code=302, payload={"nickname": "DoNotTrustRedirect"})
    response = TestClient(api.app).get("/api/v1/codm/profile?q=RedirectPlayer")
    assert response.status_code == 502


def test_profile_cache_reuses_fresh_response(monkeypatch):
    api._cache.clear()
    real_async_client = httpx.AsyncClient
    calls = {"count": 0}

    def handler(request):
        calls["count"] += 1
        return httpx.Response(
            200,
            json={"success": True, "data": {"nickname": "CachePlayer", "level": 42}},
            request=request,
        )

    def client_factory(*args, **kwargs):
        kwargs["transport"] = httpx.MockTransport(handler)
        return real_async_client(*args, **kwargs)

    monkeypatch.setattr(api.httpx, "AsyncClient", client_factory)
    client = TestClient(api.app)

    first = client.get("/api/v1/codm/profile?q=CachePlayer")
    second = client.get("/api/v1/codm/profile?q=cacheplayer")

    assert first.status_code == 200
    assert first.json()["cache"] == "miss"
    assert second.status_code == 200
    assert second.json()["cache"] == "hit"
    assert second.json()["nickname"] == "CachePlayer"
    assert calls["count"] == 1


def test_provider_invalid_json_returns_502(monkeypatch):
    api._cache.clear()
    real_async_client = httpx.AsyncClient

    def handler(request):
        return httpx.Response(200, text="not-json", request=request)

    def client_factory(*args, **kwargs):
        kwargs["transport"] = httpx.MockTransport(handler)
        return real_async_client(*args, **kwargs)

    monkeypatch.setattr(api.httpx, "AsyncClient", client_factory)
    response = TestClient(api.app).get("/api/v1/codm/profile?q=MalformedPlayer")
    assert response.status_code == 502
    assert "JSON" in response.json()["detail"]


def test_provider_timeout_returns_504(monkeypatch):
    api._cache.clear()

    class TimeoutClient:
        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, traceback):
            return False

        async def get(self, url, headers=None):
            request = httpx.Request("GET", url)
            raise httpx.ReadTimeout("simulated timeout", request=request)

    monkeypatch.setattr(api.httpx, "AsyncClient", lambda *args, **kwargs: TimeoutClient())
    response = TestClient(api.app).get("/api/v1/codm/profile?q=TimeoutPlayer")
    assert response.status_code == 504
