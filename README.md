# Ilum

[Українська](Docs/README_UA.md) · [Magyar](Docs/README_HU.md) · English below

**Українською:** Ilum — локальний персональний ШІ для macOS, створений як канонічне продовження Lumi. Його мета — бути не просто чатом, а приватним помічником, який працює локально, пам’ятає дозволені користувачем факти й уподобання, читає власні документи, обґрунтовує відповіді джерелами та виконує дії лише через контрольовані інструменти й явні дозволи.

**Magyarul:** Az Ilum egy macOS-re készülő, helyben futó személyes MI-rendszer, a Lumi kanonikus utódja. A cél nem egy egyszerű chat, hanem egy privát asszisztens, amely internetfüggőség nélkül működhet, engedéllyel tartósan emlékezhet, saját dokumentumokat használhat forrásként, ellenőrizhető hivatkozásokat adhat, és műveleteket csak szabályozott eszközökön és jogosultsági kapukon keresztül hajthat végre.

## English

Ilum is the canonical successor to Lumi: a local-first personal AI runtime for macOS built around one agent loop, durable local state, grounded knowledge retrieval, permission-gated tools, persistent personal memory, and verifiable citations.

Legacy Lumi versions are reference material only. Ilum has one product architecture and one integration line instead of parallel Lumi One / V4 engines.

## What is already in the v1 integration line

- native SwiftUI `IlumMac` application
- Swift 6 `IlumCore`
- one `AgentRuntime`
- durable multi-conversation SQLite history with New Chat and chat switching
- durable Personal Memory for facts, preferences, goals, routines, and notes
- explicit user approval before Personal Memory writes or deletion
- security-scoped macOS file selection and opaque file resource IDs
- PDFKit ingestion into a durable Knowledge store
- persistent SQLite FTS5 sparse retrieval where available, with deterministic Swift lexical fallback
- optional local Ollama embeddings and persistent Float32 vector index
- sparse + dense Reciprocal Rank Fusion with automatic sparse fallback
- context-window budgeting
- exact `[K#]` citation validation against the evidence snapshot used for the answer
- native OpenAI-compatible local model tool calls
- local Ollama model discovery that rejects embedding-only models as chat candidates
- explicit unavailable-model behavior instead of fabricated fallback answers
- multilingual same-language response policy
- Linux/macOS Core CI plus native macOS build/test/package gates

## Security invariants

- User input is persisted before model, retrieval, or tool work.
- Local files enter only through explicit user selection and opaque resource IDs.
- Model-proposed actions never bypass `ToolRuntime` / `PermissionEngine`.
- Retrieved documents and tool output are untrusted data, not higher-authority instructions.
- Personal Memory reads may be allowed by local policy; writes and deletion require explicit approval.
- Citation markers are validated against the exact grounded-context snapshot for that turn.
- No shell, unrestricted filesystem, arbitrary-network, or self-modification tool is enabled by default.

## Repository layout

```text
Apps/IlumMac/          Native macOS SwiftUI application
Packages/IlumCore/    Runtime, persistence, RAG, memory, tools, model gateway
Scripts/              Doctor, run and native .app packaging helpers
Docs/                  Architecture, status and localized project descriptions
.github/workflows/     Linux + macOS CI gates
```

## Quick start on macOS

Requirements: macOS 13+, current Xcode Command Line Tools / Swift 6, and a local OpenAI-compatible model server. Ollama is the default local setup.

From the repository root, first check the machine and local model:

```bash
bash Scripts/doctor.sh
```

For a real local-model smoke request as well:

```bash
bash Scripts/doctor.sh --chat
```

Then launch Ilum:

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

For a specific local model/server:

```bash
export ILUM_MODEL_URL="http://127.0.0.1:11434/v1/chat/completions"
export ILUM_MODEL="your-installed-local-model"
export ILUM_OLLAMA_EMBED_URL="http://127.0.0.1:11434/api/embed"
export ILUM_EMBED_MODEL="nomic-embed-text"
```

If dense embeddings are unavailable, Knowledge remains usable through sparse retrieval. If the chat model is unavailable, Ilum reports the failure instead of silently inventing an answer.

## Context controls

```bash
export ILUM_CONTEXT_WINDOW=8192
export ILUM_OUTPUT_TOKENS=1024
export ILUM_CONTEXT_SAFETY_TOKENS=512
```

The current user/tool turn is never silently removed. If a request cannot fit safely, the runtime fails explicitly.

## Release discipline

`main` is intentionally conservative. Work happens in `integration/ilum-v1` through one Draft PR. Source code existing is not enough for a release claim: the exact release commit must pass Linux Core tests, macOS Core tests, native `IlumMac` tests/build/package, and a physical macOS local-model acceptance session.

See [Architecture](Docs/ARCHITECTURE.md), [Status](Docs/STATUS.md), [Український опис](Docs/README_UA.md), and [Magyar leírás](Docs/README_HU.md).
