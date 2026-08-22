# Physical macOS acceptance

Цей етап потрібен перед тим, як Ilum v1 можна буде вивести з Draft і розглядати merge у `main`.

GitHub Actions перевіряє компіляцію, regression/security tests, пакування, `Info.plist`, codesign і macOS-сумісність helper scripts. Але CI не може довести, що Ilum правильно працює саме на реальному Mac із локально встановленим Ollama, реальними security-scoped permissions та реальною поведінкою UI.

## Один рекомендований запуск

На Mac, у чистому checkout поточного `integration/ilum-v1`:

```bash
bash Scripts/acceptance.sh --guided
```

Перед запуском закрий усі вже відкриті процеси Ilum. Runner навмисно відмовляється вважати launch smoke успішним, якщо `IlumMac` уже працював до перевірки: інакше старий процес міг би дати хибний PASS новому bundle.

Runner:

1. фіксує exact Git SHA, macOS та архітектуру машини;
2. перевіряє, що checkout чистий;
3. запускає `Scripts/doctor.sh --chat` і робить реальний запит до локальної chat-моделі;
4. запускає `Scripts/run.sh`, чекає появи нового процесу `IlumMac`, а потім завершує тільки цей source-launch smoke;
5. збирає release `Ilum.app`;
6. перевіряє executable, `Info.plist` та ad-hoc codesign;
7. запускає packaged app і перевіряє появу свіжого процесу;
8. проводить через ручні acceptance-пункти для chat, multilingual context, restart, Stop, Personal Memory, file permissions, окремих restart→approve та restart→deny сценаріїв, grounded-context recovery, PDF/RAG, citations, sparse fallback, Knowledge deletion та model failure;
9. створює Markdown-звіт у `dist/acceptance/`.

`dist/` ігнорується Git, тому acceptance report не потрапляє в репозиторій випадково.

## Інші режими

Лише автоматичні локальні перевірки, без запуску UI:

```bash
bash Scripts/acceptance.sh --auto-only
```

Автоматичні перевірки + checklist-файл, але без запуску source або packaged `Ilum.app`:

```bash
bash Scripts/acceptance.sh --no-launch
```

## Видимий sparse fallback

Ilum показує поточний retrieval mode в header:

- `Knowledge retrieval: hybrid` — dense + sparse retrieval доступні;
- `Knowledge retrieval: sparse fallback` — dense query embedding зламався/недоступний, але Knowledge продовжує працювати через sparse retrieval;
- `Knowledge retrieval: sparse` — runtime працює без dense layer;
- `Knowledge retrieval: unavailable` — Knowledge недоступний.

Безпечний physical test fallback не потребує зміни постійної конфігурації. Закрий Ilum і запусти окремий процес із недоступним embedding endpoint:

```bash
ILUM_OLLAMA_EMBED_URL=http://127.0.0.1:1/api/embed bash Scripts/run.sh
```

Постав питання до вже індексованого PDF. Очікування: header переходить у `Knowledge retrieval: sparse fallback`, але sparse evidence і валідні `[K#]` citations залишаються працездатними. Після тесту закрий цей процес і запускай Ilum нормально.

## Безпечний test model failure

Для перевірки, що Ilum не вигадує fallback-відповідь при відмові chat server, можна тимчасово запустити:

```bash
ILUM_MODEL_URL=http://127.0.0.1:1/v1/chat/completions \
ILUM_MODEL=acceptance-invalid \
bash Scripts/run.sh
```

Надішли нешкідливий prompt. Очікування: видима runtime/model помилка і відсутність вигаданої assistant-відповіді. Ці environment overrides діють лише для цього процесу.

## Durable permission acceptance

Approval і denial — це два окремі release-сценарії, а не один пункт «approve or deny».

### Restart → approve

1. виклич permission card;
2. закрий Ilum до рішення;
3. relaunch;
4. переконайся, що відновився той самий pending action без дублювання user message;
5. approve;
6. переконайся, що tool виконався один раз і turn продовжився.

### Restart → deny

1. створи новий permission-gated turn;
2. закрий Ilum до рішення;
3. relaunch;
4. deny;
5. переконайся, що tool side effect/read не виконався;
6. turn повинен продовжитися з durable denial event.

Для turn, який одночасно використовує Knowledge, після restart continuation має використовувати **оригінальний grounded-context snapshot**, а не непомітно робити новий retrieval. Це додатково покривається автоматичними Core regression tests для approve і deny path.

## Як трактувати результат

- `PASS` — усі автоматичні перевірки пройшли і в `--guided` режимі всі physical checkpoints були підтверджені людиною.
- `FAIL` — є хоча б одна автоматична або ручна помилка.
- `INCOMPLETE` — автоматична частина може бути зеленою, але physical checklist ще не завершений.

Runner навмисно **не** ставить автоматичний PASS для речей, які можна перевірити лише очима/взаємодією з реальною програмою. Це стосується, наприклад, мовної якості відповіді, правильності restored permission card та фактичної відповідності citation потрібному PDF-фрагменту.

## Приватність звіту

Acceptance report може містити:

- версію macOS;
- архітектуру Mac;
- Git SHA;
- назву локальної моделі;
- локальний model endpoint;
- короткий smoke-response моделі;
- результати build/signature/launch checks.

Runner навмисно не експортує Personal Memory DB, Knowledge DB, вміст вибраних файлів або authentication secrets.

## Release правило

Навіть `Overall: PASS` не робить merge автоматичним. Перед зміною PR #1 з Draft потрібно:

1. звірити SHA у report із поточним head PR #1;
2. переконатися, що exact SHA має зелений Linux Core, macOS Core та IlumMac CI;
3. переконатися, що `Ilum-macOS` artifact існує для того самого SHA;
4. переглянути report на physical failures/skips;
5. переконатися, що Issue #2 відповідає продемонстрованій поведінці;
6. лише після цього закривати Issue #2 та переводити PR у Ready for review.
