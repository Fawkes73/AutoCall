#!/usr/bin/env bash
set -euo pipefail

: "${POSTGRES_HOST:=localhost}"
: "${POSTGRES_PORT:=5432}"
: "${POSTGRES_DB:=autocall}"
: "${POSTGRES_USER:=autocall}"
: "${BACKUP_DIR:=/var/backups/autocall/postgres}"
: "${RETENTION_DAYS:=14}"

mkdir -p "${BACKUP_DIR}"
backup_file="${BACKUP_DIR}/${POSTGRES_DB}-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"

PGPASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}" \
  pg_dump --host "${POSTGRES_HOST}" --port "${POSTGRES_PORT}" --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" --format plain --no-owner --no-privileges \
  | gzip -9 > "${backup_file}"

find "${BACKUP_DIR}" -type f -name "${POSTGRES_DB}-*.sql.gz" -mtime +"${RETENTION_DAYS}" -delete

echo "Created backup: ${backup_file}"
