# Translator API

REST API for the Translator app. Users authenticate with JWT, run transform operations (translate, simplify, term lookup, refine, symptoms) via OpenRouter, and manage history, instructions, stats, and settings.

The Vue web UI lives in the separate [translator-webui](https://github.com/ArminDashti/translator-webui) repository.

## Tech stack

- Go 1.22 + Gin REST API
- PostgreSQL 16
- OpenRouter for LLM calls
- Docker Compose for API + PostgreSQL

## Run

### Docker

```bash
docker network create translator-net
docker compose up -d --build
```

API: http://localhost:8080

### Local development

1. `docker compose up -d postgres`
2. `cp .env.example .env` and set `JWT_SECRET`
3. `go run ./cmd/server` → http://localhost:8080

Pair with the web UI dev server from `translator-webui` (`npm run dev` on port 5173).

Default login: `armin` / `Translator@2024`
