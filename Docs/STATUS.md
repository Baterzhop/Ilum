# Ilum status

This file separates implemented code from verified behavior and future work. A feature is not considered production-ready solely because source code exists.

## Canonical line

- Repository: `Baterzhop/Ilum`
- Integration branch: `integration/ilum-v1`
- Pull request: `#1`
- Default branch: `main`
- Architecture rule: no parallel V-number engines; all product work converges into this line.

## Implemented in the integration branch

| Area | State | Notes |
| --- | --- | --- |
| Swift 6 core | Implemented | `Packages/IlumCore` |
| Native macOS app | Implemented | SwiftUI executable in `Apps/IlumMac` |
| Native app packaging | Implemented | `Scripts/build-app.sh` creates `dist/Ilum.app`; signing/notarization is not yet a release claim |
| Conversation persistence | Implemented | SQLite, survives reopen |
| Multi-conversation UI | Implemented | durable catalog, New Chat, switching stored conversations |
| Safe storage bootstrap | Implemented | critical conversation-store failure enters Safe Mode |
| Local model transport | Implemented | OpenAI-compatible endpoint, explicit failures |
| Local Ollama discovery | Implemented | deterministic chat-model selection; embedding-only models rejected |
| Tool protocol/runtime | Implemented | typed registry and structured results |
| Permission engine | Implemented | exact capability/resource grants; one-time/session grants |
| User-file boundary | Implemented | security-scoped selection + opaque resource IDs |
| PDF text ingestion | Implemented | PDFKit; scanned/image-only PDFs are not falsely treated as extracted text |
| Knowledge store | Implemented | SQLite document/chunk provenance + explicit deletion |
| Persistent sparse retrieval | Implemented | SQLite FTS5 where available; deterministic Swift lexical fallback otherwise |
| Dense retrieval | Implemented | optional local Ollama embeddings + persistent vector index |
| Hybrid fusion | Implemented | Reciprocal Rank Fusion with sparse fallback |
| Context budgeting | Implemented | current turn is never silently removed |
| Grounded citations | Implemented | `[K#]` markers validated against exact evidence snapshot |
| Personal Memory | Implemented | dedicated SQLite store; read lookup may be local-policy allowed, writes/deletion require approval |
| Multilingual policy | Implemented at runtime-prompt level | model capability still determines language quality |
| First-run diagnostics | Implemented | `Scripts/doctor.sh`, optional real `--chat` smoke request |
| CI | Implemented | Linux Core, macOS Core, macOS app test/build/package |

## Verification gates

Automated CI must stay green for every release candidate:

1. `IlumCore tests (Linux)`
2. `IlumCore tests (macOS)`
3. `IlumMac build + tests (macOS)`
4. native `Ilum.app` packaging / plist validation

An earlier runtime/app foundation passed the three build/test gates. The exact current integration head must pass again after Personal Memory, model discovery, multi-conversation support, FTS5, Knowledge deletion and packaging changes. Until that exact run is green, these newer additions are implemented but not release-verified.

## Physical acceptance still required before v1 release

GitHub Actions cannot prove behavior against the user's actual locally installed model and macOS permissions. Before merging v1 to `main`, perform a physical acceptance session that verifies:

- `Scripts/doctor.sh --chat` succeeds against the actual local model;
- Ilum launches as `swift run` and as the packaged `Ilum.app`;
- automatic local-model discovery selects a real chat model and not an embedding model;
- real multilingual chat works and a language switch preserves context;
- restart restores the active conversation and the saved conversation catalog;
- New Chat creates an independent durable conversation;
- `memory.remember` pauses for approval and the approved memory survives restart;
- `memory.search` retrieves the approved memory;
- `memory.forget` requires approval and removes the selected record;
- selecting a text file creates only an opaque resource ID for the model;
- `file.readText` pauses for approval before file content reaches the model;
- PDF indexing survives restart;
- a document question retrieves the expected page/chunk and renders only validated citations;
- removing a selected indexed file also removes its derived Knowledge/vector copies;
- dense embedding failure visibly degrades to sparse retrieval;
- model-server failure is visible and never replaced by a fabricated assistant answer.

## Deliberate non-claims

The following are not yet v1 release claims:

- no scanned-PDF OCR yet;
- no voice pipeline yet;
- no avatar yet;
- no unrestricted browser/network agent;
- no shell execution;
- no arbitrary filesystem authority;
- no autonomous self-rewriting;
- no production Developer Agent yet;
- no background autonomous task scheduler yet;
- no cloud sync dependency;
- no signed/notarized public macOS distribution yet.

These capabilities may be added only through explicit contracts, permission policy, regression tests, and an acceptance gate. Direct self-modification from arbitrary model output remains prohibited.

## Definition of v1 release

Ilum v1 can move from Draft integration to `main` when:

- all automated gates are green on the exact release commit;
- physical macOS local-model acceptance is completed;
- Personal Memory write/delete approval is demonstrated;
- multi-conversation restart behavior is demonstrated;
- PDF Knowledge + citation + deletion flow is demonstrated;
- no critical open security regression remains;
- README and localized documentation match actual behavior.
