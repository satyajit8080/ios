#!/usr/bin/env bash
# Nightly Postgres backup with 14-day retention. Add to cron: 0 3 * * * /opt/awlc/deploy/backup.sh
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/awlc}"
KEEP_DAYS="${KEEP_DAYS:-14}"
STAMP="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP_DIR"
docker compose -f /opt/awlc/docker-compose.yml exec -T db \
  pg_dump -U "${POSTGRES_USER:-awlc}" "${POSTGRES_DB:-awlc}" | gzip > "${BACKUP_DIR}/awlc-${STAMP}.sql.gz"

find "$BACKUP_DIR" -name 'awlc-*.sql.gz' -mtime "+${KEEP_DAYS}" -delete
echo "backup written: ${BACKUP_DIR}/awlc-${STAMP}.sql.gz"
