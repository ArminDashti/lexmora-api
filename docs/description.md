# Lexmora API

REST API for the Lexmora app. Users authenticate with JWT, run transform operations (translate, simplify, term lookup, refine, symptoms, compare) via OpenRouter, and manage history, instructions, stats, and settings.

The Vue web UI lives in the separate [lexmora-webui](https://github.com/ArminDashti/lexmora-webui) repository.

## Tech stack

- Go 1.22 + Gin REST API
- PostgreSQL 16
- OpenRouter for LLM calls
- Docker Compose for API + PostgreSQL

## Run

### Docker

```powershell
.\run-on-docker-local.ps1
```

Settings: `.armin/docker-scripts/run-on-docker-local.yaml`. Remote: `.\run-on-docker-server.ps1` (fill `ssh` first). Dockerfile/compose live under `.deploy/docker/`.

API: http://localhost:8080

### Local development

1. `.\run-on-docker-local.ps1` (or Postgres only via compose in `.deploy/docker/`)
2. `cp .env.example .env` and set `JWT_SECRET`
3. `go run ./cmd/server` → http://localhost:8080

Pair with the web UI dev server from `lexmora-webui` (`npm run dev` on port 5173).

Default login: `armin` / `IUpe8SqXxtJrEJxZ`
