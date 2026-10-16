# Linkwarden on Railway — one-click deploy wrapper (single service)
#
# Everything (Next.js app + archiving worker, PostgreSQL 15, Meilisearch)
# runs in ONE container. This is deliberate: Railway's `templates create`
# only carries ${{...}} expressions from scratch-project variables into
# template defaults — plain literals (postgres user/db, data paths, feature
# flags) would land on the deploy form as required fields. Baking every
# constant into the image keeps the one-click form at exactly zero fields,
# and it removes the whole class of cross-service reference-resolution
# failures (a sibling that starts before its reference resolves caches the
# broken value — learned the hard way on a two-service template).
#
# Base is the official prebuilt image (ghcr.io/linkwarden/linkwarden),
# pinned by digest: the built Next.js app, the tsx archiving worker, the
# Rust `monolith` binary for single-file HTML archives, and Playwright's
# headless Chromium shell for screenshot/PDF captures are all already
# inside — the wrapper only adapts it to Railway, never rebuilds it.
#
# Added layers:
#   postgresql-15 (Debian bookworm) — the app database. Cluster lives at
#     /data/pgdata (PGDATA, on its own Railway volume). Trust auth on
#     localhost only; postgres never leaves the container.
#   meilisearch binary (copied from the pinned getmeili/meilisearch image)
#     — full-text search. Index at /data/meili_data (own volume), master
#     key generated once at first boot and persisted at
#     /data/meili_data/.master_key so it survives restarts.
#
# Persistence (three Railway volumes, all mounted by railway.json):
#   /data/data ....... archived pages (STORAGE_FOLDER)
#   /data/pgdata ..... PostgreSQL cluster
#   /data/meili_data . Meilisearch index + master key
#
# The entrypoint inits/starts postgres, starts meilisearch, waits for both,
# runs `prisma migrate deploy`, then starts the web server and the worker
# in the foreground as PID 1 (the stock image's concurrently command).
#
# Upstream: https://github.com/linkwarden/linkwarden (AGPL-3.0)
# Base image: ghcr.io/linkwarden/linkwarden v2.16.3

FROM getmeili/meilisearch@sha256:c4d6ab59c18d7b3636e82af862c31861ccf8afb3e9c14dddf9d3e868840667cd AS meili

FROM ghcr.io/linkwarden/linkwarden@sha256:0664c28a039bda8ffa6663389e8536b2fc717219e329f85b83faca7efed3b144

USER root

# Meilisearch binary from the pinned official image (statically linked).
COPY --from=meili /bin/meilisearch /usr/local/bin/meilisearch

# PostgreSQL 15 server (Debian bookworm package; creates the `postgres` user).
RUN set -eux && \
    apt-get update && \
    apt-get install -yqq --no-install-recommends postgresql-15 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# --- Baked constants (never on the deploy form) ---
# Archives on the volume (absolute: the web/worker processes cd elsewhere).
ENV STORAGE_FOLDER=/data/data
# Bound Chromium archival concurrency: keeps archive bursts in Hobby RAM.
ENV MAX_WORKERS=1
# Postgres cluster dir (volume-mounted; subdir dodges the volume's lost+found
# which makes initdb refuse a mount point used directly as PGDATA).
ENV PGDATA=/data/pgdata
ENV MEILI_NO_ANALYTICS=true
ENV MEILI_ENV=production

# The stock image healthchecks 127.0.0.1:3000, but Railway injects its own
# PORT (usually 8080) — disable it and use Railway's external healthcheckPath.
HEALTHCHECK NONE

EXPOSE 3000

LABEL org.opencontainers.image.source="https://github.com/mc9max/linkwarden-lite"

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
