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
| Native app packaging | Implemented | `Scripts/build-app.sh` creates `dist/Ilum.app`; signing/notarization is not yet a public-distribution claim |
| Conversation persistence | Implemented | SQLite, survives reopen |
| Multi-conversation UI | Implemented | durable catalog, New Chat, switching stored conversations |
| Durable permission-turn recovery | Implemented | pending ToolCall + exact grounded evidence survive restart; approval UI is restored |
| Permission restore revalidation | Implemented | live tool recomputes permission request; stored capability/resource mismatch fails closed |
| Versioned conversation migrations | Implemented | numbered SQLite migrations; unknown newer schema version fails closed |
| Safe storage bootstrap | Implemented | critical conversation-store failure enters Safe Mode |
| Local model transport | Implemented | OpenAI-compatible endpoint, explicit failures |
| Local Ollama discovery | Implemented | deterministic chat-model selection; embedding-only models rejected |
| Tool protocol/runtime | Implemented | typed registry and structured results |
| Permission engine | Implemented | exact capability/resource grants; session grants limited to read-only capabilities |
| User-file boundary | Implemented | security-scoped selection + opaque resource IDs |
| PDF text ingestion | Implemented | PDFKit; scanned/image-only PDFs are not falsely treated as extracted text |
| Knowledge store | Implemented | SQLite document/chunk provenance + explicit deletion |
| Persistent sparse retrieval | Implemented | SQLite FTS5 where available; deterministic Swift lexical fallback otherwise |
| Dense retrieval | Implemented | optional local Ollama embeddings + persistent vector index |
| Hybrid fusion | Implemented | Reciprocal Rank Fusion with sparse fallback |
| Retrieval-mode visibility | Implemented | macOS header exposes hybrid, sparse fallback, sparse or unavailable mode after retrieval |
| Context budgeting | Implemented | current turn is never silently removed |
| Grounded citations | Implemented | `[K#]` markers validated against exact evidence snapshot |
| Personal Memory | Implemented | dedicated SQLite store; read lookup may be local-policy allowed, writes/deletion require approval |
| Multilingual policy | Implemented at runtime-prompt level | model capability still determines language quality |
| First-run diagnostics | Implemented | `Scripts/doctor.sh`, optional real `--chat` smoke request |
| Physical acceptance runner | Implemented | records exact SHA, source + packaged launch smoke, build/signature evidence and guided physical checkpoints |
| CI | Implemented | Linux Core, macOS Core, macOS app test/build/package; helper scripts syntax-checked with macOS system Bash |

## Verification gates

Automated CI must be green for the exact commit proposed for release:

1. `IlumCore tests (Linux)`
2. `IlumCore tests (macOS)`
3. `IlumMac build + tests (macOS)`
4. native `Ilum.app` packaging / plist / codesign verification
5. helper-script syntax validation on Linux and `/bin/bash` on macOS
6. `Ilum-macOS` artifact produced for the same head SHA

CI status is intentionally not cached as a permanent claim in this document. Any commit after a green run creates a new release candidate and must pass the gates again on its exact SHA.

Regression coverage includes:

- restart-safe permission turns;
- approval after restart with preservation of the original grounded-context snapshot;
- denial after restart with preservation of the original grounded-context snapshot, no tool data read, durable denial history and pending-record cleanup;
- live permission presentation after restore;
- fail-closed permission-identity mismatch;
- conversation-delete cascade for pending state;
- dense retrieval failure falling back to sparse retrieval;
- fail-closed unknown future schema versions.

## Physical acceptance still required before v1 release

GitHub Actions cannot prove behavior against the user's actual locally installed model and macOS permissions. Before merging v1 to `main`, run:

```bash
bash Scripts/acceptance.sh --guided
```

The physical session verifies:

- `Scripts/doctor.sh --chat` succeeds against the actual local model;
- Ilum launches as `swift run` through `Scripts/run.sh` and as packaged `Ilum.app`;
- launch smoke cannot false-pass because an old `IlumMac` process is already running;
- automatic local-model discovery selects a real chat model and not an embedding model;
- real multilingual chat works and a language switch preserves context;
- restart restores the active conversation and saved conversation catalog;
- New Chat creates an independent durable conversation;
- Stop cancels a long turn without corrupting durable state;
- restart while a permission card is pending restores the same action without duplicating the user turn;
- restart→approve executes and continues the paused turn once;
- restart→deny does not execute the tool and continues through a durable denial event;
- a permission-gated Knowledge turn preserves the exact original grounded evidence across restart;
- `memory.remember` pauses for approval and approved memory survives restart;
- `memory.search` retrieves approved memory;
- `memory.forget` requires approval and removes the selected record;
- selecting a text file creates only an opaque resource ID for the model;
- `file.readText` pauses for approval before file content reaches the model;
- file bookmark access survives reopen;
- PDF indexing survives restart;
- a document question retrieves the expected page/chunk and renders only validated citations;
- prompt-injection text in a document remains untrusted evidence;
- dense embedding failure visibly changes the header to `Knowledge retrieval: sparse fallback` while sparse retrieval remains usable;
- removing a selected indexed file also removes its derived Knowledge/vector copies;
- model-server failure is visible and never replaced by a fabricated assistant answer.

See `Docs/PHYSICAL_ACCEPTANCE.md` for the exact physical procedure and safe temporary environment overrides used for embedding/model-failure tests.

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

Future external side-effect tools also require a durable execution/idempotency ledger before production use. Current v1 permission-gated writes are local Personal Memory operations with retry-safe semantics.

These capabilities may be added only through explicit contracts, permission policy, regression tests, and an acceptance gate. Direct self-modification from arbitrary model output remains prohibited.

## Definition of v1 release

Ilum v1 can move from Draft integration to `main` when:

- all automated gates are green on the exact release commit;
- an `Overall: PASS` guided physical macOS local-model acceptance report exists for that exact SHA;
- pending permission restart→approve and restart→deny behavior is demonstrated on the physical Mac;
- Personal Memory write/delete approval is demonstrated;
- multi-conversation restart behavior is demonstrated;
- PDF Knowledge + citation + deletion + visible sparse-fallback flow is demonstrated;
- no critical open security regression remains;
- README and localized documentation match actual behavior.
