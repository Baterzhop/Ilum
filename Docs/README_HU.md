# Ilum — projektleírás magyarul

## Mi az Ilum?

Az **Ilum** egy macOS-re épülő, helyben futó személyes mesterségesintelligencia-rendszer és a hosszú ideje fejlesztett Lumi projekt kanonikus utódja. Az új irány megszünteti a korábbi párhuzamos prototípusokat, és egyetlen, következetes, tesztelhető termékarchitektúrára épít.

Az Ilum nem egyszerű LLM-chatfelület. A cél egy privát digitális asszisztens-alap, amely helyben működik, tartósan megőrzi az engedélyezett felhasználói kontextust, saját dokumentumokból dolgozik, ellenőrizhető forrásokat használ, és műveleteket kizárólag típusos eszközökön és program által érvényesített jogosultsági határokon keresztül hajt végre.

## Alapelv

Az Ilum **local-first / offline-first** rendszer. Az alapműködéshez nincs szükség felhős MI API-ra: a generatív modell és az embedding modell is futhat ugyanazon a Macen. Az architektúra nem függ OpenAI-, Anthropic- vagy más külső szolgáltatótól.

Az Ilum feladata, hogy:

- természetes párbeszédet folytasson, és alapértelmezésben a felhasználó aktuális nyelvén válaszoljon;
- kezelje az ukrán, magyar, német, angol és a helyi modell által támogatott további nyelveket;
- nyelvváltás közben is megőrizze a beszélgetés kontextusát;
- a beszélgetéseket újraindítás után is megtartsa;
- több egymástól független, tartós conversationt kezeljen;
- külön Personal Memory rétegben tárolja a stabil tényeket, preferenciákat, célokat, rutinokat és jegyzeteket;
- személyes emléket ne írjon vagy töröljön rejtetten: a módosítás felhasználói jóváhagyást igényel;
- kizárólag a felhasználó által kiválasztott helyi fájlokhoz férjen hozzá macOS security-scoped határon keresztül;
- PDF dokumentumokat helyi Knowledge adatbázisba indexeljen;
- lexical/sparse retrievalt mindig biztosítson, és opcionálisan helyi dense embedding keresést használjon;
- dense hiba esetén láthatóan sparse fallback módra váltson;
- csak az adott turn tényleges evidence snapshotjához tartozó, ellenőrzött `[K#]` forrásjelöléseket jelenítsen meg;
- eszközöket kizárólag a `ToolRuntime` rendszeren keresztül hívjon;
- permission-gated műveleteknél a `PermissionEngine` kapun álljon meg és felhasználói döntést kérjen;
- függőben lévő permission turnt újraindítás után az eredeti ToolCall-lal és az eredeti grounded evidence-szel folytasson;
- a modell-, tároló- vagy Knowledge-hibákat láthatóan jelezze ahelyett, hogy csendes, kitalált fallback választ gyártana.

## Architektúra

```text
IlumMac (SwiftUI)
        │
        ▼
AgentRuntime
 ├─ ConversationStore (SQLite)
 ├─ ContextBudgetManager
 ├─ ModelProvider (localhost)
 ├─ KnowledgeRetriever
 │   ├─ lexical/sparse retrieval
 │   └─ opcionális dense vector retrieval + RRF
 ├─ Personal Memory (SQLite)
 └─ ToolRuntime
      └─ PermissionEngine
```

### Egyetlen AgentRuntime

A régi Lumi-koncepciókban túl sok párhuzamos „core”, dual-core és meta-core jelent meg. Az Ilumban egyetlen agent loop vezérlő van: az `AgentRuntime`.

Conversation-szintű active-run lease biztosítja, hogy ugyanazon beszélgetés két turnje ne interleave-eljen actor reentrancy miatt. Különböző conversationök ugyanakkor egymástól függetlenül futhatnak.

### Beszélgetés, memória és tudás különválasztása

**Conversation history**: a párbeszéd tartós naplója.

**Personal Memory**: beszélgetéseken átívelő stabil felhasználói tények, preferenciák, célok, rutinok és jegyzetek.

**Knowledge**: helyi dokumentumok és azok forrásazonosítóval, chunkkal és oldalszámmal rendelkező részletei.

Ezek nem egyetlen „varázsmemóriába” kerülnek.

### Biztonságos eszközhasználat és jogosultságok

A modell nem hajthat végre közvetlenül fájl-, rendszer- vagy mellékhatással járó műveletet. Csak `ToolCall` javaslatot adhat:

```text
Model → ToolCall → ToolRuntime → PermissionEngine → Tool
```

A modell nem kap tetszőleges filesystem path hozzáférést; a kiválasztott fájlokat opaque `resourceID` azonosítókon keresztül látja.

A jogosultsági modell két authority típust különít el:

- **session grant** csak read-only capabilityhez adható, és az adott resource-ra korlátozott;
- **one-shot grant** az exact `ToolCall.id` értékhez kötött, ezért egy konkrét művelet jóváhagyását nem tudja felhasználni egy másik, ugyanazt a resource-ot célzó párhuzamos ToolCall.

Ha egy permission-gated turn túléli az alkalmazás újraindítását, az Ilum a persisted ToolCallt és az exact grounded-context snapshotot állítja vissza. Az aktuális tool újra kiszámítja a live permission requestet; a régi, sorosított UI-szöveg nem authority.

### Knowledge és RAG

A lexical/sparse retrieval önálló minimumképesség. A dense embedding réteg opcionális. Ha az embedding endpoint keresés közben nem érhető el, az Ilum sparse retrievallel folytatja, és a macOS felület láthatóan `Knowledge retrieval: sparse fallback` állapotot jelez.

A dokumentumból visszakeresett szöveg mindig **nem megbízható adat**, nem rendszerutasítás. Ez fontos prompt-injection védelmi határ.

### Ellenőrzött hivatkozások

Egy retrieval-hit önmagában még nem megbízható hivatkozás. Az Ilum csak akkor jelenít meg `[K#]` jelölést, ha a runtime igazolta, hogy az a konkrét turn exact grounded-context snapshotjában valóban létezett. Kitalált marker esetén a rendszer fail-closed módon hibát jelez.

## Ami már része a v1 integration ágnak

- Swift 6 `IlumCore`;
- natív SwiftUI `IlumMac`;
- SQLite conversation persistence;
- több tartós conversation + New Chat + switching;
- conversation active-run lease;
- durable permission-turn recovery restart után;
- restart→approve és restart→deny regression coverage;
- live permission revalidation;
- exact `ToolCall.id`-hez kötött one-shot permission;
- verziózott SQLite conversation migrationök fail-closed newer/non-contiguous ledger védelemmel;
- kritikus tárolási hiba esetén Safe Mode;
- OpenAI-kompatibilis helyi ModelProvider;
- automatikus Ollama model discovery, amely kizárja az embedding/reranker modelleket chat jelöltként;
- ToolRuntime + PermissionEngine;
- security-scoped, opaque resource ID alapú felhasználói fájl-hozzáférés;
- PDFKit szövegkinyerés;
- SQLite Knowledge;
- persistent sparse retrieval + Swift lexical fallback;
- opcionális Ollama embeddings;
- tartós Float32 vector index;
- Reciprocal Rank Fusion;
- látható retrieval mód a macOS UI-ban;
- context-window budget;
- validált grounded citations;
- permission-gated Personal Memory;
- Stop/cancellation durable user-turn megőrzéssel;
- Linux és macOS CI;
- `Ilum.app` build/package/signature ellenőrzés;
- exact-head macOS CI artifact;
- guided physical acceptance runner.

## Mit jelent az, hogy „Ilum életre kelt”?

Nem azt, hogy van egy `SelfCoder` nevű osztály vagy a dokumentációban szerepel a „consciousness” szó. Azt jelenti, hogy a valódi alkalmazás:

1. forrásból és packaged `Ilum.app` formában is elindul Macen;
2. kapcsolódik egy valódi helyi chat modellhez;
3. felhős MI-függőség nélkül képes beszélgetni;
4. újraindítás után is megtartja a conversationöket;
5. jóváhagyással Personal Memory bejegyzést tud létrehozni és törölni;
6. csak permission után tud felhasználó által kiválasztott fájlt olvasni;
7. PDF-et indexel és annak tartalma alapján válaszol;
8. kizárólag ellenőrzött forrásokat jelenít meg;
9. újraindítás után visszaállítja a pending permission turnt;
10. approve/deny után ugyanazt a paused turnt és ugyanazt a grounded evidence-t folytatja;
11. egy one-shot approval nem tud más ToolCallt felhatalmazni;
12. nem rejti el a model/storage/Knowledge hibákat;
13. átmegy a regression/security CI-n;
14. átmegy a guided physical acceptance folyamaton egy valódi Macen.

Az autonómia, Developer Agent, hang és avatar csak erre a stabil alapra épülhet rá később — nem helyette.

## Release candidate ellenőrzése

Az exact candidate SHA tiszta checkoutjából:

```bash
bash Scripts/doctor.sh --chat
bash Scripts/acceptance.sh --guided
```

A guided runner ellenőrzi a machine/model/build/signature/launch gate-eket, majd végigvezeti a valós UI/runtime teszteken. A helyi jelentés a `dist/acceptance/` mappába kerül. A v1 release feltétele az `Overall: PASS`, és a jelentésben szereplő SHA-nak egyeznie kell az aktuális PR head SHA-val.

## Fejlesztési elv

Az Ilum többé nem `V5`, `V6`, `NewCore`, `MetaCore` vagy új párhuzamos prototípus létrehozásával fejlődik. Egy repository, egy architektúra és egy integration line van. Új capability csak egyértelmű kontraktus, permission policy, regression test és release gate mellett kerülhet a termékbe.
