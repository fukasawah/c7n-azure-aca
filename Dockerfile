# --- Stage 1: Build ---
FROM dhi.io/python:3.14-dev AS builder
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
WORKDIR /app
COPY pyproject.toml uv.lock ./
COPY src/ src/
RUN uv sync --frozen --no-dev

# --- Stage 2: Runtime ---
FROM dhi.io/python:3.14
WORKDIR /app
COPY --from=builder /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"
ENTRYPOINT ["python", "-m", "c7n_azure_container_apps"]
