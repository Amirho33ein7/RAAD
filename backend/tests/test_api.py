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
