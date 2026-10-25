from concurrent.futures import ThreadPoolExecutor

import pytest
from conftest import PASSWORD, register
from sqlalchemy import select

from lango.db import Invite, Refresh, TalkSession, Ticket, User, now
from lango.security import create_invite, digest


def test_health_auth_and_secret_free_contract(env):
    assert env.client.get("/healthz").json() == {"status": "ok"}
    for path in ("me", "config", "scenarios", "sessions", "memories", "usage"):
        assert env.client.get("/api/v1/" + path).status_code == 401
    user = register(env)
    profile = env.client.get("/api/v1/me", headers=user.headers).json()
    assert profile["native_language"] == "zh"
    assert profile["target_language"] == "en"
    assert profile["level"] == "A2"
    assert profile["voice"] == "Kore"
    assert profile["memory_enabled"] is True
    assert profile["is_admin"] is False
    assert "password_hash" not in profile and "memory_epoch" not in profile
    config = env.client.get("/api/v1/config", headers=user.headers)
    assert {e["id"] for e in config.json()["engines"]} == {"cascade", "live"}
    assert config.json()["limits"] == {"daily_minutes": 60}
    assert "gemini" not in config.text.lower() and "api_key" not in config.text
    assert config.headers["cache-control"] == "no-store"
    scenarios = env.client.get("/api/v1/scenarios", headers=user.headers).json()
    assert len(scenarios) == len({s["id"] for s in scenarios}) == 12
    assert all(s["goals"] and s["opening_line"] and s["useful_phrases"] for s in scenarios)
    assert env.client.get("/api/v1/usage", headers=user.headers).json() == {
        "today_seconds": 0,
        "daily_limit_seconds": 3600,
        "sessions_count": 0,
    }
    with env.db() as db:
        row = db.get(User, user.id)
        assert row.password_hash.startswith("$argon2id$")
        assert row.password_hash != PASSWORD
        assert db.get(Refresh, digest(user.pair["refresh_token"])) is not None
        assert db.get(Refresh, user.pair["refresh_token"]) is None


def test_registration_requires_expiring_invitation(env):
    payload = {
        "email": "new@example.com",
        "password": PASSWORD,
        "display_name": "New",
        "invite_code": "invalid-invitation-123456",
    }
    assert env.client.post("/api/v1/auth/register", json=payload).status_code == 400
    with env.db.begin() as db:
        expired = create_invite(db)["code"]
        db.flush()
        db.get(Invite, digest(expired)).expires_at = now() - 1
        code = create_invite(db)["code"]
    payload["invite_code"] = expired
    assert env.client.post("/api/v1/auth/register", json=payload).status_code == 400
    payload["invite_code"] = code
    assert env.client.post("/api/v1/auth/register", json=payload).status_code == 200
    payload["email"] = "another@example.com"
    assert env.client.post("/api/v1/auth/register", json=payload).status_code == 400
    with env.db() as db:
        assert db.get(Invite, digest(code)).uses == 1


def test_duplicate_registration_rolls_back_invitation(env):
    register(env)
    with env.db.begin() as db:
        code = create_invite(db)["code"]
    response = env.client.post(
        "/api/v1/auth/register",
        json={
            "email": "LEARNER@example.com",
            "password": PASSWORD,
            "display_name": "Duplicate",
            "invite_code": code,
        },
    )
    assert response.status_code == 409
    with env.db() as db:
        assert db.get(Invite, digest(code)).uses == 0


def test_login_rotation_replay_and_logout(env):
    user = register(env)
    bad = env.client.post(
        "/api/v1/auth/login",
        json={
            "email": "learner@example.com",
            "password": "incorrect-password",
        },
    )
    assert bad.status_code == 401
    pair = env.client.post(
        "/api/v1/auth/login",
        json={
            "email": "LEARNER@example.com",
            "password": PASSWORD,
        },
    ).json()
    rotated = env.client.post("/api/v1/auth/refresh", json={"refresh_token": pair["refresh_token"]})
    assert rotated.status_code == 200
    new = rotated.json()
    assert new["refresh_token"] != pair["refresh_token"]
    headers = {"Authorization": "Bearer " + new["access_token"]}
    assert env.client.get("/api/v1/me", headers=headers).status_code == 200
    assert (
        env.client.post(
            "/api/v1/auth/refresh", json={"refresh_token": pair["refresh_token"]}
        ).status_code
        == 401
    )
    assert env.client.get("/api/v1/me", headers=headers).status_code == 401
    assert (
        env.client.post(
            "/api/v1/auth/refresh", json={"refresh_token": new["refresh_token"]}
        ).status_code
        == 401
    )
    assert env.client.get("/api/v1/me", headers=user.headers).status_code == 200
    assert env.client.post(
        "/api/v1/auth/logout",
        headers=user.headers,
        json={"refresh_token": user.pair["refresh_token"]},
    ).json() == {"ok": True}
    assert env.client.get("/api/v1/me", headers=user.headers).status_code == 401


def test_concurrent_refresh_replay_revokes_family(env):
    user = register(env)

    def refresh(_):
        return env.client.post(
            "/api/v1/auth/refresh", json={"refresh_token": user.pair["refresh_token"]}
        )

    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(refresh, range(2)))
    assert sorted(r.status_code for r in results) == [200, 401]
    issued = next(r.json() for r in results if r.status_code == 200)
    assert (
        env.client.get(
            "/api/v1/me",
            headers={
                "Authorization": "Bearer " + issued["access_token"],
            },
        ).status_code
        == 401
    )


@pytest.mark.parametrize(
    "patch",
    [
        {"is_admin": True},
        {"voice": "invalid"},
        {"level": "X"},
        {"speech_rate": 2},
        {"display_name": None},
        {"goal": "x" * 1001},
    ],
)
def test_profile_bounds(env, patch):
    user = register(env)
    assert env.client.patch("/api/v1/me", headers=user.headers, json=patch).status_code == 422


def test_profile_update_and_admin_invites(env):
    user = register(env)
    patch = {
        "display_name": "Lin",
        "level": "B2",
        "goal": "Work",
        "interests": "Hiking",
        "voice": "Puck",
        "speech_rate": 0.8,
        "onboarding_completed": True,
    }
    response = env.client.patch("/api/v1/me", headers=user.headers, json=patch)
    assert response.status_code == 200
    assert all(response.json()[key] == value for key, value in patch.items())
    assert (
        env.client.post(
            "/api/v1/admin/invites", headers=user.headers, json={"max_uses": 1}
        ).status_code
        == 403
    )
    with env.db.begin() as db:
        db.get(User, user.id).is_admin = True
    invite = env.client.post("/api/v1/admin/invites", headers=user.headers, json={"max_uses": 2})
    assert invite.status_code == 200
    assert invite.json()["uses"] == 0 and invite.json()["max_uses"] == 2
    assert (
        env.client.post(
            "/api/v1/admin/invites", headers=user.headers, json={"max_uses": 0}
        ).status_code
        == 422
    )


def test_history_ownership_and_limit(env):
    one, two = register(env), register(env, "two@example.com")
    with env.db.begin() as db:
        rows = [
            TalkSession(user_id=one.id, title=str(i), engine="cascade", started_at=now() + i)
            for i in range(105)
        ]
        db.add_all(rows)
        db.flush()
        session_id = rows[0].id
    history = env.client.get("/api/v1/sessions", headers=one.headers).json()
    assert len(history) == 100 and history[0]["title"] == "104"
    assert env.client.get("/api/v1/sessions", headers=two.headers).json() == []
    assert env.client.get("/api/v1/sessions/" + session_id, headers=two.headers).status_code == 404
    assert (
        env.client.get("/api/v1/sessions/" + session_id, headers=one.headers).json()["turns"] == []
    )


def test_rest_bounds_cors_and_auth_rate(env):
    response = env.client.post("/api/v1/auth/login", content=b"x" * 32769)
    assert response.status_code == 413
    response = env.client.post("/api/v1/auth/login", json={"password": "private-password-value"})
    assert response.status_code == 422 and "private-password" not in response.text
    response = env.client.options(
        "/api/v1/me",
        headers={
            "Origin": "https://app.example.com",
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "Authorization",
        },
    )
    assert response.headers["access-control-allow-origin"] == "https://app.example.com"
    denied = env.client.options(
        "/api/v1/me",
        headers={
            "Origin": "https://evil.example.com",
            "Access-Control-Request-Method": "GET",
        },
    )
    assert "access-control-allow-origin" not in denied.headers
    for _ in range(21):
        result = env.client.post("/api/v1/auth/refresh", json={"refresh_token": "x" * 24})
    assert result.status_code == 429


def test_ticket_stored_only_as_hash(env):
    user = register(env)
    response = env.client.post("/api/v1/talk/ticket", headers=user.headers).json()
    assert response["expires_in"] == 30
    with env.db() as db:
        ticket = db.scalar(select(Ticket))
        assert ticket.digest == digest(response["ticket"])
        assert ticket.user_id == user.id and not ticket.used
