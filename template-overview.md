# Deploy and Host

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.com/deploy/linkwarden-lite?utm_campaign=linkwarden-lite)

**Linkwarden** — a self-hosted, collaborative bookmark manager that permanently archives every saved page as a **screenshot, PDF, and single-file HTML snapshot**, so your links survive link rot. Collections, tags, sharing, browser extension, mobile apps, and fast full-text search.

Deploys in one click with **zero form fields**. The whole stack runs in one service — the Next.js app + archiving worker (headless Chromium + `monolith` HTML snapshots), PostgreSQL 15, and Meilisearch — on three persistent volumes:

- **linkwarden-data** — one volume holding `archives/` (saved pages), `pgdata/` (PostgreSQL cluster) and `meili_data/` (search index)

The entrypoint initializes PostgreSQL on first boot (localhost only — never exposed), generates the Meilisearch master key once and persists it on the volume, runs `prisma migrate deploy`, then starts the web server and worker. `NEXTAUTH_URL` points at your Railway domain; `NEXTAUTH_SECRET` is generated. Open the domain and create your account.

## About Hosting

The app honors Railway's injected `PORT`. Healthcheck is `GET /` (200 or login redirect, unauthenticated). The database and search engine run inside the same container on localhost — nothing but the web app is reachable.

- **Memory:** app ~500 MB at rest; `MAX_WORKERS=1` caps Chromium concurrency so archive bursts stay inside Hobby limits. Postgres ~100 MB, Meilisearch ~200 MB at rest.
- **Build:** the official prebuilt image (v2.16.3, digest-pinned) plus PostgreSQL and the Meilisearch binary — deploys in minutes, no source build.

## Why Deploy

Read-it-later apps rent you your own memory. Linkwarden keeps it on your hardware: every page you save is archived in three formats on your volume, full-text indexed on your Meilisearch, and searchable forever — no subscription, no link rot, no third party reading your bookmarks. The worker does real sustained work per saved link (Chromium renders screenshots/PDFs, `monolith` inlines a portable HTML copy), which is exactly the kind of always-on workload that belongs on your own Railway project instead of a metered cloud plan.

## Common Use Cases

- A personal "second brain" of web pages immune to link rot
- Team research collections with per-collection permissions and public share links
- RSS-fed auto-archiving of newsletters and blogs
- Archiving pages ahead of a redesign, shutdown, or paywall
- Full-text search across everything you have ever saved

## Dependencies for

### Deployment Dependencies

One service, zero form fields, one volume. The app needs outbound HTTPS (to archive the pages you save).

**Configuration** (auto-filled; optional upstream vars go in the service Variables panel):

| Variable | Default | What it does |
|---|---|---|
| `NEXTAUTH_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}/api/v1/auth` | Public auth callback base URL |
| `NEXTAUTH_SECRET` | `${{secret(32)}}` | Session signing secret |
| `DATABASE_URL` | composed at boot | Single-container Postgres (`postgresql://linkwarden@127.0.0.1:5432/linkwarden`) |
| `MEILI_HOST` / `MEILI_MASTER_KEY` | composed / generated at boot | Search backend; key persisted on the volume |
| `STORAGE_FOLDER` | `/data/data/archives` (baked) | Archive storage path |
| `PGDATA` | `/data/data/pgdata` (baked) | Postgres cluster dir |
| `MAX_WORKERS` | `1` (baked) | Concurrent Chromium archival jobs |

Useful upstream options: `PAGINATION_TAKE_COUNT`, `ARCHIVE_TAKE_COUNT`, `BROWSER_TIMEOUT`, `MAX_LINKS_PER_USER`, `NEXT_PUBLIC_RSS_POLLING_INTERVAL_MINUTES`, `TEXT_CONTENT_LIMIT`, AI auto-tagging (`OLLAMA_MODEL` or `OPENAI_API_KEY` + provider variants), S3 archive storage (`SPACES_*`), SMTP (`EMAIL_SERVER`/`EMAIL_FROM`), outbound `PROXY`, `ALLOW_PRIVATE_NETWORK_ACCESS`, PDF margins, and 40+ SSO providers (`NEXT_PUBLIC_<PROVIDER>_ENABLED` + credentials — GitHub, Google, Authentik, Keycloak, generic OIDC, …). Full list: https://docs.linkwarden.app/self-hosting/environment-variables
