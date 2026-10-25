import logging
import signal
import threading
import time
from contextlib import contextmanager
from pathlib import Path

from sqlalchemy import delete, or_, select, text, update
from sqlalchemy.orm import aliased

from lango.config import Settings
from lango.db import (
    MemoryItem,
    MemoryJob,
    RateBucket,
    Refresh,
    Ticket,
    User,
    make_database,
    now,
    uid,
)
from lango.memory import MAX_MEMORIES, Mem0Store, namespace
from lango.migrate import check_schema

log = logging.getLogger("lango.worker")


class Worker:
    def __init__(self, factory, settings, store=None):
        self.factory, self.settings = factory, settings
        self.store = store or Mem0Store(settings)

    def claim(self):
        rebuild = aliased(MemoryJob)
        with self.factory.begin() as db:
            candidate = db.scalar(
                select(MemoryJob.id)
                .where(
                    or_(
                        MemoryJob.status == "pending",
                        (MemoryJob.status == "running") & (MemoryJob.lease_until < now()),
                    ),
                    MemoryJob.available_at <= now(),
                    # Preserve surviving facts until their new namespace has been rebuilt.
                    or_(
                        MemoryJob.kind != "ingest",
                        ~select(rebuild.id)
                        .where(
                            rebuild.user_id == MemoryJob.user_id,
                            rebuild.epoch == MemoryJob.epoch,
                            rebuild.kind == "rebuild",
                            rebuild.status != "done",
                        )
                        .exists(),
                    ),
                )
                .order_by(MemoryJob.available_at, MemoryJob.id)
                .limit(1)
            )
            if candidate is None:
                return None
            token = uid()
            row = db.execute(
                update(MemoryJob)
                .where(
                    MemoryJob.id == candidate,
                    or_(
                        MemoryJob.status == "pending",
                        (MemoryJob.status == "running") & (MemoryJob.lease_until < now()),
                    ),
                )
                .values(
                    status="running",
                    lease_until=now() + self.settings.worker_lease_seconds,
                    lease_token=token,
                    attempts=MemoryJob.attempts + 1,
                )
                .returning(MemoryJob.id)
            ).scalar_one_or_none()
            return db.get(MemoryJob, row) if row else None

    def current(self, job):
        with self.factory() as db:
            user = db.get(User, job.user_id)
            return user is not None and user.memory_enabled and user.memory_epoch == job.epoch

    def process(self, job):
        scope = namespace(job.user_id, job.epoch)
        if job.kind == "purge" or not self.current(job):
            self.store.purge(scope)
            self.finish(job)
            return
        if job.kind == "rebuild":
            facts = job.payload.get("facts", [])
            if facts:
                self.store.add(
                    scope, [{"role": "user", "content": fact} for fact in facts], infer=False
                )
        else:
            messages = job.payload.get("messages", [])
            if messages:
                self.store.add(scope, messages)
        rows = self.store.list(scope)
        stale = False
        with self.factory.begin() as db:
            # Conditional write acquires the same row lock as forgetting, including on SQLite.
            locked = db.execute(
                update(User)
                .where(
                    User.id == job.user_id,
                    User.memory_epoch == job.epoch,
                    User.memory_enabled.is_(True),
                )
                .values(memory_epoch=User.memory_epoch)
            ).rowcount
            live = db.get(MemoryJob, job.id)
            if not locked or not live or live.lease_token != job.lease_token:
                stale = True
            else:
                db.execute(delete(MemoryItem).where(MemoryItem.user_id == job.user_id))
                for row in rows[:MAX_MEMORIES]:
                    if row.get("user_id") != scope or not isinstance(row.get("memory"), str):
                        continue
                    memory_id = str(row.get("id", ""))
                    if not memory_id or len(memory_id) > 64:
                        continue
                    db.add(
                        MemoryItem(
                            id=memory_id,
                            user_id=job.user_id,
                            epoch=job.epoch,
                            memory=row["memory"][:2000],
                        )
                    )
                live.status, live.payload, live.last_error = "done", {}, None
        if stale:
            # A completed stale upstream write is physically erased, never projected.
            self.store.purge(scope)
            self.finish(job)

    def finish(self, job):
        with self.factory.begin() as db:
            db.execute(
                update(MemoryJob)
                .where(
                    MemoryJob.id == job.id,
                    MemoryJob.lease_token == job.lease_token,
                )
                .values(status="done", payload={}, last_error=None)
            )

    def run_once(self):
        job = self.claim()
        if not job:
            return False
        stop = threading.Event()

        def renew():
            while not stop.wait(self.settings.worker_lease_seconds / 3):
                with self.factory.begin() as db:
                    db.execute(
                        update(MemoryJob)
                        .where(
                            MemoryJob.id == job.id,
                            MemoryJob.lease_token == job.lease_token,
                        )
                        .values(lease_until=now() + self.settings.worker_lease_seconds)
                    )

        heartbeat = threading.Thread(target=renew, daemon=True)
        heartbeat.start()
        try:
            self.process(job)
        except Exception:
            with self.factory.begin() as db:
                db.execute(
                    update(MemoryJob)
                    .where(
                        MemoryJob.id == job.id,
                        MemoryJob.lease_token == job.lease_token,
                    )
                    .values(
                        status="pending",
                        available_at=now() + min(3600, 2 ** min(job.attempts, 11)),
                        last_error="memory_provider_unavailable",
                    )
                )
            log.warning("Memory job deferred: provider unavailable")
        finally:
            stop.set()
            heartbeat.join()
        return True

    def maintain(self):
        with self.factory.begin() as db:
            db.execute(delete(RateBucket).where(RateBucket.until < now() - 86400))
            db.execute(delete(Ticket).where(Ticket.expires_at < now()))
            db.execute(delete(Refresh).where(Refresh.expires_at < now() - 86400))
            db.execute(delete(MemoryJob).where(MemoryJob.status == "done"))


@contextmanager
def singleton(engine, settings):
    if engine.dialect.name == "postgresql":
        with engine.connect() as connection:
            if not connection.scalar(text("SELECT pg_try_advisory_lock(734921052)")):
                raise SystemExit("A memory worker is already running")
            try:
                yield
            finally:
                connection.execute(text("SELECT pg_advisory_unlock(734921052)"))
    else:
        import fcntl

        with (Path(settings.memory_path) / "worker.lock").open("a") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise SystemExit("A memory worker is already running") from None
            yield


def main():
    from lango.logging import safe_logging

    safe_logging()
    settings = Settings()
    engine, factory = make_database(settings)
    stopped = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stopped.set())
    signal.signal(signal.SIGINT, lambda *_: stopped.set())
    worker = Worker(factory, settings)
    try:
        check_schema(engine)
        with singleton(engine, settings):
            last_maintenance = 0
            while not stopped.is_set():
                if time.monotonic() - last_maintenance > 60:
                    worker.maintain()
                    last_maintenance = time.monotonic()
                if not worker.run_once():
                    stopped.wait(settings.worker_poll_seconds)
    finally:
        worker.store.close()
        engine.dispose()


if __name__ == "__main__":
    main()
