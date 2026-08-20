# Ilum v1 status

Updated: 2026-08-20

## Implemented in `integration/ilum-v1`

- [x] clean canonical repository and single integration branch
- [x] Swift 6 `IlumCore`
- [x] single `AgentRuntime`
- [x] durable conversation persistence in SQLite
- [x] visible storage Safe Mode
- [x] native OpenAI-compatible chat/tool-call transport
- [x] typed ToolRegistry / ToolRuntime
- [x] scoped one-time/session permissions
- [x] opaque user-file resource boundary
- [x] macOS security-scoped bookmark catalog
- [x] protected UTF-8 file-read tool
- [x] PDFKit text extraction
- [x] deterministic chunking with page provenance
- [x] durable Knowledge store
- [x] deterministic lexical grounded retrieval
- [x] bounded untrusted grounded context
- [x] fail-closed citation validation
- [x] context-window budgeting
- [x] optional Ollama embedding provider
- [x] persistent Float32 vector index
- [x] sparse+dense Reciprocal Rank Fusion
- [x] sparse fallback if dense retrieval fails
- [x] native SwiftUI macOS client
- [x] permission UI
- [x] PDF Knowledge indexing UI
- [x] source citation UI
- [x] context-budget telemetry
- [x] Linux/macOS Core CI definitions
- [x] macOS app test/build CI definition

## Release blockers

The branch is intentionally not merged to `main` until these are evidenced, not merely assumed:

- [ ] GitHub Linux `IlumCore` test job is green on the current head.
- [ ] GitHub macOS `IlumCore` test job is green on the current head.
- [ ] GitHub macOS `IlumMac` test + build job is green on the current head.
- [ ] Physical macOS run opens the app and restores a conversation after restart.
- [ ] Physical local-model run produces a normal chat response.
- [ ] Physical permission flow proves selected file content is unavailable to the model until approval.
- [ ] Physical PDF test indexes a document, retrieves evidence, and renders only validated `[K#]` citations.
- [ ] Dense-offline test confirms sparse retrieval still answers Knowledge queries.

## Explicit non-claims

The current code does not claim scanned-PDF OCR, ANN/HNSW scale, cloud sync, voice/avatar, autonomous web browsing, shell access, arbitrary external actions, or self-modifying code.

Token streaming / STOP cancellation from the experimental V4 line has not yet been promoted into the canonical AgentRuntime because the first Ilum v1 release prioritizes a single safe tool/permission protocol. It should be added only without creating a second execution engine.

## Legacy source policy

`Baterzhop/LumiOrigin` is reference material. New production work belongs in `Baterzhop/Ilum`; Lumi One/V3/V4 branches are not separate product tracks anymore.
