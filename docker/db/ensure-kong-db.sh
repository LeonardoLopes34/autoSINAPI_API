#!/bin/sh

set -eu

: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
: "${KONG_PG_USER:?KONG_PG_USER is required}"
: "${KONG_PG_PASSWORD:?KONG_PG_PASSWORD is required}"
: "${KONG_PG_HOST:=db}"
: "${KONG_PG_DATABASE:=kong}"

echo "Waiting for PostgreSQL administrator authentication..."
attempt=0
max_attempts=60
until PGPASSWORD="$POSTGRES_PASSWORD" psql \
    -h "$KONG_PG_HOST" \
    -U "$POSTGRES_USER" \
    -d postgres \
    -c 'SELECT 1' >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge "$max_attempts" ]; then
    echo "ERROR: PostgreSQL administrator authentication failed after $((max_attempts * 2)) seconds."
    echo "Check POSTGRES_USER and POSTGRES_PASSWORD against the existing database volume."
    exit 1
  fi
  echo "PostgreSQL is not ready yet; retrying..."
  sleep 2
done

# The database volume can outlive .env. Keep the Kong role synchronized with
# the credentials used by the Kong containers instead of relying on the
# PostgreSQL image's one-time init scripts.
PGPASSWORD="$POSTGRES_PASSWORD" psql \
    -v ON_ERROR_STOP=1 \
    -h "$KONG_PG_HOST" \
    -U "$POSTGRES_USER" \
    -d postgres \
    --set=kong_user="$KONG_PG_USER" \
    --set=kong_password="$KONG_PG_PASSWORD" \
    --set=kong_database="$KONG_PG_DATABASE" <<'SQL'
SELECT format(
    'CREATE ROLE %I LOGIN PASSWORD %L',
    :'kong_user',
    :'kong_password'
)
WHERE NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = :'kong_user'
)
\gexec

SELECT format(
    'ALTER ROLE %I WITH LOGIN PASSWORD %L',
    :'kong_user',
    :'kong_password'
)
\gexec

SELECT format('CREATE DATABASE %I', :'kong_database')
WHERE NOT EXISTS (
    SELECT 1 FROM pg_database WHERE datname = :'kong_database'
)
\gexec

SELECT format(
    'GRANT ALL PRIVILEGES ON DATABASE %I TO %I',
    :'kong_database',
    :'kong_user'
)
\gexec
SQL

PGPASSWORD="$POSTGRES_PASSWORD" psql \
    -v ON_ERROR_STOP=1 \
    -h "$KONG_PG_HOST" \
    -U "$POSTGRES_USER" \
    -d "$KONG_PG_DATABASE" \
    --set=kong_user="$KONG_PG_USER" <<'SQL'
GRANT ALL ON SCHEMA public TO :"kong_user";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO :"kong_user";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO :"kong_user";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO :"kong_user";
SQL

echo "PostgreSQL user \"$KONG_PG_USER\" and database \"$KONG_PG_DATABASE\" are ready."
