#!/bin/sh
set -e

# Linkwarden entrypoint for Railway.
#
# 1. Compose DATABASE_URL from PG* component vars (tianji-proven pattern).
#    The template wires PGHOST/PGUSER/PGPASSWORD/PGDATABASE as single-value
#    ${{postgres.VAR}} references, which Railway resolves reliably; composing
#    several references inside one DATABASE_URL value is not reliable, so the
#    composition happens here at boot. A manually-set DATABASE_URL wins.
# 2. Wait for PostgreSQL before `prisma migrate deploy` — the stock image
#    migrates immediately at boot, and on Railway the app and DB start in
#    parallel, so the first boot would crash migrate on a not-yet-ready DB.
# 3. Start the web server and the archiving worker in the foreground as PID 1
#    (same concurrently command the stock image uses).

export PATH="/data/node_modules/.bin:$PATH"

if [ -z "${DATABASE_URL}" ] && [ -n "${PGUSER}" ]; then
  PGHOST="${PGHOST:-postgres}"
  PGPORT="${PGPORT:-5432}"
  PGDATABASE="${PGDATABASE:-linkwarden}"
  if [ -n "${PGPASSWORD}" ]; then
    export DATABASE_URL="postgresql://${PGUSER}:${PGPASSWORD}@${PGHOST}:${PGPORT}/${PGDATABASE}"
  else
    export DATABASE_URL="postgresql://${PGUSER}@${PGHOST}:${PGPORT}/${PGDATABASE}"
  fi
  echo "[linkwarden-entrypoint] composed DATABASE_URL from PG* component vars (host=${PGHOST})"
fi

# --- Parse DB host/port out of DATABASE_URL (robust to user:pass@) ---
HOSTPORT=""
if [ -n "${DATABASE_URL}" ]; then
  HOSTPORT="${DATABASE_URL#*://}"
  HOSTPORT="${HOSTPORT##*@}"
fi
if [ -n "${HOSTPORT}" ]; then
  case "${HOSTPORT}" in
    *:*) DB_HOST="${HOSTPORT%%:*}"; DB_PORT="${HOSTPORT#*:}" ;;
    *)   DB_HOST="${HOSTPORT}";   DB_PORT="5432" ;;
  esac
  DB_PORT="${DB_PORT%%/*}"
else
  DB_HOST="postgres"
  DB_PORT="5432"
fi

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
  echo "[linkwarden-entrypoint] database not up yet (attempt ${i})"
  sleep 3
done
echo "[linkwarden-entrypoint] database reachable"

echo "[linkwarden-entrypoint] applying Prisma migrations"
prisma migrate deploy --schema=/data/packages/prisma/schema.prisma

echo "[linkwarden-entrypoint] starting Linkwarden web + worker (foreground)"
exec concurrently -k -n web,worker \
  "cd /data/apps/web && exec next start" \
  "cd /data/apps/worker && exec tsx worker.ts"
