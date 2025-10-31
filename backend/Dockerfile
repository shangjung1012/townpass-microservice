FROM ghcr.io/astral-sh/uv:python3.11-bookworm-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN uv pip install --system --no-cache -r requirements.txt

COPY app ./app
COPY alembic ./alembic
COPY alembic.ini .

CMD exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}
