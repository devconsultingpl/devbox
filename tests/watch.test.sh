#!/bin/sh
# tests/watch.test.sh — criterion 4, and the drift guard the scope amendment asks for:
# `bin/devbox-watch` notifies on a terminal artifact, stays silent for everything in
# between, and its two names are the ones pi-extensions plan 0030 exports, so a rename
# on either side fails here rather than in a run.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
watch="$root/bin/devbox-watch"
work=$(mktemp -d "$HOME/.devbox-watch.XXXXXX")
export DEVBOX_NOTIFY_COMMAND="echo"
trap 'find "$work" -depth -delete 2>/dev/null || true' EXIT

pass=0
fail=0
check() { # check <label> <command ...>
  label=$1; shift
  if "$@" > "$work/out" 2>&1; then
    pass=$((pass + 1)); printf 'ok    %s\n' "$label"
  else
    fail=$((fail + 1)); printf 'FAIL  %s\n' "$label"; sed 's/^/      /' "$work/out"
  fi
}
says() { # says <pattern> <label>
  label=$2
  if grep -qF -- "$1" "$work/out"; then
    pass=$((pass + 1)); printf 'ok    %s\n' "$label"
  else
    fail=$((fail + 1)); printf 'FAIL  %s: no %s\n' "$label" "$1"; sed 's/^/      /' "$work/out"
  fi
}
fails() { # fails <label> <command ...> — the command must exit non-zero
  label=$1; shift
  if "$@" > "$work/out" 2>&1; then
    fail=$((fail + 1)); printf 'FAIL  %s (exit 0, wanted a timeout)\n' "$label"; sed 's/^/      /' "$work/out"
  else
    pass=$((pass + 1)); printf 'ok    %s\n' "$label"
  fi
}
silent() { # silent <pattern> <label>
  label=$2
  if grep -qF -- "$1" "$work/out"; then
    fail=$((fail + 1)); printf 'FAIL  %s: found %s\n' "$label" "$1"; sed 's/^/      /' "$work/out"
  else
    pass=$((pass + 1)); printf 'ok    %s\n' "$label"
  fi
}

project=$work/project
mkdir -p "$project/.flow/artifacts/reviews"
printf 'x\n' > "$project/.flow/artifacts/reviews/code-review__1.md"
printf 'x\n' > "$project/notes.md"

# Intermediate artifacts are not terminal, and the watcher times out instead of
# notifying — the "never" half of criterion 4.
fails "no notification for intermediate artifacts" "$watch" "$project" --interval 0.2 --timeout 1
says "no terminal artifact after 1s" "the watcher reports the timeout"
silent "devbox:" "no notification was raised"

# Success path.
printf 'x\n' > "$project/READY-FOR-REVIEW.md"
check "notifies on READY-FOR-REVIEW.md" "$watch" "$project" --interval 0.2 --timeout 5
says "ready for review" "the message names the outcome"
says "READY-FOR-REVIEW.md" "the message names the artifact"

# Exhaustion path, on a second directory so the first stays a valid success case.
blocked_project=$work/blocked
mkdir -p "$blocked_project"
printf 'x\n' > "$blocked_project/BLOCKED.md"
check "notifies on BLOCKED.md" "$watch" "$blocked_project" --interval 0.2 --timeout 5
says "blocked" "the message names the outcome"

# Drift guard: the names come from the graph, not from this repo's imagination.
terminal=$(dirname "$0")/../../pi-extensions/packages/flow/extensions/flow-core/built-ins/terminal.ts
terminal=${PIEXT_TERMINAL:-$HOME/source/priv/pi-extensions/packages/flow/extensions/flow-core/built-ins/terminal.ts}
if [ -f "$terminal" ]; then
  for pair in "READY_FOR_REVIEW:READY-FOR-REVIEW.md" "BLOCKED_ARTIFACT:BLOCKED.md"; do
    constant=${pair%%:*}
    wanted=${pair#*:}
    got=$(sed -n "s/^export const $constant = \"\(.*\)\";/\1/p" "$terminal" | head -1)
    if [ "$got" = "$wanted" ]; then
      pass=$((pass + 1)); printf 'ok    %s still resolves to %s\n' "$constant" "$wanted"
    else
      fail=$((fail + 1)); printf 'FAIL  %s is %s in the graph, %s in devbox-watch\n' "$constant" "${got:-missing}" "$wanted"
    fi
    grep -qF "$wanted" "$watch" || {
      fail=$((fail + 1)); printf 'FAIL  devbox-watch no longer names %s\n' "$wanted"
    }
  done
else
  printf 'skip  graph constants not readable at %s — set PIEXT_TERMINAL\n' "$terminal"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
