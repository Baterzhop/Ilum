#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="${ILUM_ACCEPTANCE_DIR:-$ROOT/dist/acceptance}"
GUIDED=0
LAUNCH=1
AUTO_ONLY=0

usage() {
  cat <<'USAGE'
Usage: bash Scripts/acceptance.sh [--guided] [--auto-only] [--no-launch]

  --guided     Run the physical acceptance checklist interactively.
  --auto-only  Run only automated local checks; do not launch Ilum.
  --no-launch  Build and verify Ilum.app but do not launch either app path.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --guided) GUIDED=1 ;;
    --auto-only) AUTO_ONLY=1; LAUNCH=0 ;;
    --no-launch) LAUNCH=0 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [[ "$AUTO_ONLY" -eq 1 && "$GUIDED" -eq 1 ]]; then
  printf '%s\n' '--auto-only and --guided cannot be used together.' >&2
  exit 2
fi
if [[ "$GUIDED" -eq 1 && ! -t 0 ]]; then
  printf '%s\n' '--guided requires an interactive terminal.' >&2
  exit 2
fi

mkdir -p "$REPORT_DIR"
STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
REPORT="$REPORT_DIR/physical-acceptance-$STAMP.md"
AUTO_FAILURES=0
AUTO_PASSES=0
MANUAL_TOTAL=0
MANUAL_PASSES=0
MANUAL_FAILURES=0
MANUAL_SKIPS=0
BUILD_OK=0

append() { printf '%s\n' "$*" >> "$REPORT"; }

record_auto() {
  local state="$1" label="$2" detail="${3:-}"
  if [[ "$state" == "PASS" ]]; then
    AUTO_PASSES=$((AUTO_PASSES + 1))
    append "- [x] **$label**${detail:+ — $detail}"
    printf 'PASS  %s%s\n' "$label" "${detail:+ — $detail}"
  else
    AUTO_FAILURES=$((AUTO_FAILURES + 1))
    append "- [ ] **$label** — FAIL${detail:+: $detail}"
    printf 'FAIL  %s%s\n' "$label" "${detail:+ — $detail}" >&2
  fi
}

append_log_details() {
  local label="$1" log="$2"
  append ""
  append "<details><summary>$label output</summary>"
  append ""
  append '```text'
  cat "$log" >> "$REPORT"
  append '```'
  append ""
  append '</details>'
  append ""
}

run_check() {
  local label="$1"
  shift
  local log status
  log="$(mktemp)"
  if "$@" >"$log" 2>&1; then
    status=0
    record_auto PASS "$label"
  else
    status=$?
    record_auto FAIL "$label" "exit $status"
  fi
  append_log_details "$label" "$log"
  rm -f "$log"
  return "$status"
}

run_source_launch_smoke() {
  local label="Source launch via Scripts/run.sh"
  local log launcher_pid attempts pids status
  log="$(mktemp)"
  bash "$ROOT/Scripts/run.sh" >"$log" 2>&1 &
  launcher_pid=$!
  attempts=0

  while [[ "$attempts" -lt 120 ]]; do
    pids="$(pgrep -x IlumMac 2>/dev/null || true)"
    if [[ -n "$pids" ]]; then
      record_auto PASS "$label" "IlumMac process started from swift run"
      kill $pids >/dev/null 2>&1 || true
      kill "$launcher_pid" >/dev/null 2>&1 || true
      wait "$launcher_pid" >/dev/null 2>&1 || true
      append_log_details "$label" "$log"
      rm -f "$log"
      return 0
    fi

    if ! kill -0 "$launcher_pid" >/dev/null 2>&1; then
      wait "$launcher_pid" >/dev/null 2>&1
      status=$?
      record_auto FAIL "$label" "launcher exited before IlumMac became observable (exit $status)"
      append_log_details "$label" "$log"
      rm -f "$log"
      return 1
    fi

    sleep 1
    attempts=$((attempts + 1))
  done

  kill "$launcher_pid" >/dev/null 2>&1 || true
  wait "$launcher_pid" >/dev/null 2>&1 || true
  record_auto FAIL "$label" "IlumMac did not become observable before the launch-smoke deadline"
  append_log_details "$label" "$log"
  rm -f "$log"
  return 1
}

manual_check() {
  local label="$1" instruction="$2"
  MANUAL_TOTAL=$((MANUAL_TOTAL + 1))
  if [[ "$GUIDED" -eq 0 ]]; then
    append "- [ ] **$label** — $instruction"
    return
  fi

  printf '\n[%d] %s\n%s\n' "$MANUAL_TOTAL" "$label" "$instruction"
  local answer
  while true; do
    read -r -p 'Result [p=pass / f=fail / s=skip]: ' answer
    case "$answer" in
      p|P|pass|PASS|Pass)
        MANUAL_PASSES=$((MANUAL_PASSES + 1))
        append "- [x] **$label** — PASS. $instruction"
        break
        ;;
      f|F|fail|FAIL|Fail)
        MANUAL_FAILURES=$((MANUAL_FAILURES + 1))
        append "- [ ] **$label** — **FAIL**. $instruction"
        break
        ;;
      s|S|skip|SKIP|Skip|'')
        MANUAL_SKIPS=$((MANUAL_SKIPS + 1))
        append "- [ ] **$label** — SKIPPED. $instruction"
        break
        ;;
      *) printf '%s\n' 'Enter p, f, or s.' ;;
    esac
  done
}

HOST_OS="$(uname -s 2>/dev/null || printf unknown)"
HOST_ARCH="$(uname -m 2>/dev/null || printf unknown)"
MACOS_VERSION="$(sw_vers -productVersion 2>/dev/null || printf unavailable)"
GIT_SHA="unavailable"
GIT_BRANCH="unavailable"
GIT_DIRTY="unknown"
if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf unavailable)"
  GIT_BRANCH="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
  [[ -n "$GIT_BRANCH" ]] || GIT_BRANCH="detached"
  if [[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=normal 2>/dev/null)" ]]; then
    GIT_DIRTY="clean"
  else
    GIT_DIRTY="dirty"
  fi
fi

cat > "$REPORT" <<EOF_REPORT
# Ilum v1 physical macOS acceptance

- UTC timestamp: $STAMP
- Host: $HOST_OS / $HOST_ARCH
- macOS: $MACOS_VERSION
- Git branch: $GIT_BRANCH
- Git SHA: $GIT_SHA
- Worktree: $GIT_DIRTY

This report is local-only by default because it is written under \`dist/\`, which is ignored by Git. It records environment/model diagnostics but intentionally does not dump Personal Memory, Knowledge databases, selected-file contents, or authentication secrets.

## Automated local evidence
EOF_REPORT

printf 'Ilum physical acceptance\n========================\n'
printf 'Report: %s\n' "$REPORT"
printf 'Git:    %s (%s, %s)\n\n' "$GIT_SHA" "$GIT_BRANCH" "$GIT_DIRTY"

if [[ "$HOST_OS" == "Darwin" ]]; then
  record_auto PASS "macOS host" "$MACOS_VERSION / $HOST_ARCH"
else
  record_auto FAIL "macOS host" "found $HOST_OS"
fi

if [[ "$GIT_SHA" != "unavailable" ]]; then
  record_auto PASS "Git revision recorded" "$GIT_SHA"
else
  record_auto FAIL "Git revision recorded" "repository revision unavailable"
fi

if [[ "$GIT_DIRTY" == "clean" ]]; then
  record_auto PASS "Clean source checkout"
elif [[ "$GIT_DIRTY" == "dirty" ]]; then
  record_auto FAIL "Clean source checkout" "uncommitted/untracked files are present"
else
  record_auto FAIL "Clean source checkout" "Git worktree state unavailable"
fi

run_check "Local model doctor + real chat smoke" bash "$ROOT/Scripts/doctor.sh" --chat || true

if [[ "$LAUNCH" -eq 1 ]]; then
  if [[ "$HOST_OS" != "Darwin" ]]; then
    append "- [ ] **Source launch via Scripts/run.sh** — not attempted on non-macOS host"
  elif pgrep -x IlumMac >/dev/null 2>&1; then
    record_auto FAIL "Clean Ilum launch state" "IlumMac is already running; close it before acceptance so launch checks cannot false-pass"
    append "- [ ] **Source launch via Scripts/run.sh** — blocked by pre-existing IlumMac process"
  else
    record_auto PASS "Clean Ilum launch state" "no pre-existing IlumMac process"
    run_source_launch_smoke || true
  fi
else
  append "- [ ] **Source launch via Scripts/run.sh** — not requested by this run"
fi

if run_check "Release Ilum.app build + ad-hoc signature" bash "$ROOT/Scripts/build-app.sh"; then
  BUILD_OK=1
fi

APP="$ROOT/dist/Ilum.app"
if [[ -x "$APP/Contents/MacOS/IlumMac" ]]; then
  record_auto PASS "Packaged executable exists"
else
  record_auto FAIL "Packaged executable exists" "$APP/Contents/MacOS/IlumMac missing"
fi
if command -v plutil >/dev/null 2>&1 && plutil -lint "$APP/Contents/Info.plist" >/dev/null 2>&1; then
  record_auto PASS "Info.plist validates"
else
  record_auto FAIL "Info.plist validates"
fi
if command -v codesign >/dev/null 2>&1 && codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
  record_auto PASS "Ilum.app signature verifies"
else
  record_auto FAIL "Ilum.app signature verifies"
fi

if [[ "$LAUNCH" -eq 1 && "$HOST_OS" == "Darwin" && "$BUILD_OK" -eq 1 ]]; then
  if pgrep -x IlumMac >/dev/null 2>&1; then
    record_auto FAIL "Packaged app launch smoke" "IlumMac is already running before packaged launch; refusing a false-positive check"
  elif open "$APP"; then
    attempts=0
    while [[ "$attempts" -lt 15 ]] && ! pgrep -x IlumMac >/dev/null 2>&1; do
      sleep 1
      attempts=$((attempts + 1))
    done
    if pgrep -x IlumMac >/dev/null 2>&1; then
      record_auto PASS "Packaged app launch smoke" "a fresh IlumMac process is running"
    else
      record_auto FAIL "Packaged app launch smoke" "open returned success but no fresh IlumMac process became observable"
    fi
  else
    record_auto FAIL "Packaged app launch smoke" "open failed"
  fi
elif [[ "$LAUNCH" -eq 0 ]]; then
  append "- [ ] **Packaged app launch smoke** — not requested by this run"
elif [[ "$BUILD_OK" -ne 1 ]]; then
  append "- [ ] **Packaged app launch smoke** — blocked because the release bundle did not build successfully"
fi

append ""
append "## Human-observed physical behavior"
append ""

if [[ "$AUTO_ONLY" -eq 0 ]]; then
  manual_check "Packaged UI is usable" "Confirm the opened Ilum.app window renders normally, is responsive, and does not enter unexpected Safe Mode."
  manual_check "Normal local chat" "Send a normal prompt and confirm a real local-model answer completes end to end with no fabricated fallback."
  manual_check "Multilingual behavior" "Test Ukrainian, Hungarian, German, and English, then switch language inside one conversation and confirm context is preserved."
  manual_check "Conversation durability" "Create a second chat, switch between chats, quit/relaunch Ilum, and confirm the active chat and stored messages are restored correctly."
  manual_check "Stop/cancellation" "Start a long response, press Stop/Escape, then continue chatting and confirm durable history is not corrupted."
  manual_check "Personal Memory write/search" "Ask Ilum to remember one harmless stable fact. Confirm a one-shot write approval appears, approve it, relaunch, and confirm memory.search can retrieve it."
  manual_check "Personal Memory delete" "Ask Ilum to forget that exact memory. Confirm a fresh one-shot approval is required and only that record is removed."
  manual_check "Opaque file authority" "Select a harmless UTF-8 text file. Confirm Ilum refers to it by an opaque resourceID and file.readText asks permission before content reaches the model."
  manual_check "Scoped file read + bookmark reopen" "Allow a read-only file permission for the session, confirm it stays scoped to that selected resource, relaunch Ilum, and confirm the registered file can be read again through the reopened bookmark."
  manual_check "Pending permission approve after restart" "Trigger a permission card, quit before deciding, relaunch, confirm the same pending action returns without duplicating the user turn, approve it, and confirm the paused turn continues exactly once."
  manual_check "Pending permission deny after restart" "Trigger a fresh permission card, quit before deciding, relaunch, deny it, and confirm the tool action does not execute while the paused turn continues with a denial result."
  manual_check "Live permission revalidation" "On a restored permission card, confirm capability/resource/display information matches the currently registered tool/file rather than stale serialized presentation data."
  manual_check "Grounded evidence survives permission restart" "Use a turn that combines Knowledge evidence with a permission-gated tool, restart while permission is pending, then approve and confirm the continuation uses the original evidence/citations rather than silently reretrieving a different snapshot."
  manual_check "PDF Knowledge persistence + citations" "Add a text PDF to Knowledge, relaunch, ask a question answered by it, and confirm the expected document/page evidence and only valid [K#] citations are shown."
  manual_check "Document prompt-injection isolation" "Use a harmless test PDF containing an instruction-like sentence and confirm Ilum treats it as evidence text, not as authority or a permission bypass."
  manual_check "Dense-to-sparse fallback is visible" "Quit Ilum, launch with ILUM_OLLAMA_EMBED_URL=http://127.0.0.1:1/api/embed bash Scripts/run.sh, ask a question about the indexed PDF, and confirm the header shows 'Knowledge retrieval: sparse fallback' while sparse evidence/citations still work. Relaunch normally afterward."
  manual_check "Knowledge deletion" "Remove the selected indexed file and confirm its derived Knowledge/vector copies disappear and are not retrieved afterward."
  manual_check "Visible model failure" "Quit Ilum, launch with ILUM_MODEL_URL=http://127.0.0.1:1/v1/chat/completions ILUM_MODEL=acceptance-invalid bash Scripts/run.sh, send a harmless prompt, and confirm Ilum shows an explicit runtime/model error and does not append a fabricated assistant answer. Relaunch normally afterward."
fi

append ""
append "## Result"
append ""
append "- Automated passes: $AUTO_PASSES"
append "- Automated failures: $AUTO_FAILURES"
append "- Manual passes: $MANUAL_PASSES / $MANUAL_TOTAL"
append "- Manual failures: $MANUAL_FAILURES"
append "- Manual skipped/unverified: $MANUAL_SKIPS"

OVERALL="INCOMPLETE"
if [[ "$AUTO_FAILURES" -gt 0 || "$MANUAL_FAILURES" -gt 0 ]]; then
  OVERALL="FAIL"
elif [[ "$GUIDED" -eq 1 && "$MANUAL_TOTAL" -gt 0 && "$MANUAL_PASSES" -eq "$MANUAL_TOTAL" ]]; then
  OVERALL="PASS"
fi
append "- Overall: **$OVERALL**"
append ""
append "A PASS report is evidence for Issue #2, not an automatic merge authorization. PR #1 should leave Draft only after the report is reviewed and the exact report SHA is still the current release candidate."

printf '\nAutomated: %d pass / %d fail\n' "$AUTO_PASSES" "$AUTO_FAILURES"
if [[ "$GUIDED" -eq 1 ]]; then
  printf 'Manual:    %d pass / %d fail / %d skip\n' "$MANUAL_PASSES" "$MANUAL_FAILURES" "$MANUAL_SKIPS"
fi
printf 'Overall:   %s\nReport:    %s\n' "$OVERALL" "$REPORT"

if [[ "$AUTO_FAILURES" -gt 0 || "$MANUAL_FAILURES" -gt 0 ]]; then
  exit 1
fi
exit 0
