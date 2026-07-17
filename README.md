# Lexmora API

Go REST API for the Lexmora app: AI-powered English ↔ Persian transforms via OpenRouter, with JWT auth, history, instructions, stats, and settings.

Companion frontend: [lexmora-webui](https://github.com/ArminDashti/lexmora-webui)

## Stack

- Go 1.22 (Gin)
- PostgreSQL 16
- OpenRouter (API key stored in DB via settings)

## Prerequisites

- Go 1.22+
- Docker (PostgreSQL)

## Setup

1. Copy environment file:

```bash
cp .env.example .env
```

2. Edit `.env` — set `JWT_SECRET` to a long random string.

3. Start PostgreSQL and API:

```bash
docker network create lexmora-net 2>/dev/null || true
docker compose up -d
```

Or run PostgreSQL only and start the API locally:

```bash
docker compose up -d postgres
go run ./cmd/server
```

API listens on [http://localhost:8080](http://localhost:8080).

### Development with the web UI

Run this API on port 8080, then start the web UI dev server from the `lexmora-webui` repo (`npm run dev` on port 5173). Set `CORS_ORIGINS` to include the Vite origin if needed.

## Default login

| Field    | Value            |
|----------|------------------|
| Username | `armin`          |
| Password | `Lexmora@2024` |

Override via `DEFAULT_USERNAME` and `DEFAULT_PASSWORD` in `.env` (only used on first boot when no users exist).

## Configuration

| Variable | Description |
|----------|-------------|
| `PORT` | HTTP port (default `8080`) |
| `JWT_SECRET` | Secret for signing login tokens |
| `DATABASE_URL` | PostgreSQL connection string |
| `CORS_ORIGINS` | Comma-separated allowed browser origins |
| `STATIC_DIR` | Optional path to serve a built SPA (leave unset for API-only) |
| `DEFAULT_USERNAME` | Initial admin username |
| `DEFAULT_PASSWORD` | Initial admin password |

OpenRouter API key and model are configured through the Settings API (stored in the database).

## API overview

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/v1/health` | No | Health check |
| POST | `/api/v1/auth/login` | No | Login |
| POST | `/api/v1/transform` | JWT | Run operation |
| GET | `/api/v1/history` | JWT | List history |
| GET | `/api/v1/history/:id` | JWT | Get history item |
| DELETE | `/api/v1/history/:id` | JWT | Delete history item |
| GET | `/api/v1/stats` | JWT | Usage statistics |
| GET | `/api/v1/instructions` | JWT | List instructions |
| GET | `/api/v1/instructions/:key` | JWT | Get instruction |
| PUT | `/api/v1/instructions/:key` | JWT | Update instruction |
| GET | `/api/v1/settings` | JWT | Get settings |
| PATCH | `/api/v1/settings` | JWT | Update settings |
| DELETE | `/api/v1/settings/data` | JWT | Clear all history |

See [docs/endpoints.md](docs/endpoints.md) for details.

## Project structure

```
cmd/server/           API entry point
internal/config/      Environment configuration
internal/db/          Database pool and migrations
internal/domain/      Entities and DTOs
internal/handler/     HTTP handlers
internal/middleware/  JWT auth middleware
internal/repository/  Data access
internal/service/     Business logic
migrations/           SQL migrations
instructions/         Reference prompt templates
```

## Docker

Build and run API + PostgreSQL:

```bash
docker network create lexmora-net
docker compose up -d --build
```

The web UI container (separate repo) should join the same `lexmora-net` network and proxy `/api` to the `lexmora-api` service hostname.
