# Linkwarden on Railway — one-click deploy wrapper
#
# Base is the official prebuilt image (ghcr.io/linkwarden/linkwarden), pinned
# by digest. It already contains the built Next.js web app, the archiving
# worker (tsx), the Rust `monolith` binary for single-file HTML archives, and
# Playwright's headless Chromium shell for screenshot/PDF captures — so the
# wrapper only adapts it to Railway, never rebuilds it.
#
# Why each non-default setting exists:
#   USER root ................. The stock image already runs as root; keep it
#                               explicit because Railway mounts persistent
#                               volumes root-owned (non-root uids crash-loop
#                               on EACCES writing archives).
#   STORAGE_FOLDER=/data/data . Upstream defaults to a RELATIVE "data" dir, but
#                               the web and worker processes `cd` into their
#                               own app dirs before starting — so the relative
#                               default would scatter archives across the
#                               container. An absolute path keeps every archive
#                               on the mounted Railway volume.
#   MAX_WORKERS=1 ............. Bounds how many Chromium archival jobs run at
#                               once; keeps one busy archive burst inside the
#                               Hobby service RAM ceiling.
#   HEALTHCHECK NONE .......... The stock image healthchecks 127.0.0.1:3000,
#                               but Railway injects its own PORT (rarely 3000).
#                               Railway's external healthcheckPath ("/") in
#                               railway.json is the real readiness gate.
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
