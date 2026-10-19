import pytest
from fastapi import HTTPException
from app.main import _normalize_profile


def test_normalizes_documented_wrapped_response():
    profile = _normalize_profile({"success": True, "data": {"nickname": "ShadowHex", "level": 178, "rating": 6421, "customReadableMpRank": "Grand Master IV", "unexpected": "do-not-copy"}})
    assert profile["nickname"] == "ShadowHex"
    assert profile["level"] == 178
    assert profile["rating"] == 6421
    assert "unexpected" not in profile
    assert profile["data_source"] == "unofficial"


def test_missing_fields_are_not_fabricated():
    profile = _normalize_profile({"data": {"nickname": "Example"}})
    assert profile["nickname"] == "Example"
    assert "level" not in profile
    assert "rating" not in profile


def test_invalid_response_fails_closed():
    with pytest.raises(HTTPException) as exc:
        _normalize_profile({"message": "nothing useful"})
    assert exc.value.status_code == 502
