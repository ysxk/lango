import asyncio
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from lango.api import create_app
from lango.config import Settings
from lango.db import make_database
from lango.migrate import upgrade
from lango.security import create_invite

PASSWORD = "test-only-strong-password"


class FakeEngine:
    def __init__(self):
        self.calls = []
        self.closed = 0
        self.fail = False
        self.wait = False
        self.native = False

    async def generate(self, **kwargs):
        self.calls.append(kwargs)
        try:
            if self.fail:
                raise RuntimeError("private-provider-error secret-token-never-return")
            if kwargs.get("pcm"):
                yield {"kind": "transcript", "text": "I enjoy hiking."}
            yield {"kind": "text", "text": "Hello there. Unheard sentence."}
            yield {
                "kind": "audio",
                "pcm": b"\x00\x00" * 160,
                "text": "" if self.native else "Hello there.",
            }
            yield {
                "kind": "audio",
                "pcm": b"\x00\x00" * 160,
                "text": "" if self.native else "Unheard sentence.",
            }
            if self.wait:
                await asyncio.Event().wait()
        finally:
            self.closed += 1

    async def evaluate(self, goals, texts):
        return [0, -1, 999, True]


class FakeMemory:
    def __init__(self):
        self.rows = {}
        self.on_add = None
        self.added = []
        self.purged = []

    def add(self, scope, messages, *, infer=True):
        self.added.append((scope, messages, infer))
        for message in messages:
            from lango.db import uid

            self.rows.setdefault(scope, []).append(
                {"id": uid(), "user_id": scope, "memory": message["content"]}
            )
        if self.on_add:
            self.on_add()

    def list(self, scope):
        return self.rows.get(scope, [])

    def purge(self, scope):
        self.purged.append(scope)
        self.rows.pop(scope, None)

    def close(self):
        pass


@pytest.fixture
def env(tmp_path):
    settings = Settings(
        jwt_secret="test-only-" + "s" * 40,
        database_url=f"sqlite:///{tmp_path / 'lango.db'}",
        memory_path=str(tmp_path / "memory"),
        google_api_key=None,
        allowed_origins=["https://app.example.com"],
    )
    database = make_database(settings)
    upgrade(database[0])
    fake = FakeEngine()
    app = create_app(settings, engine=fake, database=database)
    with TestClient(app) as client:
        yield SimpleNamespace(
            settings=settings,
            engine=database[0],
            db=database[1],
            fake=fake,
            app=app,
            client=client,
            memory=FakeMemory(),
        )


def register(env, email="learner@example.com"):
    with env.db.begin() as db:
        code = create_invite(db)["code"]
    result = env.client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": PASSWORD,
            "display_name": "Learner",
            "invite_code": code,
        },
    )
    assert result.status_code == 200, result.text
    pair = result.json()
    headers = {"Authorization": "Bearer " + pair["access_token"]}
    user_id = env.client.get("/api/v1/me", headers=headers).json()["id"]
    return SimpleNamespace(id=user_id, headers=headers, pair=pair)


def ticket(env, user):
    result = env.client.post("/api/v1/talk/ticket", headers=user.headers)
    assert result.status_code == 200, result.text
    return "/api/v1/talk?ticket=" + result.json()["ticket"]


def receive(ws, kind):
    for _ in range(100):
        message = ws.receive_json()
        if message["type"] == kind:
            return message
    raise AssertionError(f"Did not receive {kind}")
