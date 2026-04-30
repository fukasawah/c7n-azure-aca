# --- Stage 1: Build ---
FROM python:3.11-slim AS builder
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
WORKDIR /app
COPY pyproject.toml uv.lock ./
COPY src/ src/
RUN uv sync --frozen --no-dev

# --- Stage 2: Runtime ---
FROM python:3.11-slim
RUN groupadd -r custodian && useradd -r -g custodian custodian
WORKDIR /app
COPY --from=builder /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"
USER custodian
ENTRYPOINT ["python", "-m", "c7n_azure_container_apps"]
