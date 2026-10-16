#!/bin/sh
set -e

# Linkwarden app entrypoint for Railway.
#
# 1. Compose DATABASE_URL for the Postgres companion. PGHOST and PGPASSWORD
#    are single-value ${{postgres.*}} template references (the only thing
#    Railway carries into template defaults); user/db/port are this
#    template's fixed constants, composed here in shell — never as a
#    multi-reference variable value, which Railway resolves unreliably.
#    A manually-set DATABASE_URL always wins.
# 2. Wait for PostgreSQL before `prisma migrate deploy` — the stock image
#    migrates immediately at boot, and on Railway the app and DB start in
#    parallel, so the first boot would crash migrate on a not-yet-ready DB.
# 3. Start the web server and the archiving worker. The worker runs in a
#    restart loop because upstream's linkIndexing has an uncaught path
#    (addDocuments) — a transient search-backend hiccup must not take the
#    web app down (concurrently runs WITHOUT -k for the same reason).
#    The worker is idempotent (polls for unprocessed links), so restarts
#    are safe.

export PATH="/data/node_modules/.bin:$PATH"

if [ -z "${DATABASE_URL}" ]; then
  PGHOST="${PGHOST:-postgres}"
  : "${PGPASSWORD:?PGPASSWORD is not set — the postgres companion failed to wire}"
  export DATABASE_URL="postgresql://linkwarden:${PGPASSWORD}@${PGHOST}:5432/linkwarden"
  echo "[linkwarden-entrypoint] composed DATABASE_URL (host=${PGHOST})"
fi

# --- Parse DB host/port out of DATABASE_URL (robust to user:pass@) ---
HOSTPORT="${DATABASE_URL#*://}"
HOSTPORT="${HOSTPORT##*@}"
case "${HOSTPORT}" in
  *:*) DB_HOST="${HOSTPORT%%:*}"; DB_PORT="${HOSTPORT#*:}" ;;
  *)   DB_HOST="${HOSTPORT}";     DB_PORT="5432" ;;
esac
DB_PORT="${DB_PORT%%/*}"

echo "[linkwarden-entrypoint] waiting for database at ${DB_HOST}:${DB_PORT} ..."
i=0
while ! node -e "
  const net = require('net');
  const s = net.connect({ host: '${DB_HOST}', port: Number('${DB_PORT}'), timeout: 2000 });
  s.on('connect', () => { s.end(); process.exit(0); });
  s.on('error',   () => process.exit(1));
  s.on('timeout', () => { s.destroy(); process.exit(1); });
"; do
  i=$((i + 1))
  if [ "$i" -gt 60 ]; then echo "[linkwarden-entrypoint] database never became ready"; exit 1; fi
  sleep 3
done
echo "[linkwarden-entrypoint] database reachable"

echo "[linkwarden-entrypoint] applying Prisma migrations"
prisma migrate deploy --schema=/data/packages/prisma/schema.prisma

echo "[linkwarden-entrypoint] starting Linkwarden web + worker (foreground)"
exec concurrently -n web,worker \
  "cd /data/apps/web && exec next start" \
  "while true; do (cd /data/apps/worker && exec tsx worker.ts); echo \"[linkwarden-entrypoint] worker exited (\$?) — restarting in 5s\"; sleep 5; done"
