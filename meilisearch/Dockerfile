# Meilisearch companion for the Linkwarden Railway template.
#
# Bakes constants as ENV; the only variable on this service is
# MEILI_MASTER_KEY (${{secret(32)}}), which the app references as
# ${{meilisearch.MEILI_MASTER_KEY}}. The app reaches it over Railway's
# private network at http://<private-domain>:7700.

FROM getmeili/meilisearch@sha256:c4d6ab59c18d7b3636e82af862c31861ccf8afb3e9c14dddf9d3e868840667cd

ENV MEILI_ENV=production
ENV MEILI_NO_ANALYTICS=true

LABEL org.opencontainers.image.source="https://github.com/mc9max/linkwarden-lite"
