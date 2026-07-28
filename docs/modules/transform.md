# Transform module

**Package:** `internal/service/transform.go` + `internal/handler/transform.go`

Maps UI operation selections to instruction keys (must exist in DB), calls OpenRouter, and saves history.

Dropdown options are **not hardcoded** — `GET /transform/options` builds them from instruction keys.

## Operation → instruction key mapping

| Operation | Params | Instruction key | History type |
|-----------|--------|-----------------|--------------|
| translate | en-fa + mode | `en-to-fa-{mode}` | English-Persian |
| translate | fa-en + mode | `fa-to-en-{mode}` | Persian-English |
| simplify | — | `simplify-en` | Simplify |
| term | style (+ optional language) | `term-for-{style}` | Term English / Persian |
| refine | style | `refine-to-{style}` | Refine |
| symptoms | — | `symptoms` | Symptoms |
| compare | language | `compare-{lang}` | Compare English / Persian |

New modes/styles are created via `POST /instructions` (Instructions page).

## Dependencies

- `SettingsService` for API key and model
- `InstructionService` for system prompts
- `OpenRouterClient` for LLM calls
- `HistoryRepository` for persistence
