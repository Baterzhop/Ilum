# Physical macOS acceptance

Цей етап потрібен перед тим, як Ilum v1 можна буде вивести з Draft і розглядати merge у `main`.

GitHub Actions уже перевіряє компіляцію, тести, пакування та codesign. Але CI не може довести, що Ilum правильно працює саме на реальному Mac із локально встановленим Ollama, реальними security-scoped permissions та реальною поведінкою UI.

## Один рекомендований запуск

На Mac, у чистому checkout поточного `integration/ilum-v1`:

```bash
bash Scripts/acceptance.sh --guided
```

Runner:

1. фіксує exact Git SHA, macOS та архітектуру машини;
2. перевіряє, що checkout чистий;
3. запускає `Scripts/doctor.sh --chat` і робить реальний запит до локальної chat-моделі;
4. збирає release `Ilum.app`;
5. перевіряє executable, `Info.plist` та ad-hoc codesign;
6. запускає packaged app і перевіряє, що процес не завершується одразу;
7. проводить через ручні acceptance-пункти для chat, multilingual context, restart, Stop, Personal Memory, file permissions, pending-permission recovery, PDF/RAG, citations, sparse fallback та model failure;
8. створює Markdown-звіт у `dist/acceptance/`.

`dist/` ігнорується Git, тому acceptance report не потрапляє в репозиторій випадково.

## Інші режими

Лише автоматичні локальні перевірки, без запуску UI:

```bash
bash Scripts/acceptance.sh --auto-only
```

Автоматичні перевірки + checklist-файл, але без запуску `Ilum.app`:

```bash
bash Scripts/acceptance.sh --no-launch
```

## Як трактувати результат

- `PASS` — усі автоматичні перевірки пройшли і в `--guided` режимі всі physical checkpoints були підтверджені людиною.
- `FAIL` — є хоча б одна автоматична або ручна помилка.
- `INCOMPLETE` — автоматична частина може бути зеленою, але physical checklist ще не завершений.

Runner навмисно **не** ставить автоматичний PASS для речей, які можна перевірити лише очима/взаємодією з реальною програмою. Це стосується, наприклад, коректності UI, мовної якості відповіді, відновлення permission card після relaunch та фактичної відповідності citation потрібному PDF-фрагменту.

## Приватність звіту

Acceptance report може містити:

- версію macOS;
- архітектуру Mac;
- Git SHA;
- назву локальної моделі;
- локальний model endpoint;
- короткий smoke-response моделі;
- результати build/signature checks.

Runner навмисно не експортує Personal Memory DB, Knowledge DB, вміст вибраних файлів або authentication secrets.

## Release правило

Навіть `Overall: PASS` не робить merge автоматичним. Перед зміною PR #1 з Draft потрібно:

1. звірити SHA у report із поточним head PR #1;
2. переконатися, що exact SHA має зелений Linux Core, macOS Core та IlumMac CI;
3. переконатися, що `Ilum-macOS` artifact існує для того самого SHA;
4. переглянути report на physical failures;
5. лише після цього закривати Issue #2 та переводити PR у Ready for review.
