# Ilum

Ilum is the canonical successor to Lumi: a local-first personal AI runtime for macOS built around one agent loop, durable local state, grounded knowledge retrieval, explicit tool permissions, and verifiable citations.

This repository intentionally starts with a clean history. Legacy Lumi versions remain reference material only.

## What Ilum is now

The `integration/ilum-v1` branch contains one coherent architecture instead of parallel Lumi One / V4 engines:

- Swift 6 `IlumCore`
- one `AgentRuntime`
- durable SQLite conversation storage
- durable SQLite Knowledge storage
- deterministic grounded lexical retrieval
- optional Ollama embeddings and persistent Float32 vector index
- sparse + dense Reciprocal Rank Fusion with automatic sparse fallback
- bounded context-window management
- provenance-preserving `[K#]` citations validated against the exact evidence snapshot
- native OpenAI-compatible model tool calls
- typed `ToolRuntime` and scoped `PermissionEngine`
- opaque user-file resource IDs; no model-supplied raw filesystem authority
- security-scoped macOS bookmarks
- PDFKit PDF text ingestion
- native SwiftUI macOS client with permission UI, citations and context telemetry

## Design invariants

- One `AgentRuntime` owns request execution.
- User input is persisted before model, retrieval, or tool work.
- Local files are reachable only through user-selected opaque resource IDs.
- Model-proposed tool calls never execute outside `ToolRuntime` / `PermissionEngine`.
- Retrieved document text is untrusted evidence, never an instruction channel.
- Citation markers are validated against the exact context snapshot used for the answer.
- Knowledge and conversations survive restart in SQLite.
- Dense retrieval is optional; sparse retrieval remains a working fallback.
- No shell, delete, unrestricted filesystem, arbitrary-network, or self-modification tool is enabled by default.

## Run on macOS

Requirements:

1. macOS 13 or newer.
2. Swift 6 / current Xcode command-line tools.
3. SQLite 3.
4. A local OpenAI-compatible chat server.

By default Ilum calls:

- chat: `http://127.0.0.1:8080/v1/chat/completions`
- chat model: `local`
- embeddings: `http://127.0.0.1:11434/api/embed`
- embedding model: `nomic-embed-text`

Override these with:

```bash
export ILUM_MODEL_URL="http://127.0.0.1:11434/v1/chat/completions"
export ILUM_MODEL="your-installed-model"
export ILUM_OLLAMA_EMBED_URL="http://127.0.0.1:11434/api/embed"
export ILUM_EMBED_MODEL="nomic-embed-text"
```

Then run:

```bash
cd Apps/IlumMac
swift run IlumMac
```

If the embedding endpoint/model is unavailable, PDF Knowledge still indexes and retrieval degrades to the lexical path. If the chat model endpoint is unavailable, Ilum surfaces the model error instead of silently fabricating a fallback answer.

## Context controls

Optional environment variables:

```bash
export ILUM_CONTEXT_WINDOW=8192
export ILUM_OUTPUT_TOKENS=1024
export ILUM_CONTEXT_SAFETY_TOKENS=512
```

The current user/tool turn is never silently dropped. If a safe request cannot fit the configured context window, the runtime fails explicitly.

## Release gate

`main` is intentionally conservative. The v1 integration branch should not be treated as released until Linux Core tests, macOS Core tests, and the native `IlumMac` test/build gate are green and a physical macOS local-model acceptance session is completed.

See `Docs/ARCHITECTURE.md` and `Docs/STATUS.md` for the exact architecture and remaining non-claims.
