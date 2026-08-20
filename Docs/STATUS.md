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
| Conversation persistence | Implemented | SQLite, survives reopen |
| Safe storage bootstrap | Implemented | critical conversation-store failure enters Safe Mode |
| Local model transport | Implemented | OpenAI-compatible endpoint, explicit failures |
| Tool protocol/runtime | Implemented | typed registry and structured results |
| Permission engine | Implemented | exact capability/resource grants; one-time/session grants |
| User-file boundary | Implemented | security-scoped selection + opaque resource IDs |
| PDF text ingestion | Implemented | PDFKit; scanned/image-only PDFs are not falsely treated as extracted text |
| Knowledge store | Implemented | SQLite document/chunk provenance |
| Lexical retrieval | Implemented | deterministic local baseline |
| Dense retrieval | Implemented | optional local Ollama embeddings + persistent vector index |
| Hybrid fusion | Implemented | Reciprocal Rank Fusion with sparse fallback |
| Context budgeting | Implemented | current turn is never silently removed |
| Grounded citations | Implemented | `[K#]` markers validated against exact evidence snapshot |
| Personal Memory | Implemented | dedicated SQLite store; read-only lookup may be local-policy allowed, writes/deletion require approval |
| Multilingual policy | Implemented at runtime-prompt level | model capability still determines language quality |
| CI | Implemented | Linux Core, macOS Core, macOS app tests/build |

## Verification gates

Automated CI must stay green for every integration commit:

1. `IlumCore tests (Linux)`
2. `IlumCore tests (macOS)`
3. `IlumMac build + tests (macOS)`

The runtime/app foundation has passed all three gates. Newly added features must pass the same gates before they are treated as verified.

## Physical acceptance still required before v1 release

GitHub Actions cannot prove hardware-local model behavior on the user's Mac. Before merging v1 to `main`, perform a physical acceptance session that verifies:

- local model server discovery/configuration;
- real chat response from a local installed model;
- restart restores conversation;
- `memory.remember` pauses for approval and survives restart;
- `memory.search` can retrieve the approved memory;
- selecting a text file creates only an opaque resource ID for the model;
- `file.readText` pauses for approval before file content reaches the model;
- PDF indexing survives restart;
- a document question retrieves the expected page/chunk and renders only validated citations;
- dense embedding failure visibly degrades to lexical retrieval;
- model-server failure is visible and never replaced by a fabricated assistant answer.

## Deliberate non-claims

The following are not yet release claims:

- no scanned-PDF OCR yet;
- no voice pipeline yet;
- no avatar yet;
- no unrestricted browser/network agent;
- no shell execution;
- no delete/arbitrary filesystem authority;
- no autonomous self-rewriting;
- no production Developer Agent yet;
- no background autonomous task scheduler yet;
- no cloud sync dependency.

These capabilities may be added only through explicit contracts, permission policy, tests, and an acceptance gate. Direct self-modification from arbitrary model output remains prohibited.

## Definition of v1 release

Ilum v1 can move from draft integration to `main` when:

- all automated gates are green on the exact release commit;
- physical macOS local-model acceptance is completed;
- Personal Memory write/delete approval is demonstrated;
- PDF Knowledge + citation flow is demonstrated;
- no critical open security regression remains;
- README and localized documentation match actual behavior.
