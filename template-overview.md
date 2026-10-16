# Deploy and Host

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.com/deploy/linkwarden-lite?utm_campaign=linkwarden-lite)

**Linkwarden** — a self-hosted, collaborative bookmark manager that permanently archives every saved page as a **screenshot, PDF, and single-file HTML snapshot**, so your links survive link rot. Collections, tags, sharing, browser extension, mobile apps, and fast full-text search.

Deploys in one click with **zero form fields**. Three services come up together:

- **linkwarden** — the Next.js web app + the archiving worker (headless Chromium + `monolith` HTML snapshots) on `/`
- **postgres** — PostgreSQL 16 on a Railway volume
- **meilisearch** — full-text search on a Railway volume, private-network only

Secrets (`NEXTAUTH_SECRET`, `MEILI_MASTER_KEY`, `POSTGRES_PASSWORD`) are generated; the database URL is composed at boot from the Postgres companion; `NEXTAUTH_URL` points at your Railway domain. Open the domain and create your account.

## About Hosting

The app honors Railway's injected `PORT`. The entrypoint waits for Postgres, runs `prisma migrate deploy`, then starts the web server and the archiving worker in the foreground. Archives land on the `/data/data` volume; the database and search index have their own volumes. Healthcheck is `GET /` (200 or login redirect, unauthenticated).

- **Memory:** app ~500 MB at rest; `MAX_WORKERS=1` caps Chromium concurrency so archive bursts stay inside Hobby limits. Postgres ~100 MB, Meilisearch ~200 MB at rest.
- **Build:** the official prebuilt image (v2.16.3, digest-pinned) — no source build, deploys in minutes.

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

Three services, zero form fields, three volumes. The app needs outbound HTTPS (to archive the pages you save). Postgres and Meilisearch talk to the app over Railway's private network only — neither gets a public domain.

**Configuration** (wired automatically; optional upstream vars go in the service Variables panel):

| Variable | Default | What it does |
|---|---|---|
| `PGHOST` / `PGUSER` / `PGPASSWORD` / `PGDATABASE` | `${{postgres.…}}` refs | Postgres companion credentials; composed into `DATABASE_URL` at boot |
| `NEXTAUTH_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}/api/v1/auth` | Public auth callback base URL |
| `NEXTAUTH_SECRET` | `${{secret(32)}}` | Session signing secret |
| `MEILI_HOST` | `http://${{meilisearch.RAILWAY_PRIVATE_DOMAIN}}:7700` | Full-text search backend |
| `MEILI_MASTER_KEY` | `${{meilisearch.MEILI_MASTER_KEY}}` | Shared search API key |
| `STORAGE_FOLDER` | `/data/data` (baked) | Archive storage path (on the volume) |
| `MAX_WORKERS` | `1` (baked) | Concurrent Chromium archival jobs |

Useful upstream options: `PAGINATION_TAKE_COUNT`, `ARCHIVE_TAKE_COUNT`, `BROWSER_TIMEOUT`, `MAX_LINKS_PER_USER`, `NEXT_PUBLIC_RSS_POLLING_INTERVAL_MINUTES`, `TEXT_CONTENT_LIMIT`, AI auto-tagging (`OLLAMA_MODEL` or `OPENAI_API_KEY` + provider variants), S3 archive storage (`SPACES_*`), SMTP (`EMAIL_SERVER`/`EMAIL_FROM`), outbound `PROXY`, `ALLOW_PRIVATE_NETWORK_ACCESS`, PDF margins, and 40+ SSO providers (`NEXT_PUBLIC_<PROVIDER>_ENABLED` + credentials — GitHub, Google, Authentik, Keycloak, generic OIDC, …). Full list: https://docs.linkwarden.app/self-hosting/environment-variables
