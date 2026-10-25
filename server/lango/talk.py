import asyncio
import base64
import json
from contextlib import aclosing, suppress
from dataclasses import dataclass, field
from datetime import UTC, datetime

from fastapi import HTTPException, WebSocket, WebSocketDisconnect
from pydantic import ValidationError
from sqlalchemy import func, or_, select, update

from lango import schemas
from lango.db import TalkSession, Turn, Usage, User, now, uid
from lango.memory import context_memories, enqueue_session
from lango.providers import ModelError, wav_bytes
from lango.scenarios import BY_ID
from lango.security import rate_limit

MAX_PCM = 16000 * 2 * 60


def today():
    return datetime.now(UTC).date().isoformat()


@dataclass
class Response:
    id: str = field(default_factory=uid)
    text: str = ""
    segments: list[str] = field(default_factory=list)
    ack: int = -1
    status: str = "generating"
    task: asyncio.Task | None = None
    changed: asyncio.Event = field(default_factory=asyncio.Event)


class Actor:
    def __init__(self, ws: WebSocket, user_id: str, factory, settings, engine):
        self.ws, self.user_id, self.factory, self.settings, self.engine = (
            ws,
            user_id,
            factory,
            settings,
            engine,
        )
        self.session_id = None
        self.connection_id = uid()
        self.scenario = None
        self.engine_id = settings.default_engine
        self.audio = bytearray()
        self.response: Response | None = None
        self.send_lock = asyncio.Lock()
        self.closed = False
        self.started = now()
        self.last_charge = self.started
        self.heartbeat = None
        self.message_count, self.message_window = 0, now()

    async def send(self, event_type, **data):
        if not self.closed:
            async with self.send_lock:
                async with asyncio.timeout(10):
                    await self.ws.send_json({"type": event_type, **data})

    async def error(self, code, message, retryable=False):
        await self.send("error", code=code, message=message, retryable=retryable)

    async def start(self, start):
        if self.session_id:
            raise HTTPException(409, "A session has already started")
        if start.scenario_id and start.scenario_id not in BY_ID:
            raise HTTPException(404, "Scenario not found")
        with self.factory.begin() as db:
            usage = db.get(Usage, (self.user_id, today()))
            if usage and usage.seconds >= self.settings.daily_minutes * 60:
                raise HTTPException(429, "Daily practice limit reached")
            if start.session_id:
                session = db.get(TalkSession, start.session_id)
                if not session or session.user_id != self.user_id:
                    raise HTTPException(404, "Session not found")
                if (start.engine and start.engine != session.engine) or (
                    start.scenario_id and start.scenario_id != session.scenario_id
                ):
                    raise HTTPException(
                        409, "A resumed session keeps its original engine and scenario"
                    )
            else:
                scenario = BY_ID.get(start.scenario_id)
                session = TalkSession(
                    user_id=self.user_id,
                    scenario_id=start.scenario_id,
                    engine=start.engine or self.settings.default_engine,
                    title=scenario["title"] if scenario else "English conversation",
                )
                db.add(session)
                db.flush()
            acquired = db.execute(
                update(User)
                .where(
                    User.id == self.user_id,
                    or_(User.active_connection.is_(None), User.connection_until < now()),
                )
                .values(active_connection=self.connection_id, connection_until=now() + 45)
            ).rowcount
            if not acquired:
                raise HTTPException(409, "Another practice connection is already active")
            session.ended_at = None
            self.session_id, self.engine_id = session.id, session.engine
            self.scenario = BY_ID.get(session.scenario_id)
            progress = session.completed_goals
        self.started = self.last_charge = now()
        self.heartbeat = asyncio.create_task(self.keepalive())
        await self.send(
            "session.created",
            session_id=self.session_id,
            audio={"input_rate": 16000, "output_rate": 24000},
        )
        await self.send("scenario.progress", completed_goals=progress)
        await self.send("state", state="listening")
        if not start.session_id:
            await self.begin(
                text="Begin the conversation with a short greeting and one question. Use the scenario opening if provided.",
                persist_user=False,
            )

    def charge(self):
        stamp = now()
        elapsed = max(0, min(stamp - self.last_charge, 45))
        with self.factory.begin() as db:
            acquired = db.execute(
                update(User)
                .where(
                    User.id == self.user_id,
                    User.active_connection == self.connection_id,
                )
                .values(connection_until=stamp + 45)
            ).rowcount
            if not acquired:
                raise HTTPException(409, "This practice connection has expired")
            # Split the measured connection time at UTC midnight.
            cursor = self.last_charge
            remaining = elapsed
            while remaining > 0:
                day = datetime.fromtimestamp(cursor, UTC).date().isoformat()
                midnight = (int(cursor // 86400) + 1) * 86400
                part = min(remaining, midnight - cursor)
                usage = db.get(Usage, (self.user_id, day))
                if usage is None:
                    usage = Usage(user_id=self.user_id, day=day, seconds=0)
                    db.add(usage)
                usage.seconds += part
                cursor += part
                remaining -= part
            session = db.get(TalkSession, self.session_id)
            session.duration_seconds += elapsed
            quota = db.get(Usage, (self.user_id, today()))
            exceeded = quota is not None and quota.seconds >= self.settings.daily_minutes * 60
        self.last_charge = stamp
        return exceeded

    async def keepalive(self):
        try:
            while True:
                await asyncio.sleep(10)
                if self.charge():
                    await self.error("daily_limit", "Daily practice limit reached.")
                    await self.cancel()
                    await self.ws.close(code=1000)
                    return
        except asyncio.CancelledError:
            raise
        except Exception:
            with suppress(Exception):
                await self.ws.close(code=1011)

    async def begin(self, *, text=None, pcm=None, persist_user=True):
        rate_limit(self.factory, self.settings, "turn", self.user_id, 30, 60)
        if self.charge():
            raise HTTPException(429, "Daily practice limit reached")
        with self.factory.begin() as db:
            count = db.scalar(
                select(func.count()).select_from(Turn).where(Turn.session_id == self.session_id)
            )
            if count >= 400:
                raise HTTPException(429, "Session turn limit reached; start a new session")
        await self.cancel()
        self.audio.clear()
        with self.factory.begin() as db:
            user = db.get(User, self.user_id)
            profile = schemas.profile(user)
            memories = context_memories(db, user)
            previous = list(
                reversed(
                    db.scalars(
                        select(Turn)
                        .where(
                            Turn.session_id == self.session_id,
                            Turn.text != "",
                        )
                        .order_by(Turn.created_at.desc(), Turn.id.desc())
                        .limit(40)
                    ).all()
                )
            )
            history = [{"role": t.role, "text": t.text} for t in previous]
            learner_id = None
            if persist_user:
                learner = Turn(session_id=self.session_id, role="user", text=text or "")
                db.add(learner)
                db.flush()
                learner_id = learner.id
            response = Response()
            db.add(
                Turn(id=response.id, session_id=self.session_id, role="assistant", interrupted=True)
            )
        self.response = response
        await self.send("response.started", response_id=response.id)
        await self.send("state", state="thinking")
        response.task = asyncio.create_task(
            self.generate(response, profile, history, memories, learner_id, text, pcm)
        )

    def persist(self, response):
        if response.segments:
            if self.engine_id == "live":
                text = (
                    response.text
                    if response.status == "completed" and response.ack == len(response.segments) - 1
                    else ""
                )
            else:
                text = " ".join(response.segments[: response.ack + 1])
        else:
            text = response.text if response.status == "completed" else ""
        complete = response.status == "completed" and (
            not response.segments or response.ack == len(response.segments) - 1
        )
        with self.factory.begin() as db:
            turn = db.get(Turn, response.id)
            turn.text, turn.interrupted = text.strip(), not complete

    async def generate(self, response, profile, history, memories, learner_id, text, pcm):
        status = "completed"
        try:
            stream = self.engine.generate(
                engine=self.engine_id,
                profile=profile,
                scenario=self.scenario,
                history=history,
                memories=memories,
                text=text,
                pcm=pcm,
            )
            async with aclosing(stream):
                async for event in stream:
                    if event["kind"] == "transcript" and learner_id:
                        with self.factory.begin() as db:
                            db.get(Turn, learner_id).text = event["text"][:4000]
                        await self.send(
                            "input.transcript", turn_id=learner_id, text=event["text"][:4000]
                        )
                    elif event["kind"] == "text":
                        response.text += event["text"]
                        if len(response.text) > 6000:
                            raise ModelError(
                                "invalid_model_output", "The tutor response was too long."
                            )
                        await self.send(
                            "response.text", response_id=response.id, text=event["text"]
                        )
                    elif event["kind"] == "audio":
                        while len(response.segments) - response.ack > 8:
                            response.changed.clear()
                            async with asyncio.timeout(60):
                                await response.changed.wait()
                        if len(response.segments) >= 512:
                            raise ModelError(
                                "invalid_model_output", "The tutor response was too long."
                            )
                        sequence = len(response.segments)
                        response.segments.append(event.get("text", ""))
                        await self.send("state", state="speaking")
                        await self.send(
                            "response.audio",
                            response_id=response.id,
                            sequence=sequence,
                            text=event.get("text", ""),
                            audio=base64.b64encode(wav_bytes(event["pcm"], 24000)).decode(),
                            mime_type="audio/wav",
                        )
            if self.scenario and learner_id:
                with self.factory() as db:
                    texts = list(
                        db.scalars(
                            select(Turn.text)
                            .where(
                                Turn.session_id == self.session_id,
                                Turn.role == "user",
                                Turn.text != "",
                            )
                            .order_by(Turn.created_at.desc())
                            .limit(20)
                        )
                    )
                indices = await self.engine.evaluate(self.scenario["goals"], texts)
                valid = [
                    i for i in indices if type(i) is int and 0 <= i < len(self.scenario["goals"])
                ]
                with self.factory.begin() as db:
                    session = db.get(TalkSession, self.session_id)
                    session.completed_goals = sorted(set(session.completed_goals) | set(valid))
                    progress = session.completed_goals
                await self.send("scenario.progress", completed_goals=progress)
        except asyncio.CancelledError:
            status = "cancelled"
        except ModelError as exc:
            status = "failed"
            await self.error(exc.code, exc.message, exc.retryable)
        except Exception:
            status = "failed"
            await self.error(
                "model_unavailable", "The tutor is temporarily unavailable. Please try again.", True
            )
        finally:
            response.status = status
            self.persist(response)
            with suppress(Exception):
                await self.send("response.done", response_id=response.id, status=status)
                if not response.segments or response.ack == len(response.segments) - 1:
                    await self.send("state", state="listening")

    async def cancel(self, response_id=None):
        response = self.response
        if (
            not response
            or (response_id and response_id != response.id)
            or response.status == "cancelled"
        ):
            return
        if response.task and not response.task.done():
            response.task.cancel()
            with suppress(asyncio.CancelledError):
                await response.task
        else:
            # Generation completion does not mean queued audio has been heard.
            if response.segments and response.ack != len(response.segments) - 1:
                response.status = "cancelled"
                self.persist(response)
                await self.send("response.done", response_id=response.id, status="cancelled")
        response.changed.set()

    async def ack(self, ack):
        response = self.response
        if not response or response.id != ack.response_id or response.status == "cancelled":
            return
        if ack.sequence <= response.ack:
            return
        if ack.sequence != response.ack + 1 or ack.sequence >= len(response.segments):
            raise HTTPException(
                422, "Playback acknowledgements must be ordered and refer to sent audio"
            )
        response.ack = ack.sequence
        response.changed.set()
        self.persist(response)
        if response.status != "generating" and response.ack == len(response.segments) - 1:
            await self.send("state", state="listening")

    async def handle(self, message):
        if message.get("bytes") is not None:
            if not self.session_id:
                raise HTTPException(409, "Start a session before sending audio")
            data = message["bytes"]
            if len(data) > 65536 or len(self.audio) + len(data) > MAX_PCM:
                self.audio.clear()
                raise HTTPException(
                    413, "Audio exceeds the 60-second turn limit or 64 KiB frame limit"
                )
            if not self.audio:
                await self.cancel()
                await self.send("state", state="listening")
            self.audio.extend(data)
            return
        raw = message.get("text", "")
        if len(raw.encode()) > 16384:
            raise HTTPException(413, "Message too large")
        obj = json.loads(raw)
        if not isinstance(obj, dict):
            raise HTTPException(422, "Expected a JSON object")
        kind = obj.get("type")
        if not isinstance(kind, str):
            raise HTTPException(422, "Expected a string message type")
        cls = {
            "session.start": schemas.Start,
            "text.input": schemas.TextInput,
            "response.cancel": schemas.Cancel,
            "playback.ack": schemas.Ack,
        }.get(kind, schemas.Simple)
        event = cls.model_validate(obj)
        if kind == "ping":
            await self.send("pong")
        elif kind == "session.start":
            await self.start(event)
        elif not self.session_id:
            raise HTTPException(409, "Start a session first")
        elif kind == "text.input":
            await self.begin(text=event.text)
        elif kind == "input.commit":
            data = bytes(self.audio)
            self.audio.clear()
            if not data or len(data) % 2:
                raise HTTPException(422, "Audio must contain complete PCM16 samples")
            await self.begin(pcm=data)
        elif kind == "input.cancel":
            self.audio.clear()
        elif kind == "response.cancel":
            if self.response and self.response.id == event.response_id:
                await self.cancel(event.response_id)
                await self.send("state", state="listening")
        elif kind == "playback.ack":
            await self.ack(event)
        elif kind == "session.end":
            await self.finish()
            await self.send("session.ended", session_id=self.session_id)
            await self.ws.close(code=1000)
            return False
        return True

    async def finish(self):
        self.audio.clear()
        if not self.session_id:
            return
        if self.heartbeat:
            self.heartbeat.cancel()
            with suppress(asyncio.CancelledError):
                await self.heartbeat
            self.heartbeat = None
        await self.cancel()
        try:
            self.charge()
        except HTTPException:
            return
        with self.factory.begin() as db:
            session = db.get(TalkSession, self.session_id)
            session.ended_at = now()
            enqueue_session(db, session, self.started)
            db.execute(
                update(User)
                .where(User.id == self.user_id, User.active_connection == self.connection_id)
                .values(active_connection=None, connection_until=0)
            )

    async def run(self):
        finished = False
        try:
            while True:
                async with asyncio.timeout(120):
                    message = await self.ws.receive()
                if message["type"] == "websocket.disconnect":
                    break
                if now() - self.message_window >= 1:
                    self.message_count, self.message_window = 0, now()
                self.message_count += 1
                if self.message_count > 120:
                    await self.error("rate_limit", "Too many messages.")
                    await self.ws.close(code=1008)
                    break
                try:
                    result = await self.handle(message)
                    if result is False:
                        finished = True
                        break
                except (ValidationError, json.JSONDecodeError, RecursionError):
                    await self.error("invalid_input", "Invalid message or input bounds.")
                except HTTPException as exc:
                    detail = str(exc.detail)
                    if "Session turn limit" in detail:
                        code = "session_full"
                        retryable = False
                    elif exc.status_code == 429:
                        code = "rate_limit"
                        retryable = "Daily practice limit" not in detail
                    else:
                        code = "invalid_input"
                        retryable = False
                    await self.send(
                        "input.rejected", code=code, message=detail, retryable=retryable
                    )
                    await self.error(code, detail, retryable=retryable)
                    if code != "session_full":
                        await self.send("state", state="listening")
        except (WebSocketDisconnect, TimeoutError, RuntimeError):
            pass
        except Exception:
            with suppress(Exception):
                await self.error(
                    "server_unavailable", "The practice service is temporarily unavailable.", True
                )
        finally:
            self.closed = True
            if not finished:
                with suppress(Exception):
                    await self.finish()
            with suppress(Exception):
                await self.ws.close(code=1000)
