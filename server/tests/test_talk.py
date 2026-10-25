import base64
import io
import wave

import pytest
from conftest import receive, register, ticket
from sqlalchemy import func, select
from starlette.websockets import WebSocketDisconnect

from lango.db import MemoryJob, TalkSession, Ticket, Turn, Usage, User, now
from lango.providers import GeminiEngine


def start(ws, **options):
    ws.send_json({"type": "session.start", "mode": "ptt", **options})
    return receive(ws, "session.created")["session_id"]


def complete(ws):
    response_id = receive(ws, "response.started")["response_id"]
    segments = [receive(ws, "response.audio"), receive(ws, "response.audio")]
    assert receive(ws, "response.done")["status"] == "completed"
    for segment in segments:
        ws.send_json(
            {"type": "playback.ack", "response_id": response_id, "sequence": segment["sequence"]}
        )
    receive(ws, "state")
    return response_id, segments


def end(ws):
    ws.send_json({"type": "session.end"})
    return receive(ws, "session.ended")


def detail(env, user, session_id):
    return env.client.get("/api/v1/sessions/" + session_id, headers=user.headers).json()


def test_ticket_replay_expiration_and_origin(env):
    user = register(env)
    url = ticket(env, user)
    with (
        pytest.raises(WebSocketDisconnect),
        env.client.websocket_connect(url, headers={"Origin": "https://evil.example.com"}),
    ):
        pass
    with env.client.websocket_connect(url, headers={"Origin": "https://app.example.com"}) as ws:
        ws.send_json({"type": "ping"})
        assert receive(ws, "pong") == {"type": "pong"}
    with pytest.raises(WebSocketDisconnect), env.client.websocket_connect(url):
        pass
    url = ticket(env, user)
    with env.db.begin() as db:
        for row in db.scalars(select(Ticket).where(Ticket.used.is_(False))):
            row.expires_at = now() - 1
    with pytest.raises(WebSocketDisconnect), env.client.websocket_connect(url):
        pass
    with (
        pytest.raises(WebSocketDisconnect),
        env.client.websocket_connect("/api/v1/talk?ticket=" + user.pair["access_token"]),
    ):
        pass


def test_text_audio_order_wav_acks_history_and_resume(env):
    user = register(env)
    with env.client.websocket_connect(ticket(env, user)) as ws:
        sid = start(ws)
        _, segments = complete(ws)
        assert [s["sequence"] for s in segments] == [0, 1]
        for segment in segments:
            assert segment["mime_type"] == "audio/wav"
            with wave.open(io.BytesIO(base64.b64decode(segment["audio"]))) as audio:
                assert (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) == (
                    1,
                    2,
                    24000,
                )
        ws.send_json({"type": "text.input", "text": "I like hiking."})
        complete(ws)
        assert end(ws)["session_id"] == sid
    history = detail(env, user, sid)
    assert history["ended_at"] and len(history["turns"]) == 3
    assert history["turns"][1]["role"] == "user" and history["turns"][1]["text"] == "I like hiking."
    assert all(not turn["interrupted"] for turn in history["turns"])
    assert env.fake.calls[-1]["history"] == [
        {"role": "assistant", "text": "Hello there. Unheard sentence."}
    ]
    with env.client.websocket_connect(ticket(env, user)) as ws:
        assert start(ws, session_id=sid) == sid
        receive(ws, "state")
        assert len(env.fake.calls) == 2
        ws.send_json({"type": "text.input", "text": "What next?"})
        complete(ws)
        end(ws)
    assert len(env.fake.calls[-1]["history"]) == 3
    with env.db() as db:
        assert db.get(User, user.id).active_connection is None
        assert db.scalar(select(func.count()).select_from(MemoryJob)) == 2


def test_ack_only_heard_history_and_completed_generation_cancel(env):
    user = register(env)
    with env.client.websocket_connect(ticket(env, user)) as ws:
        sid = start(ws)
        rid = receive(ws, "response.started")["response_id"]
        receive(ws, "response.audio")
        receive(ws, "response.audio")
        receive(ws, "response.done")
        assert detail(env, user, sid)["turns"] == []
        ws.send_json({"type": "playback.ack", "response_id": rid, "sequence": 1})
        assert receive(ws, "error")["code"] == "invalid_input"
        ws.send_json({"type": "playback.ack", "response_id": rid, "sequence": 0})
        ws.send_json({"type": "response.cancel", "response_id": rid})
        assert receive(ws, "response.done")["status"] == "cancelled"
        ws.send_json({"type": "playback.ack", "response_id": rid, "sequence": 1})
        end(ws)
    turns = detail(env, user, sid)["turns"]
    assert len(turns) == 1 and turns[0]["text"] == "Hello there." and turns[0]["interrupted"]


def test_cancel_closes_upstream_and_next_input_discards_unheard(env):
    user = register(env)
    env.fake.wait = True
    with env.client.websocket_connect(ticket(env, user)) as ws:
        sid = start(ws)
        rid = receive(ws, "response.started")["response_id"]
        receive(ws, "response.audio")
        receive(ws, "response.audio")
        ws.send_json({"type": "playback.ack", "response_id": rid, "sequence": 0})
        ws.send_json({"type": "response.cancel", "response_id": rid})
        assert receive(ws, "response.done")["status"] == "cancelled"
        assert env.fake.closed == 1
        env.fake.wait = False
        ws.send_json({"type": "text.input", "text": "Next turn"})
        complete(ws)
        assert env.fake.calls[-1]["history"][0]["text"] == "Hello there."
        end(ws)
    assert detail(env, user, sid)["turns"][0]["interrupted"]


def test_new_binary_turn_interrupts_and_input_cancel_discards(env):
    user = register(env)
    env.fake.wait = True
    with env.client.websocket_connect(ticket(env, user)) as ws:
        start(ws)
        receive(ws, "response.started")
        receive(ws, "response.audio")
        receive(ws, "response.audio")
        ws.send_bytes(b"\x00\x00" * 40)
        assert receive(ws, "response.done")["status"] == "cancelled"
        ws.send_json({"type": "input.cancel"})
        ws.send_json({"type": "input.commit"})
        assert receive(ws, "error")["code"] == "invalid_input"
        env.fake.wait = False
        ws.send_bytes(b"\x00\x00" * 100)
        ws.send_json({"type": "input.commit"})
        t_msg = receive(ws, "input.transcript")
        assert t_msg["text"] == "I enjoy hiking."
        assert t_msg.get("turn_id") is not None
        # response.started precedes the transcript, so consume the rest directly.
        audio = [receive(ws, "response.audio"), receive(ws, "response.audio")]
        done = receive(ws, "response.done")
        for segment in audio:
            ws.send_json(
                {
                    "type": "playback.ack",
                    "response_id": done["response_id"],
                    "sequence": segment["sequence"],
                }
            )
        end(ws)
    assert env.fake.calls[-1]["pcm"] == b"\x00\x00" * 100


@pytest.mark.parametrize("native", [False, True])
def test_disconnect_does_not_persist_unheard_and_releases_connection(env, native):
    user = register(env)
    env.fake.native = native
    with env.client.websocket_connect(ticket(env, user)) as ws:
        sid = start(ws, engine="live" if native else "cascade")
        receive(ws, "response.done")
    with env.db() as db:
        assert db.get(User, user.id).active_connection is None
        assert db.get(TalkSession, sid).ended_at is not None
    assert detail(env, user, sid)["turns"] == []


def test_live_history_retained_only_after_all_audio_acknowledged(env):
    user = register(env)
    env.fake.native = True
    with env.client.websocket_connect(ticket(env, user)) as ws:
        sid = start(ws, engine="live")
        complete(ws)
        end(ws)
    turns = detail(env, user, sid)["turns"]
    assert turns[0]["text"] == "Hello there. Unheard sentence."
    assert turns[0]["interrupted"] is False


def test_session_ownership_quota_and_simultaneous_connection(env):
    one, two = register(env), register(env, "other@example.com")
    with env.client.websocket_connect(ticket(env, one)) as ws:
        sid = start(ws)
        complete(ws)
        with env.client.websocket_connect(ticket(env, one)) as duplicate:
            duplicate.send_json({"type": "session.start", "mode": "ptt"})
            assert "already active" in receive(duplicate, "error")["message"]
        with env.client.websocket_connect(ticket(env, two)) as other:
            other.send_json({"type": "session.start", "mode": "ptt", "session_id": sid})
            assert receive(other, "error")["message"] == "Session not found"
        end(ws)
    with env.db.begin() as db:
        from lango.talk import today

        usage = db.get(Usage, (one.id, today()))
        usage.seconds = 3600
    with env.client.websocket_connect(ticket(env, one)) as ws:
        ws.send_json({"type": "session.start", "mode": "ptt"})
        assert receive(ws, "error")["code"] == "rate_limit"


@pytest.mark.parametrize(
    "payload",
    [
        "{",
        "[]",
        '{"type":[]}',
        '{"type":"unknown"}',
        '{"type":"text.input","text":" "}',
        "x" * 16385,
    ],
)
def test_ws_invalid_input_does_not_break_connection(env, payload):
    user = register(env)
    with env.client.websocket_connect(ticket(env, user)) as ws:
        ws.send_text(payload)
        assert receive(ws, "error")["code"] == "invalid_input"
        ws.send_json({"type": "ping"})
        receive(ws, "pong")


def test_audio_bounds_order_and_reset(env):
    user = register(env)
    with env.client.websocket_connect(ticket(env, user)) as ws:
        ws.send_bytes(b"\x00\x00")
        assert "Start a session" in receive(ws, "error")["message"]
        start(ws)
        complete(ws)
        ws.send_bytes(b"\x00" * 65537)
        assert "limit" in receive(ws, "error")["message"]
        for _ in range(30):
            ws.send_bytes(b"\x00" * 64000)
        ws.send_bytes(b"\x00\x00")
        assert "60-second" in receive(ws, "error")["message"]
        ws.send_json({"type": "input.commit"})
        assert "complete PCM16" in receive(ws, "error")["message"]
        ws.send_bytes(b"\x00")
        ws.send_json({"type": "input.commit"})
        assert "complete PCM16" in receive(ws, "error")["message"]
        end(ws)


def test_provider_errors_are_sanitized_and_recoverable(env):
    user = register(env)
    env.fake.fail = True
    with env.client.websocket_connect(ticket(env, user)) as ws:
        sid = start(ws)
        error = receive(ws, "error")
        assert error["code"] == "model_unavailable" and error["retryable"]
        assert "secret" not in str(error) and "private" not in str(error)
        assert receive(ws, "response.done")["status"] == "failed"
        env.fake.fail = False
        ws.send_json({"type": "text.input", "text": "Try again"})
        complete(ws)
        end(ws)
    assert len(detail(env, user, sid)["turns"]) == 2


def test_missing_model_key_is_actionable_without_breaking_startup(env):
    user = register(env)
    env.app.state.tutor = GeminiEngine(env.settings)
    with env.client.websocket_connect(ticket(env, user)) as ws:
        start(ws)
        error = receive(ws, "error")
        assert error["code"] == "model_not_configured" and not error["retryable"]
        assert "LANGO_GOOGLE_API_KEY" in error["message"]
        assert receive(ws, "response.done")["status"] == "failed"
        end(ws)


def test_scenario_progress_is_validated_and_not_ingested(env):
    user = register(env)
    with env.client.websocket_connect(ticket(env, user)) as ws:
        sid = start(ws, scenario_id="cafe-order")
        complete(ws)
        ws.send_json({"type": "text.input", "text": "A medium latte please."})
        complete(ws)
        end(ws)
    assert detail(env, user, sid)["completed_goals"] == [0]
    with env.db() as db:
        assert db.scalar(select(func.count()).select_from(MemoryJob)) == 0


async def test_text_only_history_and_charge_midnight(env, monkeypatch):
    from types import SimpleNamespace

    from lango.talk import Actor, Response

    user = register(env)
    with env.db.begin() as db:
        session = TalkSession(user_id=user.id, title="Text", engine="cascade")
        db.add(session)
        db.flush()
        sid = session.id
        row = db.get(User, user.id)
        row.active_connection = "connection"
        db.add(Turn(id="response", session_id=sid, role="assistant"))
    actor = Actor(SimpleNamespace(), user.id, env.db, env.settings, env.fake)
    actor.session_id, actor.connection_id = sid, "connection"
    actor.persist(Response(id="response", text="Text without audio", status="completed"))
    with env.db() as db:
        assert db.get(Turn, "response").text == "Text without audio"
    import lango.talk as talk_module

    midnight = (int(now() // 86400) + 1) * 86400
    monkeypatch.setattr(talk_module, "now", lambda: midnight + 5)
    actor.last_charge = midnight - 7
    assert actor.charge() is False
    with env.db() as db:
        assert 11 <= db.get(TalkSession, sid).duration_seconds <= 13
        from datetime import UTC, datetime

        previous_day = datetime.fromtimestamp(midnight - 7, UTC).date().isoformat()
        next_day = datetime.fromtimestamp(midnight + 5, UTC).date().isoformat()
        assert db.get(Usage, (user.id, previous_day)).seconds == 7
        assert db.get(Usage, (user.id, next_day)).seconds == 5


def test_audio_backpressure_is_bounded_and_cancellable(env):
    user = register(env)
    produced = []

    async def many_segments(**kwargs):
        try:
            for i in range(30):
                produced.append(i)
                yield {"kind": "audio", "pcm": b"\x00\x00" * 80, "text": f"Phrase {i}."}
        finally:
            env.fake.closed += 1

    env.fake.generate = many_segments
    with env.client.websocket_connect(ticket(env, user)) as ws:
        start(ws)
        rid = receive(ws, "response.started")["response_id"]
        for sequence in range(8):
            assert receive(ws, "response.audio")["sequence"] == sequence
        ws.send_json({"type": "ping"})
        receive(ws, "pong")
        assert len(produced) == 9
        ws.send_json({"type": "playback.ack", "response_id": rid, "sequence": 0})
        assert receive(ws, "response.audio")["sequence"] == 8
        ws.send_json({"type": "response.cancel", "response_id": rid})
        assert receive(ws, "response.done")["status"] == "cancelled"
        assert env.fake.closed == 1
        end(ws)


def test_resumed_session_keeps_engine_and_scenario(env):
    user = register(env)
    with env.client.websocket_connect(ticket(env, user)) as ws:
        sid = start(ws, scenario_id="cafe-order")
        complete(ws)
        end(ws)
    with env.client.websocket_connect(ticket(env, user)) as ws:
        ws.send_json({"type": "session.start", "mode": "ptt", "session_id": sid, "engine": "live"})
        assert "original engine" in receive(ws, "error")["message"]
        ws.send_json(
            {
                "type": "session.start",
                "mode": "ptt",
                "session_id": sid,
                "scenario_id": "job-interview",
            }
        )
        assert "original engine" in receive(ws, "error")["message"]
        assert start(ws, session_id=sid) == sid
        end(ws)


def test_input_rejected_and_session_full(env):
    user = register(env)
    with env.client.websocket_connect(ticket(env, user)) as ws:
        sid = start(ws)
        complete(ws)
        # Fill session with 400 turns
        with env.db.begin() as db:
            for _ in range(400):
                db.add(Turn(session_id=sid, role="user", text="test"))
        ws.send_json({"type": "text.input", "text": "Will be rejected due to session limit"})
        rejected = receive(ws, "input.rejected")
        assert rejected["code"] == "session_full"
        assert rejected["retryable"] is False
        assert "Session turn limit" in rejected["message"]
        err = receive(ws, "error")
        assert err["code"] == "session_full"
        end(ws)


def test_rejected_turn_recovers_without_response_done(env, monkeypatch):
    from fastapi import HTTPException

    from lango import talk

    original_limit = talk.rate_limit
    blocked = False

    def limit(*args):
        if blocked:
            raise HTTPException(429, "Too many requests; try again later")
        return original_limit(*args)

    monkeypatch.setattr(talk, "rate_limit", limit)
    user = register(env)
    with env.client.websocket_connect(ticket(env, user)) as ws:
        sid = start(ws)
        complete(ws)
        blocked = True
        ws.send_json({"type": "text.input", "text": "Rejected input"})
        rejected = receive(ws, "input.rejected")
        assert rejected["code"] == "rate_limit" and rejected["retryable"]
        assert receive(ws, "error")["code"] == "rate_limit"
        assert receive(ws, "state")["state"] == "listening"
        blocked = False
        ws.send_json({"type": "text.input", "text": "Accepted input"})
        complete(ws)
        end(ws)
    turns = detail(env, user, sid)["turns"]
    assert [turn["text"] for turn in turns if turn["role"] == "user"] == ["Accepted input"]


def test_cumulative_transcripts_keep_one_persisted_turn_id(env, monkeypatch):
    async def generate(**kwargs):
        if kwargs.get("pcm"):
            yield {"kind": "transcript", "text": "I like"}
            yield {"kind": "transcript", "text": "I like tea."}
        yield {"kind": "text", "text": "Understood."}

    monkeypatch.setattr(env.fake, "generate", generate)
    user = register(env)
    with env.client.websocket_connect(ticket(env, user)) as ws:
        sid = start(ws)
        receive(ws, "response.done")
        ws.send_bytes(b"\x01\x00" * 8000)
        ws.send_json({"type": "input.commit"})
        first = receive(ws, "input.transcript")
        second = receive(ws, "input.transcript")
        assert first["text"] == "I like" and second["text"] == "I like tea."
        assert first["turn_id"] == second["turn_id"]
        receive(ws, "response.done")
        end(ws)
    turns = [turn for turn in detail(env, user, sid)["turns"] if turn["role"] == "user"]
    assert len(turns) == 1
    assert turns[0]["id"] == second["turn_id"] and turns[0]["text"] == second["text"]
