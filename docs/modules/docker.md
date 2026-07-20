# Docker deployment

API and PostgreSQL run from this repo. The web UI is deployed separately from [lexmora-webui](https://github.com/ArminDashti/lexmora-webui).

## Files

| Path | Purpose |
|------|---------|
| `.deploy/docker/Dockerfile` | Go API image (build context = repo root) |
| `.deploy/docker/docker-compose.yml` | `lexmora-pgsql` + `lexmora-api` on external `t3-net` |
| `.deploy/docker/docker-compose.publish.yml` | Optional host port mapping overlay |
| `.deploy/docker/run-on-docker-local.ps1` | Local Docker daemon deploy |
| `.deploy/docker/run-on-docker-local.yaml` | Local settings (no CLI flags) |
| `.deploy/docker/run-on-docker-server.ps1` | Remote SSH deploy (build locally, load on server) |
| `.deploy/docker/run-on-docker-server.yaml` | Remote settings (`ssh`, `ssh_key`, `remote_work_dir`) |
| `.deploy/docker/common.ps1` | Shared helpers |
| `run-on-docker-local.ps1` | Repo-root stub → `.deploy/docker/` |
| `run-on-docker-server.ps1` | Repo-root stub → `.deploy/docker/` |
| `.docker/stack.manifest.json` | Stack metadata (names, network, remote path) |

## Services

| Service | Container | Host port | Notes |
|---------|-----------|-----------|-------|
| `lexmora-pgsql` | `lexmora-pgsql` | (internal) | Volume `lexmora-pgsql-vol` |
| `lexmora-api` | `lexmora-api` | 8080 (local) | Runs migrations on startup; no host port on server (reverse proxy) |

## Local run

Edit `.deploy/docker/run-on-docker-local.yaml` if needed, then:

```powershell
.\run-on-docker-local.ps1
```

Or from `.deploy/docker/`:

```powershell
.\.deploy\docker\run-on-docker-local.ps1
```

The script builds the image, ensures the external `t3-net` network exists, and runs `docker compose up -d`.

**Default login:** `armin` / `Lexmora@2024` (from YAML / compose env).

**CORS:** Set `cors_origins` in `run-on-docker-local.yaml` to include the web UI origin (e.g. `http://localhost:5173` for Vite dev).

## Remote run

1. Fill `ssh` and `ssh_key` in `.deploy/docker/run-on-docker-server.yaml` (placeholders are rejected at runtime).
2. Run:

```powershell
.\run-on-docker-server.ps1
```

Flow: build image locally → `docker save` → SCP → remote `docker load` → sync compose files → remote `docker compose up -d` (no remote build). With `api_publish_port: ""`, only the overlay-free compose runs (API reachable on `t3-net` only).

## Full stack

1. Start this repo: `.\run-on-docker-local.ps1`
2. Start [lexmora-webui](https://github.com/ArminDashti/lexmora-webui) on the same `t3-net` network with `API_HOST=lexmora-api`.
