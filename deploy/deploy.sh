#!/usr/bin/env bash
# Deploys the API + worker to a host running Docker. Run from the repo root.
set -euo pipefail

HOST="${DEPLOY_HOST:?set DEPLOY_HOST, e.g. deploy@api.awlc.app}"
REMOTE_DIR="${REMOTE_DIR:-/opt/awlc}"
IMAGE="${IMAGE:-ghcr.io/awlc/api:latest}"

echo "==> Shipping compose + config to ${HOST}:${REMOTE_DIR}"
ssh "$HOST" "mkdir -p ${REMOTE_DIR}/deploy ${REMOTE_DIR}/secrets"
scp docker-compose.prod.yml "$HOST:${REMOTE_DIR}/docker-compose.yml"
scp deploy/Caddyfile "$HOST:${REMOTE_DIR}/deploy/Caddyfile"

if [[ -f .env.production ]]; then
  scp .env.production "$HOST:${REMOTE_DIR}/.env"
else
  echo "!! .env.production not found locally; assuming ${REMOTE_DIR}/.env already exists on the host"
fi

echo "==> Pulling ${IMAGE} and restarting"
ssh "$HOST" "cd ${REMOTE_DIR} && IMAGE=${IMAGE} docker compose pull && IMAGE=${IMAGE} docker compose up -d --remove-orphans"

echo "==> Waiting for health"
for i in $(seq 1 30); do
  if ssh "$HOST" "curl -fsS http://localhost:8000/health >/dev/null 2>&1"; then
    echo "==> Healthy"
    ssh "$HOST" "cd ${REMOTE_DIR} && docker image prune -f"
    exit 0
  fi
  sleep 5
done

echo "!! Health check failed; rolling back to the previous image"
ssh "$HOST" "cd ${REMOTE_DIR} && docker compose logs --tail 80 api && docker compose rollback 2>/dev/null || docker compose up -d"
exit 1
