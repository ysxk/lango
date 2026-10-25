import pytest
from conftest import register
from sqlalchemy import func, select

from lango.db import MemoryItem, MemoryJob, TalkSession, Turn, User, now
from lango.memory import Mem0Store, context_memories, enqueue_session, forget, namespace
from lango.worker import Worker, singleton


def enqueue(env, user, text="I enjoy hiking.", scenario=None):
    with env.db.begin() as db:
        session = TalkSession(
            user_id=user.id, title="Practice", engine="cascade", scenario_id=scenario
        )
        db.add(session)
        db.flush()
        db.add(Turn(session_id=session.id, role="user", text=text))
        db.flush()
        enqueue_session(db, session, 0)


def test_memory_worker_persistence_scope_and_delete(env):
    one, two = register(env), register(env, "two@example.com")
    enqueue(env, one)
    worker = Worker(env.db, env.settings, env.memory)
    assert worker.run_once()
    items = env.client.get("/api/v1/memories", headers=one.headers).json()["items"]
    assert len(items) == 1 and items[0]["memory"] == "I enjoy hiking."
    assert env.client.get("/api/v1/memories", headers=two.headers).json()["items"] == []
    assert (
        env.client.delete("/api/v1/memories/" + items[0]["id"], headers=two.headers).status_code
        == 404
    )
    with env.db() as db:
        assert context_memories(db, db.get(User, one.id)) == ["I enjoy hiking."]
        assert context_memories(db, db.get(User, two.id)) == []
    assert env.client.delete("/api/v1/memories", headers=one.headers).json() == {"ok": True}
    assert env.client.get("/api/v1/memories", headers=one.headers).json()["items"] == []
    assert worker.run_once()
    assert env.memory.rows == {}
    assert not worker.run_once()


def test_delete_invalidates_queued_and_inflight_facts(env):
    user = register(env)
    enqueue(env, user)
    worker = Worker(env.db, env.settings, env.memory)

    def delete_during_add():
        assert env.client.delete("/api/v1/memories", headers=user.headers).status_code == 200

    env.memory.on_add = delete_during_add
    assert worker.run_once()
    assert env.client.get("/api/v1/memories", headers=user.headers).json()["items"] == []
    assert namespace(user.id, 0) in env.memory.purged
    env.memory.on_add = None
    enqueue(env, user, "I like tea.")
    assert worker.run_once()
    assert worker.run_once()
    assert [
        i["memory"]
        for i in env.client.get("/api/v1/memories", headers=user.headers).json()["items"]
    ] == ["I like tea."]
    enqueue(env, user, "Queued old fact")
    assert env.client.delete("/api/v1/memories", headers=user.headers).status_code == 200
    while worker.run_once():
        pass
    assert not any("Queued old fact" in str(messages) for _, messages, _ in env.memory.added)
    with env.db() as db:
        assert db.scalar(select(func.count()).select_from(MemoryItem)) == 0
        assert all(job.payload == {} for job in db.scalars(select(MemoryJob)))


def test_single_delete_preserves_other_facts_and_rebuilds_new_epoch(env):
    user = register(env)
    enqueue(env, user, "I like tea.")
    enqueue(env, user, "I enjoy hiking.")
    worker = Worker(env.db, env.settings, env.memory)
    while worker.run_once():
        pass
    items = env.client.get("/api/v1/memories", headers=user.headers).json()["items"]
    tea = next(i for i in items if i["memory"] == "I like tea.")
    assert (
        env.client.delete("/api/v1/memories/" + tea["id"], headers=user.headers).status_code == 200
    )
    remaining = env.client.get("/api/v1/memories", headers=user.headers).json()["items"]
    assert [i["memory"] for i in remaining] == ["I enjoy hiking."]
    while worker.run_once():
        pass
    assert env.memory.rows[namespace(user.id, 1)][0]["memory"] == "I enjoy hiking."
    assert namespace(user.id, 0) not in env.memory.rows
    assert env.memory.added[-1][2] is False


def test_disable_memory_invalidates_jobs_and_old_session_turns(env):
    user = register(env)
    enqueue(env, user)
    response = env.client.patch("/api/v1/me", headers=user.headers, json={"memory_enabled": False})
    assert response.status_code == 200
    worker = Worker(env.db, env.settings, env.memory)
    while worker.run_once():
        pass
    enqueue(env, user, "Disabled memory fact")
    assert not worker.run_once() and env.memory.added == []
    assert env.client.get("/api/v1/memories", headers=user.headers).json() == {
        "items": [],
        "enabled": False,
    }
    env.client.patch("/api/v1/me", headers=user.headers, json={"memory_enabled": True})
    assert worker.run_once()
    with env.db.begin() as db:
        session = db.scalar(
            select(TalkSession)
            .where(TalkSession.user_id == user.id)
            .order_by(TalkSession.started_at)
        )
        enqueue_session(db, session, 0)
    assert not worker.run_once()


def test_roleplay_never_enters_personal_memory(env):
    user = register(env)
    enqueue(env, user, "I am a doctor in Paris.", scenario="job-interview")
    with env.db() as db:
        assert db.scalar(select(func.count()).select_from(MemoryJob)) == 0


def test_job_claim_lease_retry_and_sanitized_errors(env):
    user = register(env)
    enqueue(env, user)
    one, two = Worker(env.db, env.settings, env.memory), Worker(env.db, env.settings, env.memory)
    job = one.claim()
    assert job and two.claim() is None
    with env.db.begin() as db:
        db.get(MemoryJob, job.id).lease_until = now() - 1
    replacement = two.claim()
    assert replacement.lease_token != job.lease_token and replacement.attempts == 2
    one.finish(job)
    with env.db() as db:
        assert db.get(MemoryJob, job.id).status == "running"
    two.process(replacement)
    enqueue(env, user, "Another fact")

    def fail(*_args, **_kwargs):
        raise RuntimeError("secret-private-provider-details")

    env.memory.add = fail
    assert one.run_once()
    with env.db() as db:
        deferred = db.scalar(select(MemoryJob).where(MemoryJob.status == "pending"))
        assert deferred.last_error == "memory_provider_unavailable"
        assert deferred.available_at > now()
    assert not one.run_once()


def test_forgetting_multiple_times_preserves_epoch_isolation(env):
    user = register(env)
    enqueue(env, user)
    with env.db.begin() as db:
        forget(db, user.id)
        forget(db, user.id)
    worker = Worker(env.db, env.settings, env.memory)
    while worker.run_once():
        pass
    with env.db() as db:
        assert db.get(User, user.id).memory_epoch == 2
        assert context_memories(db, db.get(User, user.id)) == []


def test_worker_singleton(env):
    with singleton(env.engine, env.settings):
        with (
            pytest.raises(SystemExit, match="already running"),
            singleton(env.engine, env.settings),
        ):
            pass


def test_actual_mem0_local_vector_persistence_without_network(env, monkeypatch):
    from pydantic import SecretStr

    from lango.logging import safe_logging

    safe_logging()
    monkeypatch.setenv("MEM0_TELEMETRY", "false")
    settings = env.settings.model_copy(
        update={"google_api_key": SecretStr("test-only-not-a-real-key")}
    )
    scope = namespace("test-user", 0)
    store = Mem0Store(settings)
    client = store.client()
    assert client.config.history_db_path == ":memory:"
    monkeypatch.setattr(client.embedding_model, "embed", lambda *_a, **_k: [0.1] * 768)
    store.add(scope, [{"role": "user", "content": "Likes tea"}], infer=False)
    assert store.list(scope)[0]["memory"] == "Likes tea"
    assert store.list(namespace("different-user", 0)) == []
    store.close()
    restored = Mem0Store(settings)
    try:
        assert restored.list(scope)[0]["memory"] == "Likes tea"
        restored.purge(scope)
        assert restored.list(scope) == []
    finally:
        restored.close()


def test_pending_rebuild_blocks_new_ingestion_without_hiding_survivors(env):
    user = register(env)
    enqueue(env, user, "Keep this fact")
    enqueue(env, user, "Forget this fact")
    worker = Worker(env.db, env.settings, env.memory)
    while worker.run_once():
        pass
    items = env.client.get("/api/v1/memories", headers=user.headers).json()["items"]
    forgotten = next(item for item in items if item["memory"] == "Forget this fact")
    env.client.delete("/api/v1/memories/" + forgotten["id"], headers=user.headers)
    with env.db.begin() as db:
        rebuild = db.scalar(select(MemoryJob).where(MemoryJob.kind == "rebuild"))
        rebuild.available_at = now() + 3600
    enqueue(env, user, "A new fact")
    assert worker.run_once()  # Old namespace purge.
    assert not worker.run_once()
    assert [
        item["memory"]
        for item in env.client.get("/api/v1/memories", headers=user.headers).json()["items"]
    ] == ["Keep this fact"]
    with env.db.begin() as db:
        db.scalar(select(MemoryJob).where(MemoryJob.kind == "rebuild")).available_at = 0
    assert worker.run_once()
    assert worker.run_once()
    assert {
        item["memory"]
        for item in env.client.get("/api/v1/memories", headers=user.headers).json()["items"]
    } == {"Keep this fact", "A new fact"}


def test_pause_retains_stored_memories_but_never_retroactively_ingests_paused_turns(env):
    user = register(env)
    worker = Worker(env.db, env.settings, env.memory)
    enqueue(env, user, "Stored preference")
    assert worker.run_once()
    original = env.client.get("/api/v1/memories", headers=user.headers).json()["items"]
    enqueue(env, user, "Queued before pause")
    assert (
        env.client.patch("/api/v1/me", headers=user.headers, json={"memory_enabled": False}).json()[
            "memory_enabled"
        ]
        is False
    )
    paused = env.client.get("/api/v1/memories", headers=user.headers).json()
    assert paused == {"enabled": False, "items": original}
    with env.db() as db:
        assert context_memories(db, db.get(User, user.id)) == []
    enqueue(env, user, "Said while paused")
    while worker.run_once():
        pass
    assert env.memory.rows == {}
    assert (
        env.client.patch("/api/v1/me", headers=user.headers, json={"memory_enabled": True}).json()[
            "memory_enabled"
        ]
        is True
    )
    with env.db.begin() as db:
        for session in db.scalars(select(TalkSession).where(TalkSession.user_id == user.id)):
            enqueue_session(db, session, 0)
        assert context_memories(db, db.get(User, user.id)) == ["Stored preference"]
    while worker.run_once():
        pass
    assert [
        item["memory"]
        for item in env.client.get("/api/v1/memories", headers=user.headers).json()["items"]
    ] == ["Stored preference"]
    assert not any(
        "Said while paused" in str(messages) or "Queued before pause" in str(messages)
        for _, messages, _ in env.memory.added
    )
    enqueue(env, user, "New after resume")
    assert worker.run_once()
    assert {
        item["memory"]
        for item in env.client.get("/api/v1/memories", headers=user.headers).json()["items"]
    } == {"Stored preference", "New after resume"}


@pytest.mark.parametrize("resume_inflight", [False, True])
def test_pause_invalidates_inflight_extraction_without_losing_stored_facts(env, resume_inflight):
    user = register(env)
    worker = Worker(env.db, env.settings, env.memory)
    enqueue(env, user, "Stored preference")
    assert worker.run_once()
    enqueue(env, user, "Inflight unapproved fact")

    def toggle():
        env.client.patch("/api/v1/me", headers=user.headers, json={"memory_enabled": False})
        if resume_inflight:
            env.client.patch("/api/v1/me", headers=user.headers, json={"memory_enabled": True})

    env.memory.on_add = toggle
    assert worker.run_once()
    env.memory.on_add = None
    assert [
        item["memory"]
        for item in env.client.get("/api/v1/memories", headers=user.headers).json()["items"]
    ] == ["Stored preference"]
    if not resume_inflight:
        env.client.patch("/api/v1/me", headers=user.headers, json={"memory_enabled": True})
    while worker.run_once():
        pass
    assert [
        item["memory"]
        for item in env.client.get("/api/v1/memories", headers=user.headers).json()["items"]
    ] == ["Stored preference"]
    with env.db() as db:
        assert context_memories(db, db.get(User, user.id)) == ["Stored preference"]


def test_explicit_delete_while_paused_is_not_restored_by_reenabling(env):
    user = register(env)
    worker = Worker(env.db, env.settings, env.memory)
    enqueue(env, user, "Forget explicitly")
    enqueue(env, user, "Keep this")
    while worker.run_once():
        pass
    env.client.patch("/api/v1/me", headers=user.headers, json={"memory_enabled": False})
    items = env.client.get("/api/v1/memories", headers=user.headers).json()["items"]
    forgotten = next(item for item in items if item["memory"] == "Forget explicitly")
    assert (
        env.client.delete("/api/v1/memories/" + forgotten["id"], headers=user.headers).status_code
        == 200
    )
    while worker.run_once():
        pass
    env.client.patch("/api/v1/me", headers=user.headers, json={"memory_enabled": True})
    while worker.run_once():
        pass
    assert [
        item["memory"]
        for item in env.client.get("/api/v1/memories", headers=user.headers).json()["items"]
    ] == ["Keep this"]
    env.client.patch("/api/v1/me", headers=user.headers, json={"memory_enabled": False})
    env.client.delete("/api/v1/memories", headers=user.headers)
    env.client.patch("/api/v1/me", headers=user.headers, json={"memory_enabled": True})
    while worker.run_once():
        pass
    assert env.client.get("/api/v1/memories", headers=user.headers).json()["items"] == []
