#!/bin/sh
set -e

# Linkwarden single-service entrypoint for Railway.
#
# 1. PostgreSQL: init the cluster at $PGDATA on first boot (volume-backed),
#    start it on localhost, create the `linkwarden` role + database.
#    Trust auth — postgres never leaves this container. A stale postmaster.pid
#    from an unclean shutdown is removed (pg_ctl recovers the cluster).
# 2. Meilisearch: master key generated once at first boot and persisted on
#    the volume. If it fails to become ready (e.g. an index corrupted by an
#    unclean shutdown during active indexing), the index dir is wiped and it
#    is retried fresh — the worker re-indexes automatically. If it still
#    fails, the app boots WITHOUT search (MEILI_MASTER_KEY unset, which the
#    app treats as "search disabled") instead of crash-looping.
# 3. Wait for both, run `prisma migrate deploy`, then start the web server
#    and the archiving worker. The worker runs in a restart loop because
#    upstream's linkIndexing has an uncaught path (addDocuments) — a
#    transient search-backend hiccup must not take the web app down with it
#    (concurrently is run WITHOUT -k for the same reason).

export PATH="/data/node_modules/.bin:$PATH"

# ---------------- PostgreSQL ----------------
if [ ! -s "$PGDATA/PG_VERSION" ]; then
  echo "[linkwarden-entrypoint] initializing PostgreSQL cluster at $PGDATA"
  mkdir -p "$PGDATA" && chown -R postgres:postgres "$PGDATA"
  su postgres -c "/usr/lib/postgresql/15/bin/initdb -D $PGDATA -E UTF8 --auth=trust"
fi

# Drop a stale pidfile left by an unclean shutdown (server is not running).
if [ -f "$PGDATA/postmaster.pid" ] && ! su postgres -c "pg_isready -h 127.0.0.1 -p 5432" >/dev/null 2>&1; then
  echo "[linkwarden-entrypoint] removing stale postmaster.pid"
  rm -f "$PGDATA/postmaster.pid"
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
MEILI_DB=/data/data/meili_data
mkdir -p "$MEILI_DB"
if [ ! -f "$MEILI_KEY_FILE" ]; then
  echo "[linkwarden-entrypoint] generating Meilisearch master key"
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 > "$MEILI_KEY_FILE"
  chmod 600 "$MEILI_KEY_FILE"
fi
MEILI_MASTER_KEY="$(cat "$MEILI_KEY_FILE")"
export MEILI_HOST="http://127.0.0.1:7700"

start_meilisearch() {
  /usr/local/bin/meilisearch --http-addr 127.0.0.1:7700 --db-path "$MEILI_DB" >>/data/data/meili.log 2>&1 &
  MEILI_PID=$!
}
meilisearch_ready() {
  i=0
  until curl -sf http://127.0.0.1:7700/health >/dev/null 2>&1; do
    i=$((i + 1)); [ "$i" -gt 45 ] && return 1; sleep 2
  done
  return 0
}

echo "[linkwarden-entrypoint] starting Meilisearch"
start_meilisearch
if ! meilisearch_ready; then
  echo "[linkwarden-entrypoint] meilisearch not ready in 90s — wiping index and retrying fresh"
  kill "$MEILI_PID" 2>/dev/null; sleep 3
  rm -rf "$MEILI_DB"
  mkdir -p "$MEILI_DB"
  start_meilisearch
  if ! meilisearch_ready; then
    echo "[linkwarden-entrypoint] WARNING: meilisearch unavailable — continuing without full-text search"
    kill "$MEILI_PID" 2>/dev/null
    unset MEILI_MASTER_KEY
    export MEILI_HOST=""
  else
    export MEILI_MASTER_KEY
    echo "[linkwarden-entrypoint] Meilisearch ready (fresh index; worker will re-index)"
  fi
else
  export MEILI_MASTER_KEY
  echo "[linkwarden-entrypoint] Meilisearch ready"
fi

# ---------------- App ----------------
echo "[linkwarden-entrypoint] applying Prisma migrations"
prisma migrate deploy --schema=/data/packages/prisma/schema.prisma

echo "[linkwarden-entrypoint] starting Linkwarden web + worker (foreground)"
# No -k: a worker crash must not kill the web server. The worker loop below
# restarts it; the worker is idempotent (polls for unprocessed links).
exec concurrently -n web,worker \
  "cd /data/apps/web && exec next start" \
  "while true; do (cd /data/apps/worker && exec tsx worker.ts); echo \"[linkwarden-entrypoint] worker exited (\$?) — restarting in 5s\"; sleep 5; done"
