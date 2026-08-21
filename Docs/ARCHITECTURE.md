# Ilum v1 architecture

## Product boundary

Ilum is a local-first macOS AI runtime. The model is not the application security boundary. It can produce text or propose one typed tool call; durable state, permissions, file authority, retrieval, and side effects are controlled by code-owned runtimes.

## Runtime flow

```text
User
  -> IlumMac
  -> AgentRuntime
       -> persist user turn (SQLite)
       -> retrieve immutable grounded-context snapshot
       -> ContextBudgetManager
       -> OpenAICompatibleProvider
            -> final answer
            OR typed ToolCall
       -> ToolRuntime
            -> PermissionEngine
            -> approved Tool only
       -> validate [K#] citations
       -> persist assistant/tool result (SQLite)
```

A grounded-context snapshot is created once for a user turn and reused across tool/permission pauses. If a permission-gated turn is interrupted by app termination, Ilum persists that exact evidence snapshot with the pending ToolCall and resumes from it after restart instead of running retrieval again.

## Trust boundaries

### Model

Untrusted decision component. It has no direct file handle, SQLite connection, permission grant, vector index, or arbitrary process execution capability.

### ToolRuntime

The only execution route for model-proposed actions. Unknown tool name/version fails closed. Tool input is decoded against typed Codable models and advertised JSON schemas.

For a restored pending action, `ToolRuntime` recomputes the permission request from the currently registered tool and the persisted ToolCall. Serialized permission reason/display text is not treated as authority. The restored action fails closed if the persisted capability/resource identity does not match the live tool request.

### PermissionEngine

Grants are scoped by capability + exact resource and by duration (`once` or `session`). Chat prose cannot create a grant. A one-time grant is consumed by authorization. Session grants are limited to read-only capabilities; writes and other side effects require a fresh one-shot decision.

### User files

macOS `NSOpenPanel` selection is registered by `SecurityScopedFileCatalog`. The model receives an opaque `UserFileResourceID`, never authority to invent a filesystem path. Security-scoped bookmark data remains platform-side.

### Knowledge

PDFKit extracts text only from already registered file resources. Knowledge chunks preserve document, source resource, ordinal, and page provenance. Retrieved source text is serialized as explicitly untrusted evidence.

## Persistence

- conversations/messages: SQLite + WAL
- permission-gated pending agent turns: versioned SQLite snapshots containing the ToolCall, an audit copy of the permission request, completed tool-step count, conversation state and exact grounded-context snapshot
- Knowledge documents/chunks: SQLite + WAL
- dense vectors: SQLite Float32 blobs
- security-scoped bookmarks: local catalog under Application Support

Conversation schema changes are applied by numbered migrations. Opening a database containing an unknown newer migration version fails closed instead of allowing an older binary to write into a schema it does not understand.

When an approved or denied pending action is resolved, the resulting tool-history event and deletion of the pending record are committed together by the SQLite conversation store. Storage startup failure enters visible Safe Mode rather than silently replacing durable persistence with RAM.

## Crash/restart semantics

A permission pause is a durable runtime state, not a transient UI modal:

1. user input is persisted before model/tool work;
2. ToolCall + permission gate + evidence snapshot are persisted before the approval is exposed;
3. restart restores the same pending ID and grounded evidence;
4. the live tool recomputes the permission request before approval can execute;
5. approval/denial resolution is persisted transactionally with the tool-history event.

Current v1 side-effect tools are local Personal Memory writes/deletion; those operations are idempotent under retry. Future external side-effect tools must add an execution/idempotency ledger before they are admitted to production authority.

## Retrieval

Current baseline:

1. deterministic Unicode lexical retrieval (BM25-style correctness baseline),
2. optional dense embedding retrieval through an `EmbeddingProvider`,
3. persistent exact cosine vector search,
4. Reciprocal Rank Fusion,
5. automatic lexical fallback when embeddings are unavailable.

Exact vector scanning is intentionally correctness-first. An ANN/HNSW implementation can later replace the vector-index implementation without changing AgentRuntime authority or citation semantics.

## Context management

`ContextBudgetManager` reserves output and safety space, accounts for grounded evidence, and packs the newest usable history into the remaining model window. The newest turn is never silently discarded. An oversized unsafe request fails explicitly.

## Citations

Evidence is labeled `[K1]`, `[K2]`, etc. The answer is scanned after generation. Any marker that does not exist in the exact context snapshot fails closed instead of being displayed as a trusted citation.

## Deliberately absent from v1 authority

Ilum v1 does not enable:

- shell execution
- file deletion by the model
- unrestricted directory access
- arbitrary HTTP/network action tools
- automatic code modification / SelfCoder
- background autonomous action loops
- cloud sync
- scanned-PDF OCR

Those capabilities must be designed as separate, policy-gated additions rather than hidden inside the model provider.