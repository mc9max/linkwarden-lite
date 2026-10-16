# Linkwarden

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.com/deploy/linkwarden-lite?utm_campaign=linkwarden-lite)

**Linkwarden** is a self-hosted, collaborative bookmark manager that never lets a link die: every page you save is permanently archived as a **screenshot, a PDF, and a single-file HTML snapshot**, so it stays readable even after the original goes offline. Organize everything into collections with sub-collections and tags, share collections publicly or with collaborators, search it all with fast full-text search, and capture from anywhere with the browser extension and mobile apps.

This repo is a one-click Railway wrapper around the official [Linkwarden](https://github.com/linkwarden/linkwarden) image (AGPL-3.0, v2.16.3 pinned by digest): the Next.js app plus its archiving worker, a Postgres companion, and a Meilisearch companion for full-text search.

## Deploy and Host

Click **Deploy on Railway** — zero form fields. The template provisions three services:

- **linkwarden** (this repo) — the Next.js web app + the archiving worker (headless Chromium screenshots/PDFs, single-file HTML via the `monolith` binary) on `/`
- **postgres** — PostgreSQL 16, data on a Railway volume
- **meilisearch** — Meilisearch v1.13.3 for full-text search, index on a Railway volume, reachable only over the private network

Everything is wired automatically: the database URL is composed at boot from the Postgres companion's credentials, `NEXTAUTH_URL` points at your Railway domain, and both secrets (`NEXTAUTH_SECRET`, `MEILI_MASTER_KEY`) are generated.

After deploy, open your Railway domain and **create your account** — registration is open by default (close it later with `NEXT_PUBLIC_DISABLE_REGISTRATION=true` after you sign up... note: `NEXT_PUBLIC_*` values are baked at image build time, so that particular toggle only takes effect if you fork and rebuild; the running app otherwise reads all other vars at runtime).

## Why Deploy

Pocket-style "read it later" apps rent you your own memory. Linkwarden keeps it on your hardware: every saved page is archived in three formats on your Railway volume, full-text indexed on your Meilisearch, and searchable forever — no subscription, no link rot, no third party reading your bookmarks. The archiving worker is the interesting part: headless Chromium renders each page for screenshots and PDFs, and the Rust `monolith` binary inlines everything into one portable HTML file. That is real, sustained CPU/RAM/disk work per saved link — the kind of always-on workload that makes self-hosting it here cheaper than the cloud plan.

## Common Use Cases

- A personal "second brain" of web pages that survives link rot (screenshot + PDF + HTML per link)
- Team research collections with per-collection permissions and public share links
- RSS-fed auto-archiving of newsletters and blogs you follow
- Archiving pages before a redesign, shutdown, or paywall (your own bookmarks — respect copyright)
- Full-text search across everything you have ever saved

## Runtime

- **Port:** honors Railway's injected `PORT` (`next start` on the web app)
- **Memory:** app ~500 MB at rest; Chromium archival jobs spike — `MAX_WORKERS=1` caps concurrency so bursts stay inside Hobby limits. Postgres ~100 MB, Meilisearch ~200 MB at rest
- **Persistence:** `/data/data` (archives), `/var/lib/postgresql/data/pgdata`, `/meili_data` — all on Railway volumes
- **Healthcheck:** `GET /` (200 or login redirect, unauthenticated)
- **First boot:** the entrypoint waits for Postgres, runs `prisma migrate deploy`, then starts web + worker

### Deployment Dependencies

Three services, no form fields. The app needs outbound HTTPS (to archive the pages you save). Postgres and Meilisearch communicate over Railway's private network only — no public domains.

## Configuration

Every variable the deployment consumes. Wired values are filled by the template; baked values live in the Dockerfile; optional upstream values can be added in the service **Variables** panel.

| Variable | Default | What it does |
|---|---|---|
| `PGHOST` / `PGUSER` / `PGPASSWORD` / `PGDATABASE` | `${{postgres.…}}` refs | Postgres companion credentials; composed into `DATABASE_URL` at boot |
| `DATABASE_URL` | composed at boot | Postgres connection string (set it manually to override the composed one) |
| `NEXTAUTH_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}/api/v1/auth` | Public auth callback base URL |
| `NEXTAUTH_SECRET` | `${{secret(32)}}` | Session signing secret |
| `MEILI_HOST` | `http://${{meilisearch.RAILWAY_PRIVATE_DOMAIN}}:7700` | Full-text search backend |
| `MEILI_MASTER_KEY` | `${{meilisearch.MEILI_MASTER_KEY}}` | Shared search API key |
| `STORAGE_FOLDER` | `/data/data` (baked) | Archive storage path (on the volume) |
| `MAX_WORKERS` | `1` (baked) | Concurrent Chromium archival jobs |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | `linkwarden` / generated / `linkwarden` | Postgres companion credentials |
| `RAILWAY_RUN_UID` | `0` (postgres svc) | Run Postgres as root (root-owned volume) |
| `MEILI_ENV` / `MEILI_NO_ANALYTICS` | `production` / `true` | Meilisearch companion settings |

Applicable upstream variables (add in **Variables** as needed — [full list](https://docs.linkwarden.app/self-hosting/environment-variables)):

| Variable | What it does |
|---|---|
| `PAGINATION_TAKE_COUNT` | Links per page |
| `ARCHIVE_TAKE_COUNT` / `INDEX_TAKE_COUNT` | Links archived / indexed per worker batch |
| `BROWSER_TIMEOUT` / `AUTOSCROLL_TIMEOUT` | How long Chromium waits on a page (ms) |
| `MAX_LINKS_PER_USER` | Per-user link cap |
| `NEXT_PUBLIC_RSS_POLLING_INTERVAL_MINUTES` | RSS collection poll interval |
| `TEXT_CONTENT_LIMIT` | Max chars of page text stored per link |
| `OLLAMA_MODEL` / `NEXT_PUBLIC_OLLAMA_ENDPOINT_URL` | Local-AI auto-tagging |
| `OPENAI_API_KEY` / `OPENAI_MODEL` (+ Azure/Anthropic/OpenRouter/Perplexity variants) | Hosted-AI auto-tagging |
| `SPACES_KEY` / `SPACES_SECRET` / `SPACES_ENDPOINT` / `SPACES_BUCKET_NAME` / `SPACES_REGION` | S3-compatible archive storage instead of the volume |
| `EMAIL_SERVER` / `EMAIL_FROM` / `NEXT_PUBLIC_EMAIL_PROVIDER` | SMTP for invites and password resets |
| `PROXY` / `PROXY_USERNAME` / `PROXY_PASSWORD` / `PROXY_BYPASS` | Outbound proxy for archiving |
| `ALLOW_PRIVATE_NETWORK_ACCESS` / `ALLOW_INSECURE_TLS` | Archive intranet/self-signed sites |
| `PDF_MARGIN_TOP` / `PDF_MARGIN_BOTTOM` | PDF archive margins |
| `NEXT_PUBLIC_DISABLE_REGISTRATION` | Close sign-ups (build-time var in this image) |
| 40+ SSO providers (`NEXT_PUBLIC_<PROVIDER>_ENABLED` + client id/secret) | GitHub, Google, Authentik, Keycloak, generic OIDC, … |

## Credits

Application: [Linkwarden](https://github.com/linkwarden/linkwarden) by Daniel and contributors (AGPL-3.0). This repo only wraps their official image for one-click Railway deploys.
