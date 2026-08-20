#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OLLAMA_BASE_URL="${ILUM_OLLAMA_BASE_URL:-http://127.0.0.1:11434}"
TAGS_URL="${ILUM_OLLAMA_TAGS_URL:-${OLLAMA_BASE_URL}/api/tags}"
CHAT_URL="${ILUM_MODEL_URL:-${OLLAMA_BASE_URL}/v1/chat/completions}"
CHAT_SMOKE=0

if [[ "${1:-}" == "--chat" ]]; then
  CHAT_SMOKE=1
fi

pass() { printf 'PASS  %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; exit 1; }

printf 'Ilum doctor\n===========\n'
printf 'Repository: %s\n' "$ROOT"
printf 'Platform:   %s\n\n' "$(uname -s)"

if command -v swift >/dev/null 2>&1; then
  pass "Swift: $(swift --version | head -n 1)"
else
  fail "Swift is not installed or not on PATH."
fi

if command -v sqlite3 >/dev/null 2>&1; then
  pass "SQLite: $(sqlite3 --version | awk '{print $1}')"
else
  warn "sqlite3 CLI is not on PATH. Ilum links SQLite through the system SDK, but the CLI is useful for diagnostics."
fi

command -v curl >/dev/null 2>&1 || fail "curl is required by the doctor script."
command -v python3 >/dev/null 2>&1 || fail "python3 is required by the doctor script."

TAGS_FILE="$(mktemp)"
trap 'rm -f "$TAGS_FILE"' EXIT

if curl --silent --show-error --fail --max-time 5 "$TAGS_URL" > "$TAGS_FILE"; then
  pass "Ollama catalog reachable at $TAGS_URL"
else
  fail "Ollama is not reachable at $TAGS_URL. Start Ollama, or set ILUM_OLLAMA_BASE_URL / ILUM_OLLAMA_TAGS_URL."
fi

DISCOVERED_MODEL="$(python3 - "$TAGS_FILE" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    payload = json.load(f)
models = []
for item in payload.get('models', []):
    name = (item.get('name') or item.get('model') or '').strip()
    if not name:
        continue
    lower = name.lower()
    if any(token in lower for token in ('embed', 'embedding', 'nomic-embed', 'mxbai', 'bge-', 'rerank')):
        continue
    size = int(item.get('size') or 0)
    score = 0
    if 'instruct' in lower: score += 50
    if 'chat' in lower: score += 40
    if 'qwen' in lower: score += 20
    if 'llama' in lower: score += 18
    if 'mistral' in lower: score += 16
    if 'gemma' in lower: score += 14
    if 'phi' in lower: score += 10
    models.append((score, size, name.lower(), name))
models.sort(key=lambda x: (-x[0], -x[1], x[2]))
print(models[0][3] if models else '')
PY
)"

MODEL="${ILUM_MODEL:-$DISCOVERED_MODEL}"
if [[ -z "$MODEL" ]]; then
  fail "No local chat model was found. Install an Ollama chat/instruct model, or set ILUM_MODEL."
fi

if [[ -n "${ILUM_MODEL:-}" ]]; then
  pass "Chat model configured explicitly: $MODEL"
else
  pass "Chat model auto-detected: $MODEL"
fi

printf 'INFO  Chat endpoint: %s\n' "$CHAT_URL"

if [[ "$CHAT_SMOKE" -eq 1 ]]; then
  PAYLOAD="$(python3 - "$MODEL" <<'PY'
import json, sys
print(json.dumps({
    'model': sys.argv[1],
    'messages': [{'role': 'user', 'content': 'Reply with exactly ILUM_OK'}],
    'stream': False,
}))
PY
)"

  RESPONSE_FILE="$(mktemp)"
  trap 'rm -f "$TAGS_FILE" "$RESPONSE_FILE"' EXIT
  if curl --silent --show-error --fail --max-time 120 \
      -H 'Content-Type: application/json' \
      --data "$PAYLOAD" \
      "$CHAT_URL" > "$RESPONSE_FILE"; then
    CONTENT="$(python3 - "$RESPONSE_FILE" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    payload = json.load(f)
try:
    print((payload['choices'][0]['message'].get('content') or '').strip())
except Exception:
    print('')
PY
)"
    if [[ -n "$CONTENT" ]]; then
      pass "Local chat request returned assistant content."
      printf 'INFO  Model response: %s\n' "$CONTENT"
    else
      fail "Chat endpoint returned no assistant content. Inspect $CHAT_URL and model compatibility."
    fi
  else
    fail "Local chat smoke request failed at $CHAT_URL."
  fi
fi

printf '\nIlum local prerequisites look usable.\n'
printf 'Run the app with: %s/Scripts/run.sh\n' "$ROOT"
