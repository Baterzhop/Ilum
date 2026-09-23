# Ilum

[Українська](Docs/README_UA.md) · [Magyar](Docs/README_HU.md) · English below

**Українською:** Ilum — локальний персональний ШІ для macOS і канонічне продовження Lumi. Це не просто чат, а приватний локальний runtime з довговічними розмовами, контрольованою Personal Memory, локальним Knowledge/RAG, перевіреними цитатами та інструментами, які виконуються тільки через явні програмні межі дозволів.

**Magyarul:** Az Ilum a Lumi kanonikus utódja: macOS-re épülő, helyben futó személyes MI-runtime. Nem egyszerű chat, hanem tartós beszélgetéseket, engedélyköteles Personal Memory réteget, helyi Knowledge/RAG rendszert, ellenőrzött hivatkozásokat és szabályozott eszközvégrehajtást biztosító privát asszisztens-alap.

## English

Ilum is the canonical successor to Lumi: a local-first personal AI runtime for macOS built around one agent loop, durable local state, grounded knowledge retrieval, permission-gated tools, persistent personal memory, and verifiable citations.

Legacy Lumi branches are reference material only. Ilum has one product architecture and one integration line instead of parallel Lumi One / Lumi V4 engines.

## What is already in the v1 integration line

- native SwiftUI `IlumMac` application
- Swift 6 `IlumCore`
- one `AgentRuntime`
- durable multi-conversation SQLite history with New Chat and chat switching
- conversation-scoped active-run lease: concurrent turns cannot interleave inside one conversation while different conversations remain independently runnable
- durable permission-gated turns that survive restart without duplicating the user message
- exact grounded-context snapshot preservation across permission/restart pauses
- live permission revalidation after restore
- durable Personal Memory for facts, preferences, goals, routines, and notes
- explicit approval before Personal Memory writes or deletion
- security-scoped macOS file selection and opaque file resource IDs
- PDFKit ingestion into a durable Knowledge store
- persistent SQLite FTS5 sparse retrieval where available, with deterministic Swift lexical fallback
- optional local Ollama embeddings and persistent Float32 vector index
- sparse + dense Reciprocal Rank Fusion with automatic sparse fallback
- visible Knowledge retrieval mode in the macOS UI (`hybrid`, `sparse fallback`, `sparse`, `unavailable`)
- context-window budgeting
- exact `[K#]` citation validation against the evidence snapshot used for the answer
- native OpenAI-compatible local model tool calls
- local Ollama model discovery that rejects embedding/reranker models as chat candidates
- explicit unavailable-model behavior instead of fabricated fallback answers
- multilingual same-language response policy
- versioned conversation-schema migrations with fail-closed newer/non-contiguous migration protection
- Linux/macOS Core CI plus native macOS build/test/package gates
- guided physical macOS acceptance runner with an exact-SHA evidence report

## Security invariants

- User input is persisted before model, retrieval, or tool work.
- Local files enter only through explicit user selection and opaque resource IDs.
- Model-proposed actions never bypass `ToolRuntime` / `PermissionEngine`.
- Retrieved documents and tool output are untrusted data, not higher-authority instructions.
- Pending permission turns are durable; restart resumes the original ToolCall and original grounded evidence rather than silently re-running retrieval.
- Restored permission display is recomputed from the live registered tool; serialized permission text is not authority.
- Session grants are limited to read-only capabilities and remain scoped to the exact resource.
- One-shot grants are bound to the exact `ToolCall.id`, so approval for one concrete execution cannot be consumed by another call on the same resource.
- Same-conversation turns cannot interleave across actor reentrancy.
- Citation markers are validated against the exact grounded-context snapshot for that turn.
- No shell, unrestricted filesystem, arbitrary-network, or self-modification tool is enabled by default.

## Repository layout

```text
Apps/IlumMac/          Native macOS SwiftUI application
Packages/IlumCore/    Runtime, persistence, RAG, memory, tools, model gateway
Scripts/              Doctor, run, packaging and physical-acceptance helpers
Docs/                 Architecture, status, acceptance and localized descriptions
.github/workflows/    Linux + macOS CI gates
```

## Quick start on macOS

Requirements: macOS 13+, current Xcode Command Line Tools / Swift 6, and a local OpenAI-compatible model server. Ollama is the default local setup.

From the repository root, check the machine and local model:

```bash
bash Scripts/doctor.sh
```

For a real local-model smoke request:

```bash
bash Scripts/doctor.sh --chat
```

Launch Ilum from source:

```bash
bash Scripts/run.sh
```

Or build a native application bundle:

```bash
bash Scripts/build-app.sh
open dist/Ilum.app
```

When `ILUM_MODEL` is not set, Ilum inspects the local Ollama catalog. A saved selection for that endpoint wins; otherwise it starts with the smallest positive known model file size, with name preferences used only as tie-breakers. Unknown/zero sizes rank after known sizes. The picker and automatic selection require Ollama `/api/show` to advertise both `completion` and `tools`; missing/unavailable metadata is not guessed from the name. Metadata requests run only on discovery/refresh, at most three at once. Explicit `ILUM_MODEL` remains an override. Size is a resource-use heuristic, not a guarantee of speed or answer quality. No model is downloaded automatically.

Use **Model** in the composer to choose an installed model and **Refresh models** after installing/removing one in Ollama. The selection survives restart and is scoped to the endpoint. If a saved model disappears, Ilum visibly falls back to the automatic choice. Selection and refresh are disabled during generation, indexing, or pending permission. `ILUM_MODEL` takes precedence and locks the picker; unset it to use the UI. Custom non-Ollama endpoints keep explicit configuration.

### Explicit model configuration

```bash
export ILUM_MODEL_URL="http://127.0.0.1:11434/api/chat"
export ILUM_MODEL="your-installed-local-model"
export ILUM_OLLAMA_EMBED_URL="http://127.0.0.1:11434/api/embed"
export ILUM_EMBED_MODEL="nomic-embed-text"
```

If dense embeddings become unavailable during search, Knowledge continues through sparse retrieval and the UI visibly reports sparse fallback. Interactive embedding requests use a 3-second request timeout; after a dense-search failure, subsequent searches use sparse retrieval for a 30-second cooldown before trying dense again. Document indexing retains its longer 60-second request timeout. A timeout is not a guarantee of total end-to-end response time.

An empty Knowledge library does not run retrieval. When the vector index has no entries for the configured embedding model, search stays sparse without requesting an embedding. Adding or removing indexed vectors is recognized without restarting the app. If the chat model is unavailable, Ilum reports the failure instead of silently inventing an answer.

## Context controls

```bash
export ILUM_CONTEXT_WINDOW=8192
export ILUM_OUTPUT_TOKENS=1024
export ILUM_CONTEXT_SAFETY_TOKENS=512
```

`ILUM_OUTPUT_TOKENS` reserves output space in the context budget and is sent as native Ollama `options.num_predict` or OpenAI-compatible `max_tokens`. If the provider reports `done_reason: length` or `finish_reason: length`, Ilum reports the limit explicitly instead of saving a partial answer as complete or executing a truncated tool call. Provider behavior, including whether reasoning tokens consume this limit, should be checked against the installed model server.

If a request cannot fit the current context budget, the runtime fails explicitly.

### Performance work

Development is focused on Ilum. LumiOrigin remains historical reference material for selective feature migration, especially spreadsheet tools; it is not a second active implementation line.

Ilum skips unnecessary embedding calls, applies a dense-failure cooldown, and enforces the reserved output budget. Native Ollama chat now streams text as it arrives. The composer offers **Fast** (default), **Thinking**, and **Model default**; the choice is saved locally. Fast sends `think: false`, Thinking sends `think: true`, and Model default omits the field. GPT-OSS uses `low`/`high` instead of booleans and cannot fully disable thinking. Unsupported settings produce an explicit server error; use Model default for a model without thinking support.

The default endpoint is `/api/chat`. An explicitly configured OpenAI-compatible `/v1/chat/completions` endpoint retains buffered responses and has no thinking selector. Change an old Ollama `ILUM_MODEL_URL` export to `/api/chat` (or remove it) to enable the new behavior. `doctor.sh --chat` checks the native Fast request by default, using a buffered smoke response; it does not measure UI streaming or read the app's saved mode.

The UI shows the saved user message immediately, current activity, elapsed seconds, and a temporary answer preview. Stop cancels the network generation, including generation after approve/deny. Already completed authorized tool actions are retained. A partial, cancelled, malformed, or length-truncated answer never becomes a completed chat entry; tool calls require a complete valid stream before permission/execution. The source bar appears only after citation validation.

Expand the performance summary below the response controls to inspect elapsed time, time to first visible text, and per-call model loading, prompt processing, token generation, and tokens/second when Ollama supplies them. **Copy performance report** copies these measurements plus OS/RAM information, without prompt or document text. The total covers one send or approve/deny operation; waiting for permission is excluded, and first visible text can be a tool preamble. Multiple calls use total generated tokens divided by total generation time, not an average of rates. Missing measurements remain unavailable. Failed/cancelled operations retain that status, and incomplete calls do not invent final server statistics. OpenAI-compatible responses report client elapsed time only.

For an A/B comparison, open a new chat for each model, send the same short prompt, and save the reports for the first and second request. Compare answer quality and tool behavior as well as time. `doctor.sh` follows the smaller-model automatic policy but does not read the UI's saved selection; set `ILUM_MODEL` to test the same model explicitly.

Full-request context accounting and incremental chat persistence remain follow-up work. These changes do not claim a measured speedup on the target Mac.

For a physical check, compare the same short question with (1) no indexed documents, (2) an indexed text PDF, and (3) an unavailable embedding endpoint. Repeat the third case immediately to check sparse cooldown. Confirm citations still refer to the indexed document, Stop still cancels a generation, and an intentionally small output budget reports truncation explicitly. Record the exact build, Mac/RAM, Ollama/model version, cold versus warm start, time to first visible text, and complete response time in Fast and Thinking. Check Stop both before the first token and after a permission continuation. CI tests verify protocol behavior and actual incremental URLSession delivery using a loopback HTTP server; they do not benchmark the installed LLM.

## Release discipline

`main` is intentionally conservative. Work happens in `integration/ilum-v1` through one Draft PR. Source code existing is not enough for a release claim: the exact release commit must pass Linux Core tests, macOS Core tests, native `IlumMac` tests/build/package, produce the exact-head macOS artifact, and then pass a physical macOS session against the actual local model and macOS permission environment.

Run the final physical gate from a clean checkout of the candidate SHA:

```bash
bash Scripts/acceptance.sh --guided
```

The runner records the exact Git SHA and writes a local Markdown evidence report under `dist/acceptance/`. `Overall: PASS` is required before the v1 Draft PR is considered ready to merge.

See [Architecture](Docs/ARCHITECTURE.md), [Status](Docs/STATUS.md), [Physical acceptance](Docs/PHYSICAL_ACCEPTANCE.md), [Український опис](Docs/README_UA.md), and [Magyar leírás](Docs/README_HU.md).
