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

A grounded-context snapshot is created once for a user turn and reused across tool/permission pauses. Retrieval therefore cannot silently change evidence midway through the same run.

## Trust boundaries

### Model

Untrusted decision component. It has no direct file handle, SQLite connection, permission grant, vector index, or arbitrary process execution capability.

### ToolRuntime

The only execution route for model-proposed actions. Unknown tool name/version fails closed. Tool input is decoded against typed Codable models and advertised JSON schemas.

### PermissionEngine

Grants are scoped by capability + exact resource and by duration (`once` or `session`). Chat prose cannot create a grant. A one-time grant is consumed by authorization.

### User files

macOS `NSOpenPanel` selection is registered by `SecurityScopedFileCatalog`. The model receives an opaque `UserFileResourceID`, never authority to invent a filesystem path. Security-scoped bookmark data remains platform-side.

### Knowledge

PDFKit extracts text only from already registered file resources. Knowledge chunks preserve document, source resource, ordinal, and page provenance. Retrieved source text is serialized as explicitly untrusted evidence.

## Persistence

- conversations/messages: SQLite + WAL
- Knowledge documents/chunks: SQLite + WAL
- dense vectors: SQLite Float32 blobs
- security-scoped bookmarks: local catalog under Application Support

Storage startup failure enters visible Safe Mode rather than silently replacing durable persistence with RAM.

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
- file deletion
- unrestricted directory access
- arbitrary HTTP/network action tools
- automatic code modification / SelfCoder
- background autonomous action loops
- cloud sync
- scanned-PDF OCR

Those capabilities must be designed as separate, policy-gated additions rather than hidden inside the model provider.
