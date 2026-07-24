# Suggestion: DNS A record for lexmora-api.xaigrok.ir

**Why:** HAProxy, TLS cert, and the `lexmora-api` container are live on t3 (`2.144.27.74`), but public DNS has no A record for `lexmora-api.xaigrok.ir` (NXDOMAIN). `lexmora.xaigrok.ir` already points at the same IP.

**Action:** Add A record `lexmora-api.xaigrok.ir` → `2.144.27.74` (same TTL/style as `lexmora.xaigrok.ir`).

**Effort:** Minutes (DNS provider only).

**Also noticed:** Compose with empty `API_PUBLISH_PORT` still binds an ephemeral host port. Prefer omitting the `ports:` entry on server (expose-only) if you want zero host publish behind HAProxy.
