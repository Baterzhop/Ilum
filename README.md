# Ilum

Ilum is the canonical successor to Lumi: a local-first personal AI runtime for macOS built around one agent loop, durable local state, grounded knowledge retrieval, explicit tool permissions, and verifiable citations.

This repository intentionally starts with a clean history. Legacy Lumi versions remain reference material only.

## Design invariants

- One `AgentRuntime` owns request execution.
- User input is persisted before model/tool work.
- Local files are reachable only through user-selected opaque resource IDs.
- Model-proposed tool calls never execute outside `ToolRuntime` / `PermissionEngine`.
- Retrieved document text is untrusted evidence, never an instruction channel.
- Citation markers are validated against the exact context snapshot used for the answer.
- Knowledge and conversations survive restart in SQLite.
- Dense retrieval is an optional enhancement; sparse retrieval remains a working fallback.
- No shell, delete, unrestricted filesystem, or arbitrary-network tool is enabled by default.

## Current build target

The first Ilum production slice is being assembled from the verified Lumi One runtime/security foundation plus the proven Lumi V4 context-budgeting and hybrid-RAG ideas. CI and real macOS acceptance are release gates, not optional documentation claims.
