#!/usr/bin/env sh
# Container entrypoint.
#
# docker-compose ran migrations and seeding as part of its `command:`, but
# platforms that build straight from the Dockerfile (Railway, Fly, Cloud Run)
# only run CMD. Without this the app boots against an empty schema and every
# query 500s, so the steps live here instead.
set -e
 
echo "==> Running database migrations"
alembic upgrade head
 
echo "==> Seeding reference data"
# Idempotent: skips anything that already exists. Never fatal, because a
# seeding hiccup should not stop an otherwise healthy deploy.
python -m app.seed || echo "WARNING: seeding failed, continuing anyway"
 
# Railway, Heroku and friends inject $PORT. Fall back to 8000 locally.
PORT="${PORT:-8000}"
echo "==> Starting gunicorn on port ${PORT}"
 
exec gunicorn app.main:app \
  -k uvicorn.workers.UvicornWorker \
  -b "0.0.0.0:${PORT}" \
  -w "${WEB_CONCURRENCY:-4}" \
  --timeout 120 \
  --access-logfile - \
  --error-logfile -
