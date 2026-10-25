import asyncio
import io
import json
import wave
from contextlib import asynccontextmanager
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import pytest
from conftest import register
from google.genai import types
from google.genai.live import AsyncSession

from lango.db import User
from lango.providers import GeminiEngine, ModelError, sentences, wav_bytes
from lango.schemas import profile


def learner(env):
    user = register(env)
    with env.db() as db:
        return profile(db.get(User, user.id))


def speech(pcm=b"\x00\x00" * 120, mime="audio/pcm;rate=24000"):
    return types.GenerateContentResponse(
        candidates=[
            types.Candidate(
                content=types.Content(
                    parts=[types.Part(inline_data=types.Blob(data=pcm, mime_type=mime))],
                )
            )
        ]
    )


def text_response(value):
    return types.GenerateContentResponse(
        candidates=[
            types.Candidate(
                content=types.Content(
                    parts=[types.Part(text=json.dumps(value))],
                )
            )
        ]
    )


class FakeStream:
    def __init__(self, chunks):
        self.chunks = iter(chunks)
        self.read = 0
        self.closed = False

    def __aiter__(self):
        return self

    async def __anext__(self):
        try:
            chunk = next(self.chunks)
        except StopIteration:
            raise StopAsyncIteration from None
        self.read += 1
        if isinstance(chunk, Exception):
            raise chunk
        return chunk

    async def aclose(self):
        self.closed = True


def stream_client(*streams):
    generate = AsyncMock(side_effect=streams)
    return SimpleNamespace(
        aio=SimpleNamespace(
            models=SimpleNamespace(generate_content_stream=generate), aclose=AsyncMock()
        ),
        close=Mock(),
    ), generate


def delta(text):
    return types.GenerateContentResponse(
        candidates=[types.Candidate(content=types.Content(parts=[types.Part(text=text)]))]
    )


async def test_cascade_audio_input_text_only_low_thinking_and_separate_tts(env):
    tutor = GeminiEngine(env.settings)
    text = FakeStream(
        [
            delta('{"transcript":"Hello tutor","reply":"Hello learner. '),
            delta('What do you enjoy?"}'),
        ]
    )
    client, generate = stream_client(text, FakeStream([speech()]), FakeStream([speech()]))
    events = []
    async for event in tutor.cascade(client, learner(env), None, [], [], None, b"\x00\x00" * 80):
        events.append(event)
        if event["kind"] == "audio" and len(events) == 3:
            assert text.read == 1 and not text.closed
    assert text.closed
    assert events[0] == {"kind": "transcript", "text": "Hello tutor"}
    assert [event["kind"] for event in events] == ["transcript", "text", "audio", "text", "audio"]
    request = generate.call_args_list[0].kwargs
    assert request["model"] == "gemini-3.8-flash"
    config = request["config"]
    assert config.response_modalities == [types.Modality.TEXT]
    assert config.thinking_config.thinking_level == types.ThinkingLevel.LOW
    blob = request["contents"][-1].parts[0].inline_data
    assert blob.mime_type == "audio/wav"
    with wave.open(io.BytesIO(blob.data)) as audio:
        assert audio.getframerate() == 16000
    tts = generate.call_args_list[1].kwargs
    assert tts["model"] == "gemini-3.8-flash-lite-tts"
    assert tts["config"].response_modalities == [types.Modality.AUDIO]
    assert tts["config"].speech_config.voice_config.prebuilt_voice_config.voice_name == "Kore"
    assert "completed_goals" not in tts["contents"]


@pytest.mark.parametrize(
    "response,code",
    [
        ({"transcript": "", "reply": "Hello."}, "no_speech"),
        ({"transcript": "Hi", "reply": "{metadata}"}, "invalid_model_output"),
        ({"unexpected": "value"}, "invalid_model_output"),
    ],
)
async def test_cascade_rejects_silence_and_structured_dialogue(env, response, code):
    stream = FakeStream([text_response(response)])
    client, generate = stream_client(stream)
    with pytest.raises(ModelError) as error:
        _ = [
            event
            async for event in GeminiEngine(env.settings).cascade(
                client, learner(env), None, [], [], None, b"\x00\x00"
            )
        ]
    assert error.value.code == code
    assert generate.call_count == 1 and stream.closed


async def test_bad_tts_audio_is_rejected(env):
    text, audio = (
        FakeStream([text_response({"transcript": "Hi", "reply": "Hello."})]),
        FakeStream([speech(mime="audio/mp3")]),
    )
    client, _ = stream_client(text, audio)
    with pytest.raises(ModelError, match="unsupported audio"):
        _ = [
            event
            async for event in GeminiEngine(env.settings).cascade(
                client, learner(env), None, [], [], "Hi", None
            )
        ]
    assert text.closed and audio.closed


@pytest.mark.parametrize("use_audio", [False, True])
async def test_live_manual_turn_history_transcriptions_and_audio(env, use_audio):
    import inspect

    sends = []

    class Session:
        async def send_client_content(self, **kwargs):
            inspect.signature(AsyncSession.send_client_content).bind(self, **kwargs)
            sends.append(("content", kwargs))

        async def send_realtime_input(self, **kwargs):
            inspect.signature(AsyncSession.send_realtime_input).bind(self, **kwargs)
            sends.append(("realtime", kwargs))

        async def receive(self):
            yield types.LiveServerMessage(
                server_content=types.LiveServerContent(
                    input_transcription=types.Transcription(text="I like tea."),
                    output_transcription=types.Transcription(text="Tea is lovely."),
                    model_turn=types.Content(
                        parts=[
                            types.Part(
                                inline_data=types.Blob(
                                    data=b"\x00\x00" * 14000, mime_type="audio/pcm;rate=24000"
                                )
                            )
                        ]
                    ),
                    turn_complete=True,
                )
            )

    connections = []

    @asynccontextmanager
    async def connect(**kwargs):
        connections.append(kwargs)
        yield Session()

    client = SimpleNamespace(aio=SimpleNamespace(live=SimpleNamespace(connect=connect)))
    history = [
        {"role": "user", "text": "Earlier words"},
        {"role": "assistant", "text": "Earlier answer"},
    ]
    events = [
        event
        async for event in GeminiEngine(env.settings).live(
            client,
            learner(env),
            None,
            history,
            [],
            None if use_audio else "I like tea.",
            b"\x00\x00" * 8000 if use_audio else None,
        )
    ]
    assert connections[0]["model"] == "gemini-3.8-live"
    assert connections[0]["config"].realtime_input_config.automatic_activity_detection.disabled
    assert sends[0][1]["turn_complete"] is False
    assert [item.role for item in sends[0][1]["turns"]] == ["user", "model"]
    if use_audio:
        assert sends[1][1]["activity_start"] == types.ActivityStart()
        assert sends[-1][1]["activity_end"] == types.ActivityEnd()
        assert sends[2][1]["audio"].mime_type == "audio/pcm;rate=16000"
    else:
        assert sends[-1][1]["turn_complete"] is True
    assert events[0] == {"kind": "transcript", "text": "I like tea."}
    assert events[1] == {"kind": "text", "text": "Tea is lovely."}
    assert sum(len(e["pcm"]) for e in events if e["kind"] == "audio") == 28000


async def test_provider_cancel_closes_stream_and_clients(env, monkeypatch):
    engine = GeminiEngine(env.settings)
    client = SimpleNamespace(aio=SimpleNamespace(aclose=AsyncMock()), close=Mock())
    closed = []

    async def stream(*args):
        try:
            yield {"kind": "text", "text": "Hello"}
            await asyncio.Event().wait()
        finally:
            closed.append(True)

    monkeypatch.setattr(engine, "client", lambda: client)
    monkeypatch.setattr(engine, "cascade", stream)
    generation = engine.generate(
        engine="cascade", profile={}, scenario=None, history=[], memories=[], text="Hi"
    )
    assert await anext(generation) == {"kind": "text", "text": "Hello"}
    await generation.aclose()
    assert closed == [True] and client.close.call_count == 1
    client.aio.aclose.assert_awaited_once()


async def test_goal_evidence_validation_and_text_config(env, monkeypatch):
    engine = GeminiEngine(env.settings)
    generate = AsyncMock(
        return_value=text_response(
            {
                "completed": [
                    {"goal": 0, "evidence": "a latte"},
                    {"goal": 1, "evidence": "invented"},
                    {"goal": 99, "evidence": "a latte"},
                ]
            }
        )
    )
    client = SimpleNamespace(
        aio=SimpleNamespace(models=SimpleNamespace(generate_content=generate), aclose=AsyncMock()),
        close=Mock(),
    )
    monkeypatch.setattr(engine, "client", lambda: client)
    assert await engine.evaluate(["Order", "Pay"], ["I would like a latte."]) == [0]
    assert generate.call_args.kwargs["config"].response_modalities == [types.Modality.TEXT]
    assert client.close.called


def test_wav_and_spoken_chunks_are_bounded():
    with pytest.raises(ModelError):
        wav_bytes(b"\x00", 16000)
    assert all(len(chunk) <= 240 for chunk in sentences("word " * 300))
    for text in ("", "x" * 4001, "completed_goals: 1", "Hello <tag>", '{"reply":"hi"}'):
        with pytest.raises(ModelError):
            sentences(text)


async def test_streamed_json_escapes_unicode_and_sentence_boundaries(env):
    reply = 'Say "hello" to Zoë 😀.\nWhat is your favorite café?'
    raw = json.dumps({"transcript": 'I said \\"hi\\".', "reply": reply})
    text = FakeStream([delta(char) for char in raw])
    audio = [FakeStream([speech()]), FakeStream([speech()])]
    client, calls = stream_client(text, *audio)
    events = []
    first_audio_at = None
    async for event in GeminiEngine(env.settings).cascade(
        client, learner(env), None, [], [], None, b"\x00\x00"
    ):
        events.append(event)
        if event["kind"] == "audio" and first_audio_at is None:
            first_audio_at = text.read
    assert first_audio_at < len(raw)
    assert [event["text"] for event in events if event["kind"] == "audio"] == [
        'Say "hello" to Zoë 😀.',
        "What is your favorite café?",
    ]
    captions = [event["text"] for event in events if event["kind"] == "text"]
    assert captions == ['Say "hello" to Zoë 😀. ', "What is your favorite café? "]
    assert all("transcript" not in call.kwargs["contents"] for call in calls.call_args_list[1:])
    assert text.closed and all(stream.closed for stream in audio)


async def test_audio_waits_for_complete_nonempty_transcript_even_if_reply_arrives_first(env):
    text = FakeStream(
        [delta('{"reply":"Hello. Next question?", "transcript":"I '), delta('like tea"}')]
    )
    client, calls = stream_client(text, FakeStream([speech()]), FakeStream([speech()]))
    async for event in GeminiEngine(env.settings).cascade(
        client, learner(env), None, [], [], None, b"\x00\x00"
    ):
        assert text.read == 2
        if event["kind"] == "audio":
            assert calls.call_count >= 2


@pytest.mark.parametrize(
    "raw",
    [
        '{"transcript":"Hi","reply":"unfinished',
        '{"transcript":"Hi","reply":"bad\\qescape"}',
        '{"transcript":"Hi","reply":"Hello", "reply":"Changed"}',
        '{"transcript":"Hi","reply":"Hello.","secret":"private-provider-details"}',
        '{"transcript":"Hi","reply":' + json.dumps("x" * 4001) + "}",
        " " * 65537,
    ],
)
async def test_streamed_json_malformed_bounded_and_sanitized(env, raw):
    text = FakeStream([delta(raw)])
    client, _ = stream_client(text)
    with pytest.raises(ModelError) as error:
        _ = [
            event
            async for event in GeminiEngine(env.settings).cascade(
                client, learner(env), None, [], [], "Hi", None
            )
        ]
    assert error.value.code == "invalid_model_output"
    assert "private-provider-details" not in str(error.value)
    assert text.closed


async def test_nonmonotone_duplicate_reply_is_rejected_after_early_audio(env):
    text = FakeStream(
        [delta('{"transcript":"Hi","reply":"Hello. '), delta('There", "reply":"replacement"}')]
    )
    client, _ = stream_client(text, FakeStream([speech()]))
    events = []
    with pytest.raises(ModelError):
        async for event in GeminiEngine(env.settings).cascade(
            client, learner(env), None, [], [], "Hi", None
        ):
            events.append(event)
    assert [event["text"] for event in events if event["kind"] == "audio"] == ["Hello."]
    assert text.closed


async def test_stream_cancel_after_first_audio_closes_text_tts_and_client(env, monkeypatch):
    text = FakeStream([delta('{"transcript":"Hi","reply":"Hello. '), delta('More."}')])
    audio = FakeStream([speech()])
    client, _ = stream_client(text, audio)
    engine = GeminiEngine(env.settings)
    monkeypatch.setattr(engine, "client", lambda: client)
    stream = engine.generate(
        engine="cascade", profile=learner(env), scenario=None, history=[], memories=[], text="Hi"
    )
    while (await anext(stream))["kind"] != "audio":
        pass
    assert text.read == 1
    await stream.aclose()
    assert text.closed and audio.closed
    client.aio.aclose.assert_awaited_once()
    client.close.assert_called_once()


async def test_cancel_during_tts_closes_both_upstream_streams(env, monkeypatch):
    waiting = asyncio.Event()

    class WaitingAudio(FakeStream):
        async def __anext__(self):
            waiting.set()
            await asyncio.Event().wait()

    text = FakeStream([delta('{"transcript":"Hi","reply":"Hello. '), delta('More."}')])
    audio = WaitingAudio([])
    client, _ = stream_client(text, audio)
    engine = GeminiEngine(env.settings)
    monkeypatch.setattr(engine, "client", lambda: client)

    async def consume():
        async for _ in engine.generate(
            engine="cascade",
            profile=learner(env),
            scenario=None,
            history=[],
            memories=[],
            text="Hi",
        ):
            pass

    task = asyncio.create_task(consume())
    await waiting.wait()
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert text.closed and audio.closed
    client.aio.aclose.assert_awaited_once()
    client.close.assert_called_once()


async def test_upstream_stream_error_is_sanitized_and_closed(env, monkeypatch):
    text = FakeStream([RuntimeError("private-provider-secret")])
    client, _ = stream_client(text)
    engine = GeminiEngine(env.settings)
    monkeypatch.setattr(engine, "client", lambda: client)
    with pytest.raises(ModelError) as error:
        _ = [
            event
            async for event in engine.generate(
                engine="cascade",
                profile=learner(env),
                scenario=None,
                history=[],
                memories=[],
                text="Hi",
            )
        ]
    assert "private-provider-secret" not in str(error.value)
    assert text.closed
    client.close.assert_called_once()


async def test_empty_text_chunks_and_fragmented_pcm_keep_sentence_ack_units(env):
    text = FakeStream(
        [
            types.GenerateContentResponse(),
            delta(" \n"),
            delta('{"transcript":"Hi","reply":"\\nHello'),
            delta("."),
            delta(" "),
            delta('Next?"}'),
        ]
    )
    pcm = [FakeStream([speech(b"\x01"), speech(b"\x02\x03\x04")]), FakeStream([speech()])]
    client, _ = stream_client(text, *pcm)
    events = []
    async for event in GeminiEngine(env.settings).cascade(
        client, learner(env), None, [], [], "Hi", None
    ):
        events.append(event)
        if event["kind"] == "audio" and event["text"] == "Hello.":
            assert text.read == 5
            assert event["pcm"] == b"\x01\x02\x03\x04"
    assert [event["text"] for event in events if event["kind"] == "audio"] == ["Hello.", "Next?"]


async def test_cancel_while_waiting_for_text_closes_stream_and_client(env, monkeypatch):
    waiting = asyncio.Event()

    class WaitingText(FakeStream):
        async def __anext__(self):
            waiting.set()
            await asyncio.Event().wait()

    text = WaitingText([])
    client, _ = stream_client(text)
    engine = GeminiEngine(env.settings)
    monkeypatch.setattr(engine, "client", lambda: client)
    stream = engine.generate(
        engine="cascade", profile=learner(env), scenario=None, history=[], memories=[], text="Hi"
    )
    task = asyncio.create_task(anext(stream))
    await waiting.wait()
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert text.closed
    client.aio.aclose.assert_awaited_once()
    client.close.assert_called_once()
