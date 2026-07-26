# Suggestion: retire legacy `.deploy/docker` deploy scripts

`.armin/docker-scripts/` is now the primary deploy entry. The older pair under `.deploy/docker/run-on-docker-*.ps1` (plus `common.ps1`) still works but duplicates the contract and can drift.

**Why:** Two deploy paths confuse agents and humans; stubs already point at `.armin`.

**Effort:** Low — delete or clearly mark legacy scripts after a short deprecation window; keep Dockerfile/compose in `.deploy/docker/`.
