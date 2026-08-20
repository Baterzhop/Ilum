# Ilum

[Українська](Docs/README_UA.md) · [Magyar](Docs/README_HU.md) · English below

**Українською:** Ilum — локальний персональний ШІ для macOS, створений як канонічне продовження Lumi. Його мета — бути не просто чатом, а приватним помічником, який працює локально, пам’ятає дозволені користувачем факти й уподобання, читає власні документи, обґрунтовує відповіді джерелами та виконує дії лише через контрольовані інструменти й явні дозволи.

**Magyarul:** Az Ilum egy macOS-re készülő, helyben futó személyes MI-rendszer, a Lumi kanonikus utódja. A cél nem egy egyszerű chat, hanem egy privát asszisztens, amely internetfüggőség nélkül működhet, engedéllyel tartósan emlékezhet, saját dokumentumokat használhat forrásként, ellenőrizhető hivatkozásokat adhat, és műveleteket csak szabályozott eszközökön és jogosultsági kapukon keresztül hajthat végre.

## English

Ilum is the canonical successor to Lumi: a local-first personal AI runtime for macOS built around one agent loop, durable local state, grounded knowledge retrieval, permission-gated tools, persistent personal memory, and verifiable citations.

This repository intentionally starts with a clean history. Legacy Lumi versions remain reference material only. There is one product architecture, not parallel Lumi One / V4 engines.

## Product goal

Ilum is intended to become a private local personal AI rather than a chat wrapper. The v1 architecture is designed around these capabilities:

- local/offline-first model execution; no cloud API is required by the architecture
- multilingual conversation with language switching and same-language replies by default
- durable conversations in SQLite
- durable Personal Memory for stable facts, preferences, goals, routines, and notes
- explicit approval before Personal Memory is written or deleted
- local document Knowledge with provenance-preserving PDF ingestion
- lexical retrieval that always works plus optional local dense embeddings
- sparse + dense Reciprocal Rank Fusion with automatic sparse fallback
- bounded context-window management instead of silently overflowing the model
- exact `[K#]` citation validation against the evidence used for a turn
- native OpenAI-compatible local model tool calls
- typed `ToolRuntime` and scoped `PermissionEngine`
- opaque user-file resource IDs; model output cannot invent filesystem authority
- security-scoped macOS file bookmarks
- native SwiftUI macOS client with permission UI, citations, context telemetry, and file/Knowledge controls

## Security invariants

- One `AgentRuntime` owns request execution.
- User input is persisted before model, retrieval, or tool work.
- Local files enter through explicit user selection and opaque resource IDs.
- Model-proposed actions never bypass `ToolRuntime` / `PermissionEngine`.
- Retrieved documents and tool output are data, not higher-authority instructions.
- Citation markers are validated against the exact context snapshot used for the answer.
- Personal Memory reads may be locally auto-authorized; writes and deletion require explicit approval.
- No shell, delete, unrestricted filesystem, arbitrary-network, or self-modification tool is enabled by default.

## Repository layout

```text
Apps/IlumMac/          Native macOS SwiftUI application
Packages/IlumCore/    Platform-neutral runtime, storage, RAG, memory, tools, model gateway
Docs/                  Architecture, status and localized project descriptions
.github/workflows/     Linux + macOS CI gates
```

## Run on macOS

Requirements:

1. macOS 13 or newer.
2. Swift 6 / current Xcode command-line tools.
3. SQLite 3.
4. A local OpenAI-compatible chat server. Ollama can expose an OpenAI-compatible endpoint.

By default Ilum calls localhost endpoints. Override configuration without changing code:

```bash
export ILUM_MODEL_URL="http://127.0.0.1:11434/v1/chat/completions"
export ILUM_MODEL="your-installed-local-model"
export ILUM_OLLAMA_EMBED_URL="http://127.0.0.1:11434/api/embed"
export ILUM_EMBED_MODEL="nomic-embed-text"
```

Then run:

```bash
cd Apps/IlumMac
swift run IlumMac
```

If dense embeddings are unavailable, Knowledge degrades to lexical retrieval. If the chat model is unavailable, Ilum surfaces the error instead of fabricating a fallback response.

## Context controls

```bash
export ILUM_CONTEXT_WINDOW=8192
export ILUM_OUTPUT_TOKENS=1024
export ILUM_CONTEXT_SAFETY_TOKENS=512
```

The current turn is never silently dropped. If a request cannot fit safely, the runtime fails explicitly.

## Release discipline

`main` is intentionally conservative. Work happens in `integration/ilum-v1` through one draft PR. A feature is not called complete because code exists; it must pass Linux Core tests, macOS Core tests, native IlumMac tests/build, and where applicable a physical local-model acceptance session.

See [Architecture](Docs/ARCHITECTURE.md), [Status](Docs/STATUS.md), [Український опис](Docs/README_UA.md), and [Magyar leírás](Docs/README_HU.md).
