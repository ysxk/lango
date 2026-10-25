import importlib
import logging
import sys

import pytest
from conftest import PASSWORD
from pydantic import ValidationError
from sqlalchemy import inspect, select

from lango import cli
from lango.config import Settings
from lango.db import Base, Invite, User, make_database
from lango.logging import PrivacyFilter
from lango.migrate import check_schema, upgrade


def test_migrations_are_explicit_idempotent_and_match_models(tmp_path):
    settings = Settings(
        jwt_secret="test-only-" + "s" * 40,
        database_url=f"sqlite:///{tmp_path / 'db.sqlite'}",
        memory_path=str(tmp_path / "memory"),
        google_api_key=None,
    )
    engine, _ = make_database(settings)
    try:
        with pytest.raises(RuntimeError, match="lango.migrate"):
            check_schema(engine)
        upgrade(engine)
        upgrade(engine)
        check_schema(engine)
        schema = inspect(engine)
        assert set(Base.metadata.tables) <= set(schema.get_table_names())
        for name, table in Base.metadata.tables.items():
            assert set(table.columns.keys()) == {c["name"] for c in schema.get_columns(name)}
    finally:
        engine.dispose()


@pytest.mark.parametrize(
    "changes",
    [
        {"jwt_secret": "too-short"},
        {"daily_minutes": 0},
        {"daily_minutes": 1441},
        {"access_minutes": 61},
        {"refresh_days": 91},
        {"allowed_origins": ["*"]},
        {"provider_timeout_seconds": 1},
        {"worker_lease_seconds": 100},
        {"environment": "production"},
        {
            "environment": "production",
            "database_url": "postgresql+psycopg://localhost/lango",
            "allowed_origins": ["http://app.example.com"],
        },
        {
            "environment": "production",
            "database_url": "postgresql+psycopg://localhost/lango",
            "allowed_origins": ["https://app.example.com"],
            "memory_postgres_url": None,
        },
    ],
)
def test_invalid_config_rejected_without_echoing_secrets(changes):
    with pytest.raises(ValidationError) as error:
        Settings(**{"jwt_secret": "test-only-" + "s" * 40, **changes})
    assert "test-only-" not in str(error.value)


def test_production_pgvector_config_and_model_defaults():
    settings = Settings(
        jwt_secret="test-only-" + "s" * 40,
        environment="production",
        database_url="postgresql+psycopg://localhost/lango",
        memory_postgres_url="postgresql://localhost/lango",
        allowed_origins=["https://app.example.com"],
        google_api_key=None,
    )
    assert settings.text_model == "gemini-3.8-flash"
    assert settings.tts_model == "gemini-3.8-flash-lite-tts"
    assert settings.live_model == "gemini-3.8-live"


def test_cli_password_prompt_admin_and_invitation(env, monkeypatch, capsys):
    monkeypatch.setattr(cli, "Settings", lambda: env.settings)
    monkeypatch.setattr(cli, "make_database", lambda _: (env.engine, env.db))
    prompts = []

    def password(prompt):
        prompts.append(prompt)
        return PASSWORD

    monkeypatch.setattr(cli.getpass, "getpass", password)
    monkeypatch.setattr(
        sys,
        "argv",
        ["lango", "create-admin", "--email", "admin@example.com", "--display-name", "Admin"],
    )
    cli.main()
    assert prompts == ["Password: ", "Confirm password: "]
    assert "Administrator created" in capsys.readouterr().out
    with env.db() as db:
        admin = db.scalar(select(User).where(User.email == "admin@example.com"))
        assert admin.is_admin and admin.password_hash.startswith("$argon2id$")
    monkeypatch.setattr(
        sys, "argv", ["lango", "invite", "--email", "admin@example.com", "--hours", "1"]
    )
    cli.main()
    output = capsys.readouterr().out
    assert '"code"' in output and PASSWORD not in output
    with env.db() as db:
        assert db.scalar(select(Invite)).max_uses == 1


def test_cli_rejects_mismatched_passwords(env, monkeypatch):
    monkeypatch.setattr(cli, "Settings", lambda: env.settings)
    monkeypatch.setattr(cli, "make_database", lambda _: (env.engine, env.db))
    values = iter([PASSWORD, "not-the-same"])
    monkeypatch.setattr(cli.getpass, "getpass", lambda _: next(values))
    monkeypatch.setattr(
        sys,
        "argv",
        ["lango", "create-admin", "--email", "admin@example.com", "--display-name", "Admin"],
    )
    with pytest.raises(SystemExit) as error:
        cli.main()
    assert error.value.code == 2
    with env.db() as db:
        assert db.scalar(select(User)) is None


def test_asgi_entrypoint_starts_without_provider_key(env, monkeypatch):
    import os

    from fastapi.testclient import TestClient

    for key in os.environ:
        if key.startswith("LANGO_") or key in ("GOOGLE_API_KEY", "GEMINI_API_KEY"):
            monkeypatch.delenv(key)
    monkeypatch.setenv("LANGO_JWT_SECRET", env.settings.jwt_secret.get_secret_value())
    monkeypatch.setenv("LANGO_DATABASE_URL", env.settings.database_url.get_secret_value())
    monkeypatch.setenv("LANGO_MEMORY_PATH", env.settings.memory_path)
    sys.modules.pop("lango.main", None)
    entry = importlib.import_module("lango.main")
    with TestClient(entry.app) as client:
        assert client.get("/healthz").json() == {"status": "ok"}
    launches = []
    monkeypatch.setattr(entry.uvicorn, "run", lambda *args, **kwargs: launches.append(kwargs))
    entry.main()
    assert launches[0]["host"] == "127.0.0.1"
    assert launches[0]["access_log"] is False and launches[0]["ws_max_size"] == 65536
    sys.modules.pop("lango.main", None)


def test_privacy_logging_suppresses_provider_and_query_details():
    privacy = PrivacyFilter()
    record = logging.LogRecord(
        "uvicorn.error", logging.INFO, "", 0, "/talk?ticket=private-ticket", (), None
    )
    assert privacy.filter(record)
    assert "private-ticket" not in record.getMessage()
    record = logging.LogRecord(
        "google.genai", logging.ERROR, "", 0, "private-provider-details", (), None
    )
    assert not privacy.filter(record)
    record = logging.LogRecord(
        "uvicorn.error",
        logging.ERROR,
        "",
        0,
        "failure",
        (),
        (ValueError, ValueError("private"), None),
    )
    assert privacy.filter(record)
    assert record.exc_info is None and "private" not in record.getMessage()
