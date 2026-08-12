# API Endpoints

All authenticated routes require `Authorization: Bearer <jwt>`.

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/v1/health` | No | Health check |
| POST | `/api/v1/auth/login` | No | Login with username/password, returns JWT |
| POST | `/api/v1/transform` | Yes | Run a transform operation |
| GET | `/api/v1/transform/options` | Yes | Dynamic Operation / Direction / Mode catalog from instruction keys |
| GET | `/api/v1/history` | Yes | Paginated history (`sort_by`, `sort_order`, `type`, `from`, `to`, `limit` default 50, `offset`) |
| GET | `/api/v1/history/:id` | Yes | Get single history record |
| DELETE | `/api/v1/history/:id` | Yes | Delete history record |
| GET | `/api/v1/stats` | Yes | Request counts by period and type |
| GET | `/api/v1/instructions` | Yes | List all instruction keys |
| POST | `/api/v1/instructions` | Yes | Create instruction from operation / direction / mode |
| GET | `/api/v1/instructions/:key` | Yes | Get instruction content |
| PUT | `/api/v1/instructions/:key` | Yes | Update instruction content |
| GET | `/api/v1/settings` | Yes | Get OpenRouter token and model |
| PATCH | `/api/v1/settings` | Yes | Update OpenRouter token and/or model |
| GET | `/api/v1/settings/models` | Yes | Search OpenRouter models (`q`) |
| GET | `/api/v1/settings/credits` | Yes | Remaining OpenRouter credits / key usage |
| DELETE | `/api/v1/settings/data` | Yes | Delete all history rows |

## History filters

- `type` — exact history type code (`en_fa`, `simplify`, …)
- `from` / `to` — `YYYY-MM-DD` inclusive calendar days (server local TZ; `to` is end-of-day inclusive)

Response:

```json
{
  "items": [ /* HistoryRecord[] */ ],
  "total": 237,
  "limit": 50,
  "offset": 0
}
```

## Transform options — `GET /api/v1/transform/options`

Derived from instruction keys (not hardcoded allow-lists):

| Key pattern | UI |
|-------------|-----|
| `en-to-fa-{mode}` | Translate · English → Persian · mode |
| `fa-to-en-{mode}` | Translate · Persian → English · mode |
| `refine-to-{style}` | Refine · style |
| `term-for-{style}` | Term · style |
| `compare-{lang}` | Compare · language |
| `grammar-{lang}` | Grammar · language |
| `simplify-en` | Simplify |
| `symptoms` | Symptoms |

Create new modes/styles via `POST /instructions`.

## Transform — `POST /api/v1/transform`

### Full request body shape

```json
{
  "operation": "translate|simplify|term|refine|symptoms|compare|grammar",
  "text": "...",
  "text1": "...",
  "text2": "...",
  "direction": "en-fa|fa-en",
  "mode": "<slug matching an instruction key>",
  "movie_name": "...",
  "language": "en|fa",
  "style": "<slug matching an instruction key>"
}
```

Only include fields relevant to the selected operation. Modes/styles must exist as instruction keys.

### Operations

| Operation | Required fields | History type |
|-----------|-----------------|--------------|
| `translate` | `text`, `direction`, `mode` (`movie_name` optional when mode is `movie`) | `en_fa` / `fa_en` |
| `simplify` | `text` | `simplify` |
| `term` | `text`, `style` (`language` optional) | `term_en` / `term_fa` |
| `refine` | `text`, `style` | `refine` |
| `symptoms` | `text` | `symptoms` |
| `compare` | `text1`, `text2` (`language` optional; defaults to `en`) | `compare_en` / `compare_fa` |
| `grammar` | `text` (`language` optional; defaults to `en`) | `grammar_en` / `grammar_fa` |

### Compare

```json
{
  "operation": "compare",
  "text1": "ask",
  "text2": "request",
  "language": "en"
}
```

- Do not send `text` for this operation
- History `input_text` is stored as `"ask vs request"`
- Instruction keys: `compare-en`, `compare-fa`

### Transform response

```json
{
  "id": "uuid",
  "type": "compare_en",
  "type_display": "Compare English",
  "input_text": "ask vs request",
  "result_text": "...",
  "model": "anthropic/claude-3.5-sonnet",
  "instruction_key": "compare-en",
  "created_at": "2026-07-16T17:00:00Z",
  "formatted_date": "2026:07:16 17:00"
}
```

### Stats

`StatsBucket` includes: `simplify`, `en_fa`, `fa_en`, `term`, `refine`, `symptoms`, `compare`, `grammar`, `total`.

## Settings — models and credits

### `GET /api/v1/settings/models?q=`

Proxies OpenRouter `GET /models`. Returns `{ id, name, context_length }[]`. Requires a configured API key.

### `GET /api/v1/settings/credits`

Tries OpenRouter `GET /credits` (management key) for account remaining (`total_credits - total_usage`). Falls back to `GET /key` for normal API keys (`usage`, optional `limit_remaining`).

## Create instruction — `POST /api/v1/instructions`

```json
{
  "operation": "translate",
  "direction": "en-fa",
  "mode": "poetry",
  "content": "optional custom prompt; default seed used if omitted"
}
```

Also supports `style` (refine/term) and `language` (compare).
