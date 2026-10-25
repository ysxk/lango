# Lango server

Python 3.12 / FastAPI backend implementing [`../docs/protocol.md`](../docs/protocol.md).
The application uses real Gemini and Mem0 integrations. Fake providers exist only in tests;
there is no demo-model fallback in the running server.

## Local development

Install [uv](https://docs.astral.sh/uv/), then run from `server/`:

```sh
uv sync --frozen
export LANGO_JWT_SECRET="$(uv run python -c 'import secrets; print(secrets.token_urlsafe(48))')"
export LANGO_ALLOWED_ORIGINS='["http://localhost:8081","http://localhost:8082"]'
uv run python -m lango.migrate
uv run lango create-admin --email admin@example.com --display-name Administrator
uv run lango invite --email admin@example.com --max-uses 1 --hours 72
uv run python -m lango.main
```

Admin creation prompts twice for a password; invitation creation authenticates the admin
using a hidden password prompt. Passwords must contain 10–128 characters; there are no
default credentials. The invitation command prints its code once. An admin can also use
`POST /api/v1/admin/invites` after logging in. Invitations expire (72 hours by default), are
hashed in the database, and are consumed atomically during registration.

Keep the generated JWT secret stable across API, worker, and CLI processes/restarts.
The example's exported variables apply only to that shell; persist secrets through your
service manager or secret store, never source control. No `.env` file is loaded automatically.

The default API address is `http://127.0.0.1:8000`; `GET /healthz` verifies database connectivity.
`/docs` is available in development. A separate worker is required to extract or physically
purge long-term vector memories; run it with the **same environment** in another terminal:

```sh
uv run python -m lango.worker
```

The API and CLI fail with an actionable migration message if the schema is not current.
Migrations are explicit and idempotent; API startup does not silently create/alter tables.

### Configure inference

Provision a **new, private** Gemini API key with access to the configured models. Set it as
`LANGO_GOOGLE_API_KEY` in the service environment and restart the API and worker. Never paste
it into a URL, client configuration, application logs, or this repository. Do not reuse an
exposed key. No key is needed for migrations, bootstrap, authentication, history, or health;
inference without one returns a sanitized, actionable `model_not_configured` WebSocket error.
Provider failures never fall back to fabricated responses.

- **cascade**: native 16 kHz audio input (or typed text) to `gemini-3.8-flash`, requesting
  **TEXT only**, structured transcript/reply, and **LOW** thinking (not unsupported minimal).
  The structured text response is streamed and incrementally JSON-decoded: only the monotone
  `reply` string enters sentence splitting and `gemini-3.8-flash-lite-tts`. The first complete
  sentence can produce audio before later text chunks arrive; audio input must first have a
  completed, nonempty transcript. JSON escapes/Unicode may span chunks. Text is capped at
  4000 characters per field and 64 KiB encoded JSON; the final document is schema-validated.
  TTS also streams, buffering only one bounded phrase into an independent WAV acknowledgement
  unit. Cancellation closes both upstream streams and clients. Structured metadata is not spoken.
- **live**: `gemini-3.8-live` with native audio output, input/output transcription, and
  automatic activity detection disabled. Each committed learner turn uses explicit activity
  start/end markers (typed input uses a completed client-content turn). Persisted **text**
  history is reconstructed on each upstream connection; old audio is never replayed.
- Scenario goal evaluation is a separate structured text request. Only valid goal indices
  backed by an exact learner quote are accepted, never metadata embedded in spoken dialogue.

Model availability, regional access, quota, billing, and voice support must be checked with
your own fresh credential. The automated tests do not call Google's paid endpoints.

## Environment

All settings use the `LANGO_` prefix. Paths are relative to the process working directory.

| Variable | Default / requirement |
| --- | --- |
| `ENVIRONMENT` | `development`; `production` enables strict deployment checks and disables API docs |
| `JWT_SECRET` | Required, at least 32 characters; use a cryptographically random secret |
| `DATABASE_URL` | `sqlite:///./data/lango.db`; production requires `postgresql+psycopg://...` |
| `ALLOWED_ORIGINS` | JSON array, default `[]`; exact browser origins, no wildcard; production requires explicit HTTPS origins |
| `GOOGLE_API_KEY` | Optional for startup; required for actual Gemini inference and Mem0 extraction/embeddings |
| `TEXT_MODEL` | `gemini-3.8-flash` |
| `TTS_MODEL` | `gemini-3.8-flash-lite-tts` |
| `LIVE_MODEL` | `gemini-3.8-live` |
| `EMBEDDING_MODEL` | `gemini-embedding-001`, configured for 768-dimensional vectors |
| `DEFAULT_ENGINE` | `cascade` (or `live`); clients see product aliases, never model IDs |
| `ACCESS_MINUTES` / `REFRESH_DAYS` | `15` / `30`; bounded to 1–60 / 1–90 |
| `DAILY_MINUTES` | `60`, bounded to 1–1440; counts connected practice time, not only provider audio |
| `PROVIDER_TIMEOUT_SECONDS` | `120`, bounded to 10–300; Gemini turn timeout and Mem0 transport timeout |
| `MEMORY_PATH` | `./data/memory`; local vector persistence and single-worker lock |
| `MEMORY_POSTGRES_URL` | Required in production: native psycopg DSN such as `postgresql://user:password@db/lango` (**no** `+psycopg`) |
| `MEMORY_QDRANT_URL` / `MEMORY_QDRANT_API_KEY` | Optional development-only remote Qdrant instead of local vectors; not a substitute for production pgvector |
| `WORKER_POLL_SECONDS` | `2.0`, bounded to 0.1–60 |
| `WORKER_LEASE_SECONDS` | `600`, at least twice the provider timeout and at most 3600 |

All model IDs are server-side and environment-configurable. Different models must support
the requested modalities, structured-output/thinking settings, and audio format. Changing
embedding dimensions or models against an existing vector collection requires an explicit
operator-managed rebuild; the server does not mix incompatible embeddings.

## Production operations

Use PostgreSQL with the `vector` extension installed (`CREATE EXTENSION IF NOT EXISTS vector`)
and a dedicated database/account. Mem0 creates its `lango_memories` vector table/indexes;
the worker's database role must have the necessary table/index permissions. Set both
`LANGO_DATABASE_URL` and `LANGO_MEMORY_POSTGRES_URL`. Run migrations once before the API and
worker. Run exactly one memory worker: PostgreSQL advisory locking (or a local file lock
in development) rejects duplicate worker processes. Jobs survive API/worker restarts,
have renewable leases, retry with bounded exponential backoff, and expose no raw provider
error text in job status/logging. Keep the worker's memory path persistent for its lock;
production facts themselves persist in PostgreSQL/pgvector.

An ASGI deployment command, behind a trusted TLS reverse proxy, is:

```sh
uv run uvicorn lango.main:app --host 0.0.0.0 --port 8000 \
  --no-access-log --ws-max-size 65536 --ws-max-queue 16
```

Do not expose this plain HTTP listener to the public Internet. Enforce HTTPS/WSS at the
proxy, allow WebSocket upgrades, bound request bodies, and use sufficiently long WebSocket
idle timeouts. Configure proxy access logging to **omit query strings** (tickets are URL
credentials); application access logging is disabled and SDK/provider logs are suppressed.
Only trust forwarded client addresses from your actual proxy. Configure exact browser
origins including any nonstandard port; WebSocket origins are checked even for same-origin
browser deployments. Native clients without `Origin` are allowed but still require a ticket.
LAN HTTP is suitable only on explicitly trusted networks; it exposes credentials/audio
in transit and browser microphone APIs may require HTTPS. Prefer TLS.

Back up the relational database and local dev vector directory consistently; restrict data
and secret-file permissions. Memory deletion is not erasure of separately retained session
history or operator backups. No raw microphone audio is written to disk. Do not enable SDK
HTTP debugging, SQL echo, request-body dumps, or proxy query logging.

## Conversation and privacy guarantees

- Access JWTs require an active refresh-token family. Refresh tokens are SHA-256 hashed,
  single-use, rotated, and replay revokes that family; logout revokes the supplied owned
  family. Passwords use Argon2id. Auth/IP/account rate limits are database-backed.
- REST profile/history/memory access and session resumption are user-scoped. `/config` is
  authenticated like the shared contract and exposes only public voice/engine choices and
  limits, never provider credentials or model names. Twelve complete role-play scenarios
  are available.
- WebSocket admission consumes an expiring **one-use database ticket before accept**.
  One active practice connection per user is enforced with a renewable DB lease. Obtain a
  fresh ticket for every reconnect and resume using your owned session ID.
- `session.start` precedes audio/text. Input PCM is mono signed little-endian PCM16 at
  16000 Hz, at most 60 seconds per turn and 64 KiB per binary message. JSON messages are
  at most 16 KiB, typed learner text at most 4000 characters, and REST bodies at most 32 KiB.
  Sessions are capped at 400 persisted turn rows; provider context is the latest 40 turns.
- New input and explicit response cancellation close upstream generation. `input.cancel`
  discards uncommitted microphone input. Clients must stop recording/playback on backgrounding,
  ignore cancelled response IDs, and acknowledge **only fully played segments** in order.
  Output segments are independently playable mono 24 kHz WAV files with sequence numbers
  starting at zero. At most eight unacknowledged segments are produced before backpressure;
  stalled playback times out rather than accumulating unbounded audio.
- `response.done` describes generation, not playback completion. Cascade assistant history
  includes only acknowledged phrase segments. Native Live output has no reliable per-word
  alignment: its full transcription is retained only once **all** audio is acknowledged;
  an interrupted partially heard Live response is conservatively omitted from text history.
  A completed genuinely text-only response may be retained without playback acknowledgements.
- SQL memory projection is immediately revoked by epoch changes. Deletion clears pending
  old ingestion payloads; stale in-flight writes cannot enter the projection and are purged.
  Deleting a single fact rebuilds surviving facts under a new namespace without re-inferring
  deleted facts. Turning memory off **pauses** tutor retrieval and new extraction; it does not
  delete saved facts. Saved items remain visible/manageable in `/memories` while disabled.
  Both pause and resume rotate epochs and invalidate old queued/in-flight extraction; resume
  rebuilds the preserved SQL facts in a new vector namespace. Utterances from before resume,
  including those spoken while paused, cannot be retroactively ingested. Only explicit
  `DELETE /memories` or `DELETE /memories/{id}` forgets saved facts. Physical old-namespace
  purge/rebuild is asynchronous and requires the worker.
- Only real, non-role-play learner utterances enter Mem0 extraction. Scenario sessions are
  excluded entirely. Extraction instructions reject fictional examples, inferred biography,
  credentials, and sensitive personal data; extraction remains AI-based, not a perfect PII
  classifier. Mem0's redundant raw-message/change archive is **in-memory only**; durable
  facts are stored in the SQL projection and persistent vector store.

## Tests and validation

From `server/`:

```sh
uv sync --frozen
uv run ruff check lango tests
uv run ruff format --check lango tests
uv run pytest -q
```

Tests inject fake tutor/memory providers and mock Gemini requests using the installed
`google-genai==2.33.0` types/signatures. They cover auth/refresh replay/concurrent rotation,
invitations, profiles, ownership/resumption, ticket replay, input bounds, WAV sequencing,
playback-confirmed history, quota, sanitized failures, scenario/role-play behavior, durable
job leases/retries, memory deletion, and pause/resume preservation. Stream-specific tests
prove first audio precedes the last text chunk, escaped JSON/Unicode survives chunk boundaries,
malformed/oversized output fails safely, and cancellation closes text/TTS/client resources.
An actual `mem0ai==2.2.1` + local Qdrant persistence round-trip uses **fake embeddings and no
network or real API key**. Migration, CLI prompt, logging, and no-provider-key ASGI startup
checks are included.

These offline tests do **not** certify paid model availability/audio quality, real-device
microphone/playback behavior, TLS proxy configuration, or a live PostgreSQL/pgvector
installation. Verify those integration paths in your own deployment with newly provisioned
credentials; never use an exposed key for testing.
