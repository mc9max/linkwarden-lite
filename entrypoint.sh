#!/bin/sh
set -e

# Linkwarden single-service entrypoint for Railway.
#
# 1. PostgreSQL: init the cluster at $PGDATA on first boot (volume-backed),
#    start it on localhost, create the `linkwarden` role + database.
#    Trust auth — postgres never leaves this container.
# 2. Meilisearch: master key generated once at first boot and persisted on
#    the volume (a fresh key per restart would lock the app out of its own
#    index). Starts on 127.0.0.1:7700.
# 3. Wait for both, run `prisma migrate deploy`, then start the web server
#    and the archiving worker in the foreground as PID 1 (the stock image's
#    concurrently command).

export PATH="/data/node_modules/.bin:$PATH"

# ---------------- PostgreSQL ----------------
if [ ! -s "$PGDATA/PG_VERSION" ]; then
  echo "[linkwarden-entrypoint] initializing PostgreSQL cluster at $PGDATA"
  mkdir -p "$PGDATA" && chown -R postgres:postgres "$PGDATA"
  su postgres -c "/usr/lib/postgresql/15/bin/initdb -D $PGDATA -E UTF8 --auth=trust"
fi

echo "[linkwarden-entrypoint] starting PostgreSQL"
su postgres -c "/usr/lib/postgresql/15/bin/pg_ctl -D $PGDATA -l $PGDATA/pg.log -o '-c listen_addresses=127.0.0.1' start"

echo "[linkwarden-entrypoint] waiting for PostgreSQL ..."
i=0
until su postgres -c "pg_isready -h 127.0.0.1 -p 5432" >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -gt 60 ]; then echo "[linkwarden-entrypoint] postgres never became ready"; exit 1; fi
  sleep 2
done
echo "[linkwarden-entrypoint] PostgreSQL ready"

if ! su postgres -c "psql -h 127.0.0.1 -p 5432 -tc \"SELECT 1 FROM pg_roles WHERE rolname='linkwarden'\"" | grep -q 1; then
  su postgres -c "psql -h 127.0.0.1 -p 5432 -c \"CREATE USER linkwarden;\""
  echo "[linkwarden-entrypoint] created role linkwarden"
fi
if ! su postgres -c "psql -h 127.0.0.1 -p 5432 -tc \"SELECT 1 FROM pg_database WHERE datname='linkwarden'\"" | grep -q 1; then
  su postgres -c "psql -h 127.0.0.1 -p 5432 -c \"CREATE DATABASE linkwarden OWNER linkwarden;\""
  echo "[linkwarden-entrypoint] created database linkwarden"
fi

export DATABASE_URL="postgresql://linkwarden@127.0.0.1:5432/linkwarden"

# ---------------- Meilisearch ----------------
MEILI_KEY_FILE=/data/data/.meili_master_key
mkdir -p /data/data/meili_data
if [ ! -f "$MEILI_KEY_FILE" ]; then
  echo "[linkwarden-entrypoint] generating Meilisearch master key"
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 > "$MEILI_KEY_FILE"
  chmod 600 "$MEILI_KEY_FILE"
fi
export MEILI_MASTER_KEY="$(cat "$MEILI_KEY_FILE")"
export MEILI_HOST="http://127.0.0.1:7700"

echo "[linkwarden-entrypoint] starting Meilisearch"
/usr/local/bin/meilisearch --http-addr 127.0.0.1:7700 --db-path /data/data/meili_data >>/data/data/meili.log 2>&1 &

echo "[linkwarden-entrypoint] waiting for Meilisearch ..."
i=0
until curl -sf http://127.0.0.1:7700/health >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -gt 60 ]; then echo "[linkwarden-entrypoint] meilisearch never became ready"; tail -20 /data/data/meili.log; exit 1; fi
  sleep 2
done
echo "[linkwarden-entrypoint] Meilisearch ready"

# ---------------- App ----------------
echo "[linkwarden-entrypoint] applying Prisma migrations"
prisma migrate deploy --schema=/data/packages/prisma/schema.prisma

echo "[linkwarden-entrypoint] starting Linkwarden web + worker (foreground)"
exec concurrently -k -n web,worker \
  "cd /data/apps/web && exec next start" \
  "cd /data/apps/worker && exec tsx worker.ts"
