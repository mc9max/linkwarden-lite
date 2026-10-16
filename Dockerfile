# Linkwarden on Railway — one-click deploy wrapper (app service)
#
# Base is the official prebuilt image (ghcr.io/linkwarden/linkwarden),
# pinned by digest: the built Next.js app, the tsx archiving worker, the
# Rust `monolith` binary for single-file HTML archives, and Playwright's
# headless Chromium shell for screenshot/PDF captures are all already
# inside — the wrapper only adapts it to Railway, never rebuilds it.
#
# Companion services (PostgreSQL 16 and Meilisearch) run as sibling
# services from postgres.Dockerfile and meilisearch.Dockerfile in this
# repo. Every constant is baked into the images as ENV because Railway's
# `templates create` only carries ${{...}} expressions into template
# defaults — plain literals would land on the deploy form as required
# fields. The only template variables are ${{...}} expressions, so the
# one-click form is zero fields.
#
# Why each non-default setting exists:
#   USER root ................. The stock image already runs as root; keep it
#                               explicit because Railway mounts persistent
#                               volumes root-owned.
#   STORAGE_FOLDER=/data/data . Upstream defaults to a RELATIVE "data" dir,
#                               but the web and worker processes `cd` into
#                               their own app dirs — an absolute path keeps
#                               every archive on the mounted Railway volume.
#   MAX_WORKERS=1 ............. Bounds Chromium archival concurrency so one
#                               busy archive burst stays in Hobby RAM.
#   HEALTHCHECK NONE .......... The stock image healthchecks 127.0.0.1:3000,
#                               but Railway injects its own PORT (usually
#                               8080). Railway's external healthcheckPath
#                               ("/") in railway.json is the readiness gate.
#
# Upstream: https://github.com/linkwarden/linkwarden (AGPL-3.0)
# Base image: ghcr.io/linkwarden/linkwarden v2.16.3

FROM ghcr.io/linkwarden/linkwarden@sha256:0664c28a039bda8ffa6663389e8536b2fc717219e329f85b83faca7efed3b144

USER root

ENV STORAGE_FOLDER=/data/data
ENV MAX_WORKERS=1

HEALTHCHECK NONE

EXPOSE 3000

LABEL org.opencontainers.image.source="https://github.com/mc9max/linkwarden-lite"

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
