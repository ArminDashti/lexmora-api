# Docker deployment



API and PostgreSQL run from this repo. The web UI is deployed separately from [lexmora-webui](https://github.com/ArminDashti/lexmora-webui).



## Files



| File | Purpose |

|------|---------|

| `Dockerfile` | Go API image |

| `docker-compose.yml` | `postgres` + `api` on external `lexmora-net` |

| `run-on-docker.ps1` | Local or SSH deploy with ports/volumes/cleanup flags |

| `.docker/stack.manifest.json` | Image tags, container names, ports |



## Services



| Service | Container | Host port | Notes |

|---------|-----------|-----------|-------|

| `postgres` | `lexmora-postgres` | 5432 | Volume `postgres_data` |

| `api` | `lexmora-api` | 8080 | Runs migrations on startup |



## Local run



```powershell

.\run-on-docker.ps1

```



Or manually:



```bash

docker network create lexmora-net

docker compose up -d --build

```



Set `JWT_SECRET` in the environment before running if you need a non-default secret (compose default is for local dev only).



**Default login:** `armin` / `Lexmora@2024` (from compose env).



**CORS:** Set `CORS_ORIGINS` to include the web UI origin (e.g. `http://localhost:8082` for Docker web UI, `http://localhost:5173` for Vite dev).



## Full stack



1. Start this repo: `docker compose up -d --build`

2. Start [lexmora-webui](https://github.com/ArminDashti/lexmora-webui) on the same `lexmora-net` network with `API_HOST=lexmora-api`.

