# Docker deployment

API and PostgreSQL run from this repo. The web UI is deployed separately from [translator-webui](https://github.com/ArminDashti/translator-webui).

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Go API image |
| `docker-compose.yml` | `postgres` + `api` on external `translator-net` |
| `.docker/stack.manifest.json` | Image tags, container names, ports |

## Services

| Service | Container | Host port | Notes |
|---------|-----------|-----------|-------|
| `postgres` | `translator-postgres` | 5432 | Volume `postgres_data` |
| `api` | `translator-api` | 8080 | Runs migrations on startup |

## Local run

```bash
docker network create translator-net
docker compose up -d --build
```

Set `JWT_SECRET` in the environment before running if you need a non-default secret (compose default is for local dev only).

**Default login:** `armin` / `Translator@2024` (from compose env).

**CORS:** Set `CORS_ORIGINS` to include the web UI origin (e.g. `http://localhost:8082` for Docker web UI, `http://localhost:5173` for Vite dev).

## Full stack

1. Start this repo: `docker compose up -d --build`
2. Start [translator-webui](https://github.com/ArminDashti/translator-webui) on the same `translator-net` network with `API_HOST=translator-api`.
