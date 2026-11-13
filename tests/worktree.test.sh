#!/bin/sh
# tests/worktree.test.sh — the worktree boundary, end to end (0003).
#
# Every assertion runs the real CLI and the real container: a box on a git
# worktree must see that worktree and its gitdir at their own host paths, commit
# when the policy allows it, refuse to commit when it does not, and leave the
# host's git state untouched by `down`.
#
# Scratch state lives under $HOME (colima shares ~ and /tmp/colima only) and is
# removed with `find -delete`; containers are asserted by compose label, never by
# a global count. Runs with `sh tests/worktree.test.sh`.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
devbox="$root/bin/devbox"
work=$(mktemp -d "$HOME/.devbox-worktree.XXXXXX")
export XDG_STATE_HOME="$work/state"
sock="$HOME/.colima/default/docker.sock"
[ -S "$sock" ] || sock="$HOME/.colima/docker.sock"
export DOCKER_HOST="unix://$sock" DOCKER_CONFIG="$XDG_STATE_HOME/devbox/docker"

boxes=""
cleanup() {
  for path in $boxes; do "$devbox" down base "$path" >/dev/null 2>&1 || true; done
  [ -n "${probe:-}" ] && docker volume rm "$probe" >/dev/null 2>&1 || true
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
refute() { # refute <label> <command ...> — the command must fail
  label=$1; shift
  if "$@" > "$work/out" 2>&1; then
    fail=$((fail + 1)); printf 'FAIL  %s (unexpectedly succeeded)\n' "$label"
  else
    pass=$((pass + 1)); printf 'ok    %s\n' "$label"
  fi
}
says() { # says <pattern> <label> — assert what the last command printed
  if grep -qF -- "$1" "$work/out"; then
    pass=$((pass + 1)); printf 'ok    %s\n' "$2"
  else
    fail=$((fail + 1)); printf 'FAIL  %s: no %s\n' "$2" "$1"; sed 's/^/      /' "$work/out"
  fi
}
container() { # container <worktree> — the box's container name, empty if none
  slug=$(basename "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/-\{1,\}$//')
  docker ps --format '{{.Names}} {{.Label "com.docker.compose.project"}}' |
    awk -v b="devbox-$slug" 'index($2, b "-") == 1 { print $1; exit }'
}
repo() { # repo <name> — a scratch repository with one commit
  mkdir -p "$work/$1"
  git -C "$work/$1" init -q
  git -C "$work/$1" config user.email devbox@test
  git -C "$work/$1" config user.name devbox
  printf 'hello\n' > "$work/$1/README"
  git -C "$work/$1" add README
  git -C "$work/$1" commit -qm init
}
up() { boxes="$boxes $1"; "$devbox" up base "$1" >/dev/null; }

repo main
git -C "$work/main" worktree add -q .devbox/wt/feat-a -b feat-a
git -C "$work/main" worktree add -q .devbox/wt/feat-b -b feat-b
a="$work/main/.devbox/wt/feat-a"
b="$work/main/.devbox/wt/feat-b"

check "up on a worktree" up "$a"
box=$(container "$a")
check "box exists" test -n "$box"
check "working directory is the worktree's own path" \
  sh -c "docker exec '$box' sh -c 'test \"\$PWD\" = \"$a\"'"
check "box is on the worktree's branch" \
  sh -c "docker exec '$box' git rev-parse --abbrev-ref HEAD | grep -qx feat-a"
check "main checkout is not reachable from the box" \
  sh -c "! docker exec '$box' test -e '$work/main/README'"
check "gitdir of a sibling worktree is reachable (the accepted boundary)" \
  sh -c "docker exec '$box' test -f '$work/main/.git/worktrees/feat-b/gitdir'"

check "a commit inside the box succeeds" \
  sh -c "docker exec '$box' sh -c 'printf x > box.txt && git add box.txt && git commit -qm frombox'"
check "the host sees that commit" \
  sh -c "git -C '$a' log --oneline -1 | grep -q frombox"

check "doctor accepts a worktree" "$devbox" doctor base "$a"
check "doctor accepts an ordinary repository" "$devbox" doctor base "$work/main"
mkdir -p "$a/sub"
refute "doctor refuses a subdirectory of a worktree" "$devbox" doctor base "$a/sub"
says "point devbox at the worktree root" "subdirectory message"
check "up is idempotent" up "$a"

check "up on an ordinary repository" up "$work/main"
main_box=$(container "$work/main")
check "an ordinary repository's box commits" \
  sh -c "docker exec '$main_box' sh -c 'printf m > main.txt && git add main.txt && git commit -qm mainbox'"
"$devbox" down base "$work/main" >/dev/null

echo "--- two boxes on one repository"
check "up a second worktree" up "$b"
box2=$(container "$b")
check "both boxes run" test -n "$box2"
check "each box is on its own branch" \
  sh -c "docker exec '$box2' git rev-parse --abbrev-ref HEAD | grep -qx feat-b"
check "the two boxes are separate compose projects" \
  sh -c "! test \"\$(docker inspect -f '{{ index .Config.Labels \"com.docker.compose.project\" }}' '$box')\" = \"\$(docker inspect -f '{{ index .Config.Labels \"com.docker.compose.project\" }}' '$box2')\""
"$devbox" down base "$a" >/dev/null
check "down of one leaves the other running" test -n "$(container "$b")"

echo "--- review-only"
check "policy records review-only" "$devbox" policy review-only "$b"
check "policy --list shows the path and mode" \
  sh -c "'$devbox' policy --list | grep -q \"review-only.*$b\""
check "up in review-only" up "$b"
box2=$(container "$b")
check "the working tree stays writable" \
  sh -c "docker exec '$box2' sh -c 'printf p > PROOF.txt'"
check "a commit fails at the filesystem level" \
  sh -c "docker exec '$box2' sh -c 'git add PROOF.txt' 2>&1 | grep -q 'Read-only file system'"
check "status still works" sh -c "docker exec '$box2' git status --short >/dev/null"
check "COMMIT_PROPOSAL.md is writable" \
  sh -c "docker exec '$box2' sh -c 'printf proposal > COMMIT_PROPOSAL.md'"
check "the host can commit what the box proposed" \
  sh -c "git -C '$b' add COMMIT_PROPOSAL.md PROOF.txt && git -C '$b' commit -qm proposal"
check "policy records commits-allowed again" "$devbox" policy commits-allowed "$b"
check "up after the policy change" up "$b"
box2=$(container "$b")
check "committing works again" \
  sh -c "docker exec '$box2' sh -c 'printf y > again.txt && git add again.txt && git commit -qm again'"
printf 'nonsense\n%s\n' "$b" > "$XDG_STATE_HOME/devbox/policy/$(printf '%s' "$b" | shasum -a 256 | cut -c1-16).policy"
refute "an unreadable policy refuses up" "$devbox" up base "$b"
says "unreadable commit policy" "unreadable policy message"
"$devbox" policy commits-allowed "$b" >/dev/null

echo "--- a repository with an unreadable git extension"
repo extension
git -C "$work/extension" worktree add -q --relative-paths .devbox/wt/rel -b rel
rel="$work/extension/.devbox/wt/rel"
refute "up refuses a relative worktree" "$devbox" up base "$rel"
says "extensions.relativeworktrees" "the refusal names the extension"
refute "doctor refuses it too" "$devbox" doctor base "$rel"
check "nothing was started for it" test -z "$(container "$rel")"

echo "--- a worktree name the compose slug rewrites"
repo dotted
git -C "$work/dotted" worktree add -q .devbox/wt/feat.c -b feat.c
dotted="$work/dotted/.devbox/wt/feat.c"
check "up on a dotted worktree name" up "$dotted"
check "the container is found for a dotted name" test -n "$(container "$dotted")"
check "it is on its own branch" \
  sh -c "docker exec '$(container "$dotted")' git rev-parse --abbrev-ref HEAD | grep -qx 'feat.c'"
"$devbox" down base "$dotted" >/dev/null

echo "--- down leaves nothing behind"
project=$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$box2")
probe="devbox-review-probe-$$"
docker volume create --label "com.docker.compose.project=$project" \
  --label com.docker.compose.volume=devbox-slr "$probe" >/dev/null
"$devbox" down base "$b" >/dev/null
check "no container for the worktree" test -z "$(container "$b")"
check "no container left under that compose project" \
  sh -c "! docker ps -a -q --filter label=com.docker.compose.project=$project | grep -q ."
check "the down path removes a labelled slr volume" \
  sh -c "! docker volume inspect '$probe' >/dev/null 2>&1"
check "no volume left under that compose project" \
  sh -c "! docker volume ls -q --filter label=com.docker.compose.project=$project | grep -q ."
check "the worktree still exists on the host" test -d "$b"
check "the host's git state is intact" sh -c "git -C '$b' log --oneline -3 | grep -q again"

printf '\n%s ok, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
