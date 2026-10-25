FROM python:3.12-slim-bookworm
COPY --from=ghcr.io/astral-sh/uv:0.12.1 /uv /usr/local/bin/uv
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy PATH="/app/.venv/bin:$PATH" MEM0_TELEMETRY=false
WORKDIR /app
COPY server/pyproject.toml server/uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY server/ ./
RUN uv sync --frozen --no-dev && \
    groupadd --gid 10001 lango && useradd --uid 10001 --gid lango --no-create-home lango && \
    mkdir -p /data/memory && chown -R lango:lango /data
USER 10001:10001
EXPOSE 8000
CMD ["sh", "-c", "python -m lango.migrate && exec uvicorn lango.main:app --host 0.0.0.0 --port 8000 --no-access-log --ws-max-size 65536 --ws-max-queue 16"]
