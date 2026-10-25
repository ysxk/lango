import hashlib
import hmac
import secrets

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import VerificationError
from fastapi import HTTPException
from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert

from lango.db import Invite, RateBucket, Refresh, Ticket, User, iso, now, uid

passwords = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=2)
DUMMY_HASH = passwords.hash(secrets.token_urlsafe(32))


def digest(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def verify_password(encoded: str, password: str) -> bool:
    try:
        return passwords.verify(encoded, password)
    except VerificationError:
        return False


def rate_limit(factory, settings, scope: str, identity: str, limit: int, seconds: int):
    key = hmac.new(
        settings.jwt_secret.get_secret_value().encode(),
        f"{scope}:{identity}:{int(now() // seconds)}".encode(),
        hashlib.sha256,
    ).hexdigest()
    with factory.begin() as db:
        insert = sqlite_insert if db.bind.dialect.name == "sqlite" else pg_insert
        statement = insert(RateBucket).values(key=key, count=1, until=now() + seconds)
        count = db.execute(
            statement.on_conflict_do_update(
                index_elements=[RateBucket.key], set_={"count": RateBucket.count + 1}
            ).returning(RateBucket.count)
        ).scalar_one()
    if count > limit:
        raise HTTPException(429, "Too many requests; try again later")


def issue_pair(db, settings, user_id: str, family: str | None = None):
    token = secrets.token_urlsafe(48)
    family = family or uid()
    db.add(
        Refresh(
            digest=digest(token),
            user_id=user_id,
            family=family,
            expires_at=now() + settings.refresh_days * 86400,
        )
    )
    access = jwt.encode(
        {
            "sub": user_id,
            "sid": family,
            "iat": int(now()),
            "exp": int(now()) + settings.access_minutes * 60,
            "iss": "lango",
            "aud": "lango-app",
            "typ": "access",
            "jti": uid(),
        },
        settings.jwt_secret.get_secret_value(),
        algorithm="HS256",
    )
    return {"access_token": access, "refresh_token": token, "token_type": "bearer"}


def authenticate(db, settings, token: str):
    try:
        claims = jwt.decode(
            token,
            settings.jwt_secret.get_secret_value(),
            algorithms=["HS256"],
            audience="lango-app",
            issuer="lango",
            options={"require": ["sub", "sid", "exp", "iat", "typ"]},
        )
        if claims["typ"] != "access":
            raise ValueError
        active = db.scalar(
            select(Refresh.digest)
            .where(
                Refresh.family == claims["sid"],
                Refresh.user_id == claims["sub"],
                Refresh.revoked.is_(False),
                Refresh.used.is_(False),
                Refresh.expires_at > now(),
            )
            .limit(1)
        )
        user = db.get(User, claims["sub"]) if active else None
        if user is None:
            raise ValueError
        return user
    except (jwt.PyJWTError, ValueError, TypeError, KeyError):
        raise HTTPException(401, "Authentication required") from None


def rotate(factory, settings, token: str):
    result = None
    with factory.begin() as db:
        row = db.get(Refresh, digest(token))
        if row and not row.revoked and row.expires_at > now():
            consumed = db.execute(
                update(Refresh)
                .where(
                    Refresh.digest == row.digest,
                    Refresh.used.is_(False),
                    Refresh.revoked.is_(False),
                )
                .values(used=True)
            ).rowcount
            if consumed:
                result = issue_pair(db, settings, row.user_id, row.family)
            else:
                db.execute(update(Refresh).where(Refresh.family == row.family).values(revoked=True))
    if result is None:
        raise HTTPException(401, "Refresh token is invalid or expired")
    return result


def create_invite(db, max_uses=1, hours=72):
    code = secrets.token_urlsafe(24)
    expires = now() + hours * 3600
    db.add(Invite(digest=digest(code), max_uses=max_uses, uses=0, expires_at=expires))
    return {"code": code, "max_uses": max_uses, "uses": 0, "expires_at": iso(expires)}


def consume_ticket(factory, token):
    if not token or not 20 <= len(token) <= 128:
        return None
    with factory.begin() as db:
        return db.execute(
            update(Ticket)
            .where(
                Ticket.digest == digest(token),
                Ticket.used.is_(False),
                Ticket.expires_at > now(),
            )
            .values(used=True)
            .returning(Ticket.user_id)
        ).scalar_one_or_none()
