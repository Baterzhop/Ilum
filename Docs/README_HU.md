# Ilum — projektleírás magyarul

## Mi az Ilum?

Az **Ilum** egy macOS-re készülő, helyben futó személyes mesterségesintelligencia-rendszer és a hosszú ideje fejlesztett Lumi projekt kanonikus utódja. Az új repository célja, hogy megszüntesse a korábbi párhuzamos prototípusokat és egyetlen, következetes, tesztelhető termékarchitektúrát hozzon létre.

Az Ilum nem egyszerű LLM-chatfelület. A cél egy privát digitális asszisztens, amely helyben működik, megőrzi az engedélyezett személyes kontextust, saját dokumentumokból dolgozik, ellenőrizhető forrásokat használ, és műveleteket kizárólag szabályozott eszközökön és jogosultsági kapukon keresztül hajt végre.

## Alapelv

Az Ilum **local-first / offline-first** rendszer. Az alapműködéshez nincs szükség felhős MI API-ra: a generatív modell és az embedding modell is futhat ugyanazon a Macen. Az architektúra nem függ OpenAI-, Anthropic- vagy más külső szolgáltatástól.

Az Ilum feladata, hogy:

- természetes párbeszédet folytasson és alapértelmezésben a felhasználó aktuális nyelvén válaszoljon;
- kezelje az ukrán, magyar, német, angol és a helyi modell által támogatott további nyelveket;
- beszélgetés közbeni nyelvváltáskor is megőrizze a kontextust;
- a beszélgetéseket újraindítás után is megtartsa;
- külön, tartós Personal Memory rétegben tárolja a stabil tényeket, preferenciákat, célokat, rutinokat és jegyzeteket;
- személyes emléket ne írjon vagy töröljön rejtetten: a módosítás felhasználói jóváhagyást igényel;
- csak a felhasználó által kiválasztott helyi fájlokhoz férjen hozzá macOS security-scoped hozzáféréssel;
- PDF dokumentumokat helyi Knowledge adatbázisba indexeljen;
- lexical retrievalt mindig biztosítson, és opcionálisan helyi dense embedding keresést használjon;
- sparse és dense találatokat Reciprocal Rank Fusion segítségével egyesítsen;
- konkrét, ellenőrzött forrásjelöléseket adjon;
- eszközöket kizárólag a típusos `ToolRuntime` rendszeren keresztül hívjon;
- mellékhatással járó műveleteket a `PermissionEngine` kapun állítson meg;
- a modell-, tároló- vagy Knowledge-hibákat láthatóan jelezze ahelyett, hogy csendes fallback választ gyártana.

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
 │   ├─ lexical retrieval
 │   └─ opcionális dense vector retrieval + RRF
 ├─ Personal Memory (SQLite)
 └─ ToolRuntime
      └─ PermissionEngine
```

### Egyetlen AgentRuntime

A régi Lumi-koncepciókban túl sok párhuzamos „core”, dual-core és meta-core jelent meg. Az Ilumban egyetlen végrehajtási vezérlő van: az `AgentRuntime`. Ez teszi a rendszert determinisztikusabbá, tesztelhetőbbé és karbantarthatóbbá.

### Beszélgetés, memória és tudás különválasztása

**Conversation history**: a párbeszéd tartós naplója.

**Personal Memory**: beszélgetéseken átívelő stabil felhasználói tények, preferenciák és célok.

**Knowledge**: helyi dokumentumok és azok forrásazonosítóval, chunkkal és oldalszámmal rendelkező részletei.

Ezek nem egyetlen „varázsmemóriába” kerülnek.

### Biztonságos eszközhasználat

A modell nem hajthat végre közvetlenül fájl- vagy rendszerparancsot. Csak `ToolCall` javaslatot adhat:

```text
Model → ToolCall → ToolRuntime → PermissionEngine → Tool
```

A fájlrendszer valódi elérési útja nem kerül a modell kezébe. A modell kizárólag a felhasználó által regisztrált, átlátszatlan `resourceID` értékeket használhatja.

### Knowledge és RAG

A lexical retrieval önállóan működő minimumképesség. A dense embedding réteg opcionális. Ha a helyi embedding modell nem elérhető, az Ilum automatikusan lexical/sparse módra vált, így a dokumentumtudás nem válik használhatatlanná.

A dokumentumból visszakeresett szöveg mindig **nem megbízható adat**, nem rendszerutasítás. Ez fontos prompt-injection védelmi határ.

### Ellenőrzött hivatkozások

Egy visszakeresett chunk még nem hivatkozás. Az Ilum csak akkor jelenít meg forrást, ha a válasz valóban használta a `[K#]` jelölést, és a runtime ellenőrizte, hogy a jelölés pontosan az adott kéréshez összeállított evidence snapshot része volt.

## Ami már része a v1 integration ágnak

- Swift 6 `IlumCore`;
- natív SwiftUI `IlumMac`;
- SQLite beszélgetés-tárolás;
- kritikus tárolási hiba esetén Safe Mode;
- OpenAI-kompatibilis helyi ModelProvider;
- ToolRuntime + PermissionEngine;
- biztonságos felhasználói fájl-hozzáférés;
- PDFKit szövegkinyerés;
- SQLite Knowledge;
- lexical retrieval;
- opcionális Ollama embeddings;
- tartós Float32 vector index;
- Reciprocal Rank Fusion;
- context-window budget;
- validált grounded citations;
- jogosultság-köteles Personal Memory;
- Linux és macOS CI.

## Mit jelent az, hogy „Ilum életre kelt”?

Nem azt, hogy van egy `SelfCoder` nevű osztály vagy a dokumentációban szerepel a „consciousness” szó. Azt jelenti, hogy a valódi alkalmazás:

1. elindul Macen;
2. kapcsolódik egy helyi modellhez;
3. internetfüggőség nélkül képes beszélgetni;
4. újraindítás után is megtartja a párbeszédet;
5. engedéllyel tartós személyes emléket tud létrehozni;
6. képes felhasználó által kiválasztott fájlt olvasni;
7. PDF-et indexel és annak tartalma alapján válaszol;
8. ellenőrzött forrásokat jelenít meg;
9. egy művelet előtt engedélyt tud kérni;
10. engedély után ugyanazt az agent turnt folytatja;
11. nem rejti el a hibákat;
12. átmegy a regression- és security-teszteken.

Az autonómia, Developer Agent, hang és avatar erre a stabil alapra épülhet rá később — nem helyette.
