#!/bin/sh
# tests/work.test.sh — criterion 1: `devbox work` starts a detached tmux session with an
# interactive pi in the box and submits the workflow with no human at a keyboard;
# `devbox attach` names the session it would reconnect to.
#
# The brief here carries no acceptance criteria on purpose: the supervisor's own contract
# says it stops after one line in that case, so this costs a single short turn and proves
# the launcher without spending on a plan.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
devbox="$root/bin/devbox"
work=$(mktemp -d "$HOME/.devbox-work.XXXXXX")
export XDG_STATE_HOME="$work/state"
sock="$HOME/.colima/default/docker.sock"
[ -S "$sock" ] || sock="$HOME/.colima/docker.sock"
export DOCKER_HOST="unix://$sock" DOCKER_CONFIG="$XDG_STATE_HOME/devbox/docker"
project=$work/project

cleanup() {
  "$devbox" down sbcl "$project" >/dev/null 2>&1 || true
  find "$work" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

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

mkdir -p "$project"
git -C "$project" init -q
git -C "$project" config user.email devbox@test
git -C "$project" config user.name devbox
printf 'hello\n' > "$project/README"
git -C "$project" add README
git -C "$project" commit -qm init

box() {
  docker ps --format '{{.Names}} {{.Label "com.docker.compose.project"}}' |
    awk -v p="devbox-project-" 'index($2, p) == 1 { print $1; exit }'
}

# The brief carries no acceptance criteria on purpose: the supervisor's own contract says
# it stops after one line in that case, so the proof below costs a single short turn rather
# than a plan's worth of work.
check "work starts a detached session and submits the workflow" \
  "$devbox" work sbcl "$project" "a probe with no acceptance criteria"
says "session 'devbox' in the box, no client attached" "the launcher reports the detached session"
says "devbox attach sbcl $project" "the launcher names the reconnect command"

name=$(box)
if [ -z "$name" ]; then
  fail=$((fail + 1)); printf 'FAIL  no box container after `devbox work`\n'
else
  check "the tmux session exists in the box" docker exec "$name" tmux has-session -t devbox
  check "the session is running pi, not a shell" \
    docker exec "$name" tmux list-panes -t devbox -F '#{pane_current_command}'
  says "pi" "the pane's current command is the agent"
  replied=0
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    if docker exec "$name" sh -lc "ls $project/.flow/workflows/runs/*.jsonl" > /dev/null 2>&1; then
      replied=1
      break
    fi
    sleep 2
  done
  docker exec "$name" tmux capture-pane -p -t devbox > "$work/out" 2>&1 || true
  if [ "$replied" = 1 ]; then
    pass=$((pass + 1)); printf 'ok    the workflow line was submitted and a run directory exists\n'
  else
    fail=$((fail + 1)); printf 'FAIL  no run directory — the line was typed but never submitted\n'
    sed 's/^/      /' "$work/out"
  fi
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
