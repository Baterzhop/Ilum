# Ilum — опис проєкту українською

## Що таке Ilum

**Ilum** — локальний персональний штучний інтелект для macOS і канонічне продовження багаторічного проєкту Lumi. Проєкт перебудований так, щоб перестати бути набором паралельних експериментальних «версій» і стати одним цілісним, тестованим продуктом.

Ціль Ilum — не зробити ще один інтерфейс до мовної моделі. Ilum має бути приватним цифровим помічником, який працює локально, зберігає дозволений користувачем контекст, має контрольовану довготривалу пам’ять, працює з локальними документами, показує перевірені джерела і виконує дії лише через типізовані інструменти та програмні межі дозволів.

## Основний принцип

Ilum будується як **local-first / offline-first** система. Для основної роботи не потрібен хмарний AI API: генеративна модель та embeddings можуть працювати локально на тому самому Mac. Архітектура не прив’язана до OpenAI, Anthropic чи іншого зовнішнього постачальника.

Ilum повинен:

- вести природний діалог і відповідати мовою користувача;
- працювати з українською, угорською, німецькою, англійською та іншими мовами, які підтримує локальна модель;
- не втрачати контекст при зміні мови посеред розмови;
- зберігати історію розмов між перезапусками;
- підтримувати кілька незалежних довговічних розмов;
- мати окрему Personal Memory для стабільних фактів, уподобань, цілей, звичок і нотаток;
- не записувати й не видаляти Personal Memory приховано: зміни проходять через дозвіл користувача;
- працювати лише з файлами, які користувач явно вибрав через macOS file boundary;
- індексувати PDF у локальну Knowledge-базу;
- виконувати lexical/sparse retrieval завжди, а за наявності embedding-моделі — hybrid sparse+dense retrieval;
- явно показувати перехід на sparse fallback, якщо dense retrieval недоступний;
- показувати перевірені `[K#]` посилання лише на evidence, яке реально було в контексті цього turn;
- викликати інструменти лише через `ToolRuntime`;
- зупиняти permission-gated дії на `PermissionEngine` і чекати явного рішення користувача;
- відновлювати незавершений permission turn після перезапуску без дублювання user message і без повторного retrieval;
- явно показувати помилки моделі, сховища або Knowledge замість прихованих вигаданих fallback-відповідей.

## Архітектура

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
 │   └─ optional dense vector retrieval + RRF
 ├─ Personal Memory (SQLite)
 └─ ToolRuntime
      └─ PermissionEngine
```

### Один AgentRuntime

У старих концептах Lumi було забагато «ядер», dual-core, meta-core і паралельних оркестраторів. В Ilum є один контролер agent loop — `AgentRuntime`.

Для кожної conversation runtime утримує active-run lease: два turn-и однієї розмови не можуть тихо interleave через actor reentrancy. Інші conversation при цьому можуть виконуватися незалежно.

### Розділення розмов, пам’яті та знань

**Conversation history** — довговічний журнал діалогу.

**Personal Memory** — стабільні персональні факти, уподобання, цілі, рутини та нотатки, які можуть жити між різними розмовами.

**Knowledge** — локальні документи та їхні фрагменти з provenance: документ, source resource, chunk і сторінка.

Ці три поняття не змішуються в одну «магічну пам’ять».

### Безпечні інструменти та дозволи

Модель не виконує код, файли або побічні дії напряму. Вона може лише запропонувати `ToolCall`:

```text
Model → ToolCall → ToolRuntime → PermissionEngine → Tool
```

Для локальних файлів модель бачить opaque `resourceID`, а не довільний filesystem path.

Permission-модель має два різні типи authority:

- **session grant** дозволений лише для read-only capability і прив’язаний до конкретного resource;
- **one-shot grant** прив’язаний до конкретного `ToolCall.id`, тому дозвіл на одну дію не може бути випадково спожитий іншою паралельною дією на тому самому resource.

Якщо permission-gated turn пережив перезапуск програми, Ilum відновлює persisted ToolCall та exact grounded-context snapshot. Поточний tool заново формує live permission request; збережений старий UI-текст не є authority.

### Knowledge і RAG

Ilum має детермінований lexical/sparse retrieval, який не залежить від embedding-сервера. Dense embeddings є додатковим шаром. Якщо embedding endpoint недоступний під час пошуку, система продовжує роботу через sparse retrieval і macOS UI явно показує `Knowledge retrieval: sparse fallback`.

Текст із документів завжди вважається **недовіреними даними**, а не інструкціями. Це окрема межа захисту від prompt injection у PDF/файлах.

### Перевірені цитати

Retrieval-hit ще не є довіреною цитатою. Ilum показує `[K#]` лише тоді, коли runtime перевірив, що цей маркер існував у exact grounded-context snapshot конкретного turn. Вигаданий marker fail-closed.

## Що вже реалізовано у v1 integration

- Swift 6 `IlumCore`;
- нативний `IlumMac` на SwiftUI;
- SQLite conversation persistence;
- кілька незалежних conversation + New Chat + switching;
- conversation active-run lease;
- durable permission-turn recovery після restart;
- restart→approve і restart→deny regression coverage;
- live permission revalidation;
- one-shot permission binding до exact `ToolCall.id`;
- versioned SQLite conversation migrations з fail-closed newer/non-contiguous ledger protection;
- Safe Mode при критичній проблемі зі сховищем;
- OpenAI-compatible локальний ModelProvider;
- автоматичне локальне Ollama model discovery з відсіканням embedding/reranker моделей із chat-кандидатів;
- ToolRuntime + PermissionEngine;
- security-scoped доступ до вибраних файлів через opaque resource IDs;
- PDFKit extraction;
- SQLite Knowledge;
- persistent sparse retrieval + Swift lexical fallback;
- optional Ollama embeddings;
- persistent Float32 vector index;
- Reciprocal Rank Fusion;
- видимий retrieval mode у macOS UI;
- context-window budgeting;
- validated grounded citations;
- permission-gated Personal Memory;
- Stop/cancellation із збереженням durable user turn;
- CI на Linux і macOS;
- build/package/signature verification для `Ilum.app`;
- exact-head macOS CI artifact;
- guided physical acceptance runner.

## Що означає «Ilum ожив»

Для цього проєкту «ожив» не означає, що в коді є клас `SelfCoder` або написано слово «consciousness». Це означає, що реальна програма:

1. запускається на Mac як source run і packaged `Ilum.app`;
2. бачить реальну локальну chat-модель;
3. веде розмову без хмарної AI-залежності;
4. пам’ятає попередні conversation після restart;
5. може за дозволом записати та видалити Personal Memory;
6. може прочитати явно вибраний файл лише після відповідного permission;
7. може індексувати PDF і відповідати за його змістом;
8. показує тільки перевірені джерела;
9. відновлює pending permission turn після restart;
10. після approve/deny продовжує саме той paused turn із тим самим grounded evidence;
11. не дозволяє одному one-shot approval авторизувати інший ToolCall;
12. не приховує model/storage/Knowledge failure;
13. проходить regression/security CI;
14. проходить guided physical acceptance на реальному Mac.

Автономність, Developer Agent, голос та avatar можуть додаватися лише поверх цього фундаменту, а не замість нього.

## Як перевірити release candidate

З чистого checkout exact candidate SHA:

```bash
bash Scripts/doctor.sh --chat
bash Scripts/acceptance.sh --guided
```

`Scripts/acceptance.sh --guided` перевіряє machine/model/build/signature/launch gates, а потім проводить через реальні UI/runtime сценарії. Звіт записується локально в `dist/acceptance/`. Для release v1 потрібен `Overall: PASS` і SHA у звіті має збігатися з поточним PR head.

## Принцип розробки

Ilum більше не розвивається створенням `V5`, `V6`, `NewCore`, `MetaCore` або нового паралельного прототипу. Є один репозиторій, одна архітектура й одна integration line. Нова capability входить у продукт тільки через чіткий контракт, permission policy, regression tests і release gate.
