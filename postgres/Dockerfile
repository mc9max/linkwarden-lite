# PostgreSQL 16 companion for the Linkwarden Railway template.
#
# Bakes every constant as ENV because Railway's `templates create` only
# carries ${{...}} expressions into template defaults — literals would land
# on the deploy form as required fields. The only variable on this service
# is POSTGRES_PASSWORD (${{secret(16)}}), which the app references as
# ${{postgres.POSTGRES_PASSWORD}}.
#
# Volume handling: the official image starts as root and its entrypoint
# chowns $PGDATA, which tolerates Railway's root-owned volumes. PGDATA is
# a SUBDIR of the mount because initdb refuses a volume mount point
# directly (it contains lost+found).

FROM postgres:16-alpine@sha256:1a66d744c1b459e13b05a8fca341da84cb63383e99ce262210efee5a319d4551

ENV PGDATA=/var/lib/postgresql/data/pgdata
ENV POSTGRES_USER=linkwarden
ENV POSTGRES_DB=linkwarden

LABEL org.opencontainers.image.source="https://github.com/mc9max/linkwarden-lite"
