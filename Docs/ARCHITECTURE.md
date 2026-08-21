# Ilum v1 architecture

## Product boundary

Ilum is a local-first macOS AI runtime. The model is not the application security boundary. It can produce text or propose one typed tool call; durable state, permissions, file authority, retrieval, concurrency, and side effects are controlled by code-owned runtimes.

## Runtime flow

```text
User
  -> IlumMac
  -> AgentRuntime
       -> acquire conversation run lease
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
       -> release conversation run lease
```

A grounded-context snapshot is created once for a user turn and reused across tool/permission pauses. If a permission-gated turn is interrupted by app termination, Ilum persists that exact evidence snapshot with the pending ToolCall and resumes from it after restart instead of running retrieval again.

## Runtime concurrency

Swift actors are reentrant at `await`, so actor isolation alone is not a conversation-transaction boundary. `AgentRuntime` therefore owns an explicit conversation-scoped run lease.

- Only one active agent turn or permission continuation may mutate a given conversation at a time.
- A second send to the same conversation fails before it can persist another user message.
- Different conversations may execute concurrently; Ilum does not serialize the entire runtime globally.
- Approval/denial keeps the conversation lease across tool execution, transactional pending-record resolution, and the model continuation. Deleting the durable pending row therefore cannot open a race window for a new send before the paused turn finishes.
- A pending permission ID also has a resolution guard so duplicate approve/deny requests cannot resolve the same transaction concurrently.

`RuntimePhase` and `lastError` remain runtime-level diagnostics rather than per-conversation telemetry. Current `IlumMac` presents one interactive generation at a time; a future multi-client UI should introduce per-run observability without weakening the conversation lease.

## Trust boundaries

### Model

Untrusted decision component. It has no direct file handle, SQLite connection, permission grant, vector index, or arbitrary process execution capability.

### ToolRuntime

The only execution route for model-proposed actions. Unknown tool name/version fails closed. Tool input is decoded against typed Codable models and advertised JSON schemas.

For a restored pending action, `ToolRuntime` recomputes the permission request from the currently registered tool and the persisted ToolCall. Serialized permission reason/display text is not treated as authority. The restored action fails closed if the persisted capability/resource identity does not match the live tool request.

### PermissionEngine

Permission identity has two deliberately different scopes:

- **Session read grants** are scoped to `capability + exact resource`. They are allowed only for read-only capabilities and may authorize later matching reads during that application session.
- **One-shot grants** are scoped to `capability + exact resource + concrete execution ID`. `ToolRuntime` uses the internal persisted `ToolCall.id` as that execution ID. A one-shot approval for call A therefore cannot be consumed by concurrent call B even if both calls request the same file or app-data resource.

Chat prose cannot create a grant. A one-shot grant is consumed only by its matching concrete execution. Distinct approved one-shot calls on the same resource can coexist without replacing each other. Writes and other side effects always resolve to one-shot authority and require a fresh user decision for every concrete ToolCall.

The user-facing `PermissionRequest.id` is presentation/audit identity, not execution authority. This distinction is required because a restored permission request is recomputed after restart and may receive a fresh request UUID while the durable `ToolCall.id` remains stable.

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

Conversation schema changes are applied by numbered migrations. The migration ledger must be a valid prefix of the migrations known to the running binary. Opening a database containing an unknown newer migration version **or a non-contiguous/gapped known migration history** fails closed instead of allowing writes against an ambiguous schema state.

When an approved or denied pending action is resolved, the resulting tool-history event and deletion of the pending record are committed together by the SQLite conversation store. Storage startup failure enters visible Safe Mode rather than silently replacing durable persistence with RAM.

## Crash/restart semantics

A permission pause is a durable runtime state, not a transient UI modal:

1. user input is persisted before model/tool work;
2. ToolCall + permission gate + evidence snapshot are persisted before the approval is exposed;
3. restart restores the same pending ID, concrete ToolCall ID and grounded evidence;
4. the live tool recomputes the permission request before approval can execute;
5. an approval grant is bound to the persisted ToolCall ID for one-shot authority;
6. approval/denial resolution is persisted transactionally with the tool-history event;
7. the conversation run lease remains held until the resumed model continuation completes or fails.

Current v1 side-effect tools are local Personal Memory writes/deletion; those operations are idempotent under retry. Future external side-effect tools must add an execution/idempotency ledger before they are admitted to production authority.

## Retrieval

Current baseline:

1. deterministic Unicode lexical retrieval (BM25-style correctness baseline),
2. optional dense embedding retrieval through an `EmbeddingProvider`,
3. persistent exact cosine vector search,
4. Reciprocal Rank Fusion,
5. automatic lexical fallback when embeddings are unavailable,
6. visible macOS retrieval state so dense failure is not silently hidden from the user.

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
