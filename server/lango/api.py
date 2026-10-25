import secrets
from contextlib import asynccontextmanager
from typing import Annotated

from fastapi import APIRouter, Depends, FastAPI, HTTPException, Request, WebSocket
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import func, select, text, update
from sqlalchemy.exc import IntegrityError, SQLAlchemyError

from lango import schemas
from lango.config import VOICES, Settings
from lango.db import (
    Invite,
    MemoryItem,
    TalkSession,
    Ticket,
    Turn,
    Usage,
    User,
    iso,
    make_database,
    now,
)
from lango.logging import safe_logging
from lango.memory import forget, set_memory_enabled
from lango.providers import GeminiEngine
from lango.scenarios import SCENARIOS
from lango.security import (
    DUMMY_HASH,
    authenticate,
    consume_ticket,
    create_invite,
    digest,
    issue_pair,
    passwords,
    rate_limit,
    revoke_family,
    rotate,
    verify_password,
)
from lango.talk import Actor, today


def session_view(row):
    return {
        "id": row.id,
        "title": row.title,
        "scenario_id": row.scenario_id,
        "started_at": iso(row.started_at),
        "ended_at": iso(row.ended_at),
        "duration_seconds": int(row.duration_seconds),
        "engine": row.engine,
    }


def create_app(settings: Settings | None = None, *, engine=None, database=None):
    safe_logging()
    settings = settings or Settings()
    sql_engine, factory = database or make_database(settings)

    @asynccontextmanager
    async def lifespan(app):
        from lango.migrate import check_schema

        check_schema(sql_engine)
        yield
        sql_engine.dispose()

    app = FastAPI(
        title="Lango",
        version="1.0.0",
        lifespan=lifespan,
        docs_url=None if settings.environment == "production" else "/docs",
        redoc_url=None,
        openapi_url=None if settings.environment == "production" else "/openapi.json",
    )
    app.state.settings, app.state.db = settings, factory
    app.state.tutor = engine or GeminiEngine(settings)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins,
        allow_credentials=False,
        allow_methods=["GET", "POST", "PATCH", "DELETE"],
        allow_headers=["Authorization", "Content-Type"],
    )

    @app.middleware("http")
    async def boundaries(request: Request, call_next):
        if request.url.path != "/healthz":
            try:
                rate_limit(
                    factory,
                    settings,
                    "http",
                    request.client.host if request.client else "unknown",
                    300,
                    60,
                )
            except HTTPException as exc:
                return JSONResponse({"detail": exc.detail}, status_code=exc.status_code)
        if request.method in ("POST", "PATCH"):
            body = bytearray()
            async for piece in request.stream():
                body.extend(piece)
                if len(body) > 32768:
                    return JSONResponse({"detail": "Request body exceeds 32 KiB"}, status_code=413)
            request._body = bytes(body)
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response

    @app.exception_handler(RequestValidationError)
    async def invalid_input(request, exc):
        return JSONResponse({"detail": "Invalid request fields or input bounds"}, status_code=422)

    @app.exception_handler(SQLAlchemyError)
    async def database_error(request, exc):
        return JSONResponse({"detail": "Database temporarily unavailable"}, status_code=503)

    @app.exception_handler(Exception)
    async def internal_error(request, exc):
        return JSONResponse({"detail": "Internal operation failed"}, status_code=500)

    bearer = HTTPBearer(auto_error=False)

    def current(credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)]):
        if credentials is None or len(credentials.credentials) > 2048:
            raise HTTPException(401, "Authentication required")
        with factory() as db:
            return authenticate(db, settings, credentials.credentials)

    AuthUser = Annotated[User, Depends(current)]
    router = APIRouter(prefix="/api/v1")

    @app.get("/healthz")
    def health():
        with factory() as db:
            db.execute(text("SELECT 1"))
        return {"status": "ok"}

    def auth_limit(request, email=""):
        address = request.client.host if request.client else "unknown"
        rate_limit(factory, settings, "auth-ip", address, 20, 60)
        if email:
            rate_limit(factory, settings, "auth-email", email.lower(), 10, 60)

    @router.post("/auth/register")
    def register(body: schemas.Register, request: Request):
        auth_limit(request, str(body.email))
        encoded = passwords.hash(body.password.get_secret_value())
        try:
            with factory.begin() as db:
                accepted = db.execute(
                    update(Invite)
                    .where(
                        Invite.digest == digest(body.invite_code),
                        Invite.expires_at > now(),
                        Invite.uses < Invite.max_uses,
                    )
                    .values(uses=Invite.uses + 1)
                ).rowcount
                if not accepted:
                    raise HTTPException(400, "Invitation is invalid, expired or exhausted")
                user = User(
                    email=str(body.email).lower(),
                    password_hash=encoded,
                    display_name=body.display_name,
                )
                db.add(user)
                db.flush()
                pair = issue_pair(db, settings, user.id)
            return pair
        except IntegrityError:
            raise HTTPException(409, "Account could not be registered") from None

    @router.post("/auth/login")
    def login(body: schemas.Login, request: Request):
        auth_limit(request, str(body.email))
        with factory.begin() as db:
            user = db.scalar(select(User).where(User.email == str(body.email).lower()))
            valid = verify_password(
                user.password_hash if user else DUMMY_HASH, body.password.get_secret_value()
            )
            if not user or not valid:
                raise HTTPException(401, "Invalid email or password")
            return issue_pair(db, settings, user.id)

    @router.post("/auth/refresh")
    def refresh(body: schemas.RefreshBody, request: Request):
        auth_limit(request)
        return rotate(factory, settings, body.refresh_token)

    @router.post("/auth/logout")
    def logout(body: schemas.RefreshBody, request: Request):
        auth_limit(request)
        revoke_family(factory, body.refresh_token)
        return {"ok": True}

    @router.get("/me")
    def me(user: AuthUser):
        return schemas.profile(user)

    @router.patch("/me")
    def patch_me(body: schemas.ProfilePatch, user: AuthUser):
        with factory.begin() as db:
            row = db.get(User, user.id)
            changes = body.model_dump(exclude_unset=True)
            if "memory_enabled" in changes:
                set_memory_enabled(db, user.id, changes.pop("memory_enabled"))
                row = db.get(User, user.id, populate_existing=True)
            for key, value in changes.items():
                setattr(row, key, value)
            db.flush()
            return schemas.profile(row)

    @router.get("/config")
    def config(user: AuthUser):
        return {
            "voices": [{"id": v, "name": v, "accent": "English"} for v in VOICES],
            "engines": [
                {"id": "cascade", "name": "Standard voice"},
                {"id": "live", "name": "Live voice"},
            ],
            "default_engine": settings.default_engine,
            "limits": {"daily_minutes": settings.daily_minutes},
        }

    @router.get("/scenarios")
    def scenarios(user: AuthUser):
        return SCENARIOS

    @router.get("/sessions")
    def sessions(user: AuthUser):
        with factory() as db:
            return [
                session_view(s)
                for s in db.scalars(
                    select(TalkSession)
                    .where(
                        TalkSession.user_id == user.id,
                    )
                    .order_by(TalkSession.started_at.desc())
                    .limit(100)
                )
            ]

    @router.get("/sessions/{session_id}")
    def session_detail(session_id: str, user: AuthUser):
        if len(session_id) > 80:
            raise HTTPException(404, "Session not found")
        with factory() as db:
            row = db.get(TalkSession, session_id)
            if not row or row.user_id != user.id:
                raise HTTPException(404, "Session not found")
            turns = db.scalars(
                select(Turn)
                .where(Turn.session_id == row.id, Turn.text != "")
                .order_by(Turn.created_at, Turn.id)
                .limit(402)
            )
            return session_view(row) | {
                "completed_goals": row.completed_goals,
                "turns": [
                    {
                        "id": t.id,
                        "role": t.role,
                        "text": t.text,
                        "created_at": iso(t.created_at),
                        "interrupted": t.interrupted,
                    }
                    for t in turns
                ],
            }

    @router.get("/memories")
    def memories(user: AuthUser):
        with factory() as db:
            return {
                "enabled": user.memory_enabled,
                "items": [
                    {"id": row.id, "memory": row.memory, "created_at": iso(row.created_at)}
                    for row in db.scalars(
                        select(MemoryItem)
                        .where(
                            MemoryItem.user_id == user.id,
                            MemoryItem.epoch == user.memory_epoch,
                        )
                        .order_by(MemoryItem.created_at.desc())
                        .limit(500)
                    )
                ],
            }

    @router.delete("/memories")
    def forget_all(user: AuthUser):
        with factory.begin() as db:
            forget(db, user.id)
        return {"ok": True}

    @router.delete("/memories/{memory_id}")
    def forget_one(memory_id: str, user: AuthUser):
        with factory.begin() as db:
            row = db.get(MemoryItem, memory_id) if len(memory_id) <= 64 else None
            if not row or row.user_id != user.id:
                raise HTTPException(404, "Memory not found")
            forget(db, user.id, memory_id)
        return {"ok": True}

    @router.post("/admin/invites")
    def invites(body: schemas.InviteBody, user: AuthUser):
        if not user.is_admin:
            raise HTTPException(403, "Administrator permission required")
        rate_limit(factory, settings, "invite", user.id, 30, 3600)
        with factory.begin() as db:
            return create_invite(db, body.max_uses)

    @router.get("/usage")
    def usage(user: AuthUser):
        with factory() as db:
            row = db.get(Usage, (user.id, today()))
            day_start = int(now() // 86400) * 86400
            count = db.scalar(
                select(func.count())
                .select_from(TalkSession)
                .where(
                    TalkSession.user_id == user.id,
                    TalkSession.started_at >= day_start,
                )
            )
            return {
                "today_seconds": int(row.seconds) if row else 0,
                "daily_limit_seconds": settings.daily_minutes * 60,
                "sessions_count": count,
            }

    @router.post("/talk/ticket")
    def ticket(user: AuthUser):
        rate_limit(factory, settings, "ticket", user.id, 20, 60)
        token = secrets.token_urlsafe(32)
        with factory.begin() as db:
            db.add(Ticket(digest=digest(token), user_id=user.id, expires_at=now() + 30))
        return {"ticket": token, "expires_in": 30}

    @router.websocket("/talk")
    async def talk(ws: WebSocket):
        origin = ws.headers.get("origin")
        if origin is not None and origin not in settings.allowed_origins:
            await ws.close(code=1008)
            return
        user_id = consume_ticket(factory, ws.query_params.get("ticket"))
        if not user_id:
            await ws.close(code=1008)
            return
        try:
            rate_limit(factory, settings, "ws", user_id, 20, 60)
        except HTTPException:
            await ws.close(code=1008)
            return
        await ws.accept()
        await Actor(ws, user_id, factory, settings, app.state.tutor).run()

    app.include_router(router)
    return app
