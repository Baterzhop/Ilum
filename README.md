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

When `ILUM_MODEL` is not set, Ilum inspects the local Ollama catalog and deterministically selects a chat-capable model. Embedding/reranker models are excluded from chat selection. No model is downloaded automatically.

### Explicit model configuration

```bash
export ILUM_MODEL_URL="http://127.0.0.1:11434/v1/chat/completions"
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

`ILUM_OUTPUT_TOKENS` reserves output space in the context budget and is also sent to the OpenAI-compatible server as `max_tokens`. If the provider reports `finish_reason: length`, Ilum reports the limit explicitly instead of saving a partial answer as complete or executing a truncated tool call. Provider behavior, including whether reasoning tokens consume this limit, should be checked against the installed model server.

If a request cannot fit the current context budget, the runtime fails explicitly.

### Performance work

Development is focused on Ilum. LumiOrigin remains historical reference material for selective feature migration, especially spreadsheet tools; it is not a second active implementation line.

The first latency change removes unnecessary embedding calls, adds dense-failure cooldown, and enforces the reserved output budget in the model request. Streaming, explicit Ollama thinking profiles, full-request context accounting, and incremental chat persistence remain separate follow-up work. These changes do not claim a measured speedup on the target Mac.

For a physical check, compare the same short question with (1) no indexed documents, (2) an indexed text PDF, and (3) an unavailable embedding endpoint. Repeat the third case immediately to check sparse cooldown. Confirm citations still refer to the indexed document, Stop still cancels a generation, and an intentionally small output budget reports truncation explicitly. Record the exact build, Mac/RAM, Ollama/model version, cold versus warm start, and complete response time. CI mocks verify request counts and protocol behavior; they do not benchmark the installed LLM.

## Release discipline

`main` is intentionally conservative. Work happens in `integration/ilum-v1` through one Draft PR. Source code existing is not enough for a release claim: the exact release commit must pass Linux Core tests, macOS Core tests, native `IlumMac` tests/build/package, produce the exact-head macOS artifact, and then pass a physical macOS session against the actual local model and macOS permission environment.

Run the final physical gate from a clean checkout of the candidate SHA:

```bash
bash Scripts/acceptance.sh --guided
```

The runner records the exact Git SHA and writes a local Markdown evidence report under `dist/acceptance/`. `Overall: PASS` is required before the v1 Draft PR is considered ready to merge.

See [Architecture](Docs/ARCHITECTURE.md), [Status](Docs/STATUS.md), [Physical acceptance](Docs/PHYSICAL_ACCEPTANCE.md), [Український опис](Docs/README_UA.md), and [Magyar leírás](Docs/README_HU.md).
