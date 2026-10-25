# Lango API contract v1

All REST paths start with `/api/v1`, return JSON, and use `Authorization: Bearer <access_token>` except health, login, refresh and register. Errors use `{detail: string}`. IDs are opaque strings. Dates are UTC ISO-8601. No provider credentials or model IDs are sent to clients.

## REST

- `GET /healthz` → `{status:"ok"}` (outside prefix).
- `POST /auth/register` `{email,password,display_name,invite_code}` → TokenPair.
- `POST /auth/login` `{email,password}` → TokenPair.
- `POST /auth/refresh` `{refresh_token}` → rotated TokenPair.
- `POST /auth/logout` `{refresh_token}` → `{ok:true}`.
- TokenPair: `{access_token,refresh_token,token_type:"bearer"}`.
- `GET /me` → Profile.
- `PATCH /me` accepts mutable Profile fields → Profile.
- Profile: `{id,email,display_name,native_language:"zh",target_language:"en",level:"A2",goal:"",interests:"",voice:"Kore",speech_rate:1.0,memory_enabled:true,onboarding_completed:false,is_admin:false}`.
- `GET /config` → `{voices:[{id,name,accent}],engines:[{id,name}],default_engine,limits:{daily_minutes:60}}`. Engine IDs are product aliases (`cascade`,`live`), not provider model names.
- `GET /scenarios` → array of `{id,title,subtitle,level,category,ai_role,learner_role,setting,goals:[string],opening_line,useful_phrases:[string]}`.
- `GET /sessions` → array of `{id,title,scenario_id,started_at,ended_at,duration_seconds,engine}` newest first, bounded to 100.
- `GET /sessions/{id}` → session fields plus `turns:[{id,role,text,created_at,interrupted}]`, `completed_goals:[int]`.
- `GET /memories` → `{items:[{id,memory,created_at}],enabled:bool}`.
- `PATCH /me {memory_enabled:false}` pauses memory retrieval and ingestion without deleting saved facts; management listing and explicit deletion remain available. Toggling invalidates queued/in-flight ingestion. Re-enabling rebuilds from retained facts and does not ingest conversations from the paused period.
- `DELETE /memories/{id}` → `{ok:true}`.
- `DELETE /memories` → `{ok:true}`. Also invalidates queued/in-flight ingestion so forgotten facts cannot be resurrected.
- `POST /admin/invites` `{max_uses:1}` → `{code,max_uses,uses,expires_at}`. Admin only.
- `GET /usage` → `{today_seconds,daily_limit_seconds,sessions_count}`.
- `POST /talk/ticket` → `{ticket,expires_in:30}`. Short-lived single-use ticket bound to user. It is NOT an access token.


Every JSON event has a `type` discriminator, for example `{"type":"text.input","text":"Hello"}`. The event names below are values of `type`.
## WebSocket

`/api/v1/talk?ticket=<single-use-ticket>`; redact query strings from access logging. Origin allowlist enforced when supplied by browser. Authenticate and consume ticket before accepting. Refresh auth and obtain a new ticket for every connection; never place access/refresh tokens in URLs.

Client JSON:
- `session.start {scenario_id?:string,engine?:"cascade"|"live",session_id?:string,mode:"ptt"|"hands_free"|"half_duplex"}`. Resume only own sessions. Server reconstructs persisted text history. Never replay old audio. Start must precede audio/text.
  New sessions automatically generate a short opening response; resumed sessions do not. A learner input may interrupt that opening normally. Correlate response events by `response_id`, including cancellation completion events from the previous response.
- `input.commit`: finish accumulated PCM audio and generate a response.
- `input.cancel`: discard accumulated microphone audio.
- `text.input {text}`: send a typed learner turn (also available when microphone permission denied).
- `response.cancel {response_id}`: explicit interruption; cancel upstream generation and discard queued playback.
- `playback.ack {response_id,sequence}`: sent AFTER this entire audio segment was played, used for persisting heard assistant content.
- `session.end`: persist and enqueue memory job; close gracefully.
- `ping` → `pong`.

Client binary: raw mono signed little-endian PCM16 at 16000 Hz. Only current learner turn, maximum 60 seconds. Client keeps a short pre-roll for voice activity detection. No raw audio is stored on disk.

Server JSON:
- `session.created {session_id,audio:{input_rate:16000,output_rate:24000}}`.
- `state {state:"listening"|"thinking"|"speaking"}`.
- `input.transcript {text}`.
- `response.started {response_id}`.
- `response.text {response_id,text}`: text delta; append for captions.
- `response.audio {response_id,sequence,text,audio,mime_type:"audio/wav"}`: independent playable WAV segment, base64 encoded. Ordered monotonically from sequence 0. `text` is the phrase corresponding to this segment; may be empty for native audio fragments. Player must ignore frames from cancelled responses and acknowledge completed segments only. Queue playback; do not overlap clips.
- `scenario.progress {completed_goals:[int]}` (zero-based validated goal indices).
- `response.done {response_id,status:"completed"|"cancelled"|"failed"}` means generation is done; client remains speaking while audio queue drains. Assistant history is finalized using playback acknowledgements, not just generation completion.
- `error {code,message,retryable}`: human-readable, never include raw provider errors, tokens or credentials.
- `session.ended {session_id}`.
- `pong`.

A new input turn interrupts any current response. Aborted upstream streams must be closed. Interrupted assistant content is limited to confirmed played segments. For text-only turns with no audio produced, complete assistant text may be retained. Client lifecycle/background pauses microphone and cancels playback. Reconnection requires a fresh ticket and an owned session ID; an uncommitted microphone recording is discarded, never retried automatically.

## Deployment and safety

Development may bind loopback with SQLite; Docker uses PostgreSQL + pgvector and a separate durable memory worker. Production requires TLS and explicit CORS/WS origins. LAN HTTP is supported only on trusted networks (Android user-configured server); document exposure and prefer HTTPS. Passwords are Argon2 hashed, refresh tokens hashed at rest and rotated. Registration requires an expiring invitation. Bootstrap admin uses a server CLI with password prompt. Rate limits and bounded audio/text input are mandatory. Memory operations are always scoped to authenticated user IDs; role-play dialogue is not treated as real personal biography.
