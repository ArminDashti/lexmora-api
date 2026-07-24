# Suggestion: keep CORS origins in one place

Local Docker CORS is duplicated across `.env.example`, `internal/config/config.go` defaults, `.deploy/docker/docker-compose.yml`, and `.deploy/docker/run-on-docker-local.yaml`. `.armin/docker-scripts/` does not set `CORS_ORIGINS`, so compose defaults are the real source for that path.

**Why:** Drift caused `8082` to be missing from the running API while docs and `config.go` still listed it.

**Effort:** Low — document a single canonical list, or have `.armin` YAML pass `cors_origins` like the legacy deploy scripts.
