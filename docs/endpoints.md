# API Endpoints

All authenticated routes require `Authorization: Bearer <jwt>`.

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/v1/health` | No | Health check |
| POST | `/api/v1/auth/login` | No | Login with username/password, returns JWT |
| POST | `/api/v1/transform` | Yes | Run a transform operation |
| GET | `/api/v1/history` | Yes | List history (`sort_by`, `sort_order`, `limit`, `offset`) |
| GET | `/api/v1/history/:id` | Yes | Get single history record |
| DELETE | `/api/v1/history/:id` | Yes | Delete history record |
| GET | `/api/v1/stats` | Yes | Request counts by period and type |
| GET | `/api/v1/instructions` | Yes | List all instruction keys |
| GET | `/api/v1/instructions/:key` | Yes | Get instruction content |
| PUT | `/api/v1/instructions/:key` | Yes | Update instruction content |
| GET | `/api/v1/settings` | Yes | Get OpenRouter token and model |
| PATCH | `/api/v1/settings` | Yes | Update OpenRouter token and/or model |
| DELETE | `/api/v1/settings/data` | Yes | Delete all history rows |

## Transform — `POST /api/v1/transform`

### Full request body shape

```json
{
  "operation": "translate|simplify|term|refine|symptoms|compare",
  "text": "...",
  "text1": "...",
  "text2": "...",
  "direction": "en-fa|fa-en",
  "mode": "general|movie|formal|scientific|music",
  "movie_name": "...",
  "language": "en|fa",
  "style": "everyday|formal|slang"
}
```

Only include fields relevant to the selected operation.

### Operations

| Operation | Required fields | History type |
|-----------|-----------------|--------------|
| `translate` | `text`, `direction`, `mode` (+ `movie_name` if mode is `movie`) | `en_fa` / `fa_en` |
| `simplify` | `text` | `simplify` |
| `term` | `text`, `language`, `style` | `term_en` / `term_fa` |
| `refine` | `text`, `style` | `refine` |
| `symptoms` | `text` | `symptoms` |
| `compare` | `text1`, `text2`, `language` | `compare_en` / `compare_fa` |

### Translate

```json
{
  "operation": "translate",
  "text": "Hello",
  "direction": "en-fa",
  "mode": "general"
}
```

- `direction`: `en-fa` or `fa-en`
- `mode` (en-fa): `general`, `movie`, `formal`, `scientific`, `music`
- `mode` (fa-en): `general`, `formal`, `scientific`
- For `mode: "movie"`, also send `movie_name`

### Simplify

```json
{
  "operation": "simplify",
  "text": "The aforementioned individual subsequently departed."
}
```

### Term

```json
{
  "operation": "term",
  "text": "a short informal word for friend",
  "language": "en",
  "style": "slang"
}
```

- `language`: `en` or `fa`
- `style`: `everyday`, `formal`, `slang`

### Refine

```json
{
  "operation": "refine",
  "text": "hey can you send that file",
  "style": "formal"
}
```

- `style`: `everyday`, `formal`, `slang`

### Symptoms

```json
{
  "operation": "symptoms",
  "text": "migraine"
}
```

### Compare

Compare two words or phrases and explain how they differ.

```json
{
  "operation": "compare",
  "text1": "ask",
  "text2": "request",
  "language": "en"
}
```

| Field | Description |
|-------|-------------|
| `text1` | First word or phrase (required) |
| `text2` | Second word or phrase (required) |
| `language` | Explanation language: `en` or `fa` |

- Do not send `text` for this operation
- History `input_text` is stored as `"ask vs request"`
- Instruction keys: `compare-en`, `compare-fa`

### Transform response

```json
{
  "id": "uuid",
  "type": "compare_en",
  "type_display": "Compare EN",
  "input_text": "ask vs request",
  "result_text": "...",
  "model": "anthropic/claude-3.5-sonnet",
  "instruction_key": "compare-en",
  "created_at": "2026-07-16T17:00:00Z",
  "formatted_date": "2026:07:16 17:00"
}
```
