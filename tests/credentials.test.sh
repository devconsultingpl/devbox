#!/bin/sh
# tests/credentials.test.sh — criteria 14–16 of plan 0002: the model credential
# never enters the box (I5 amendment).
#
# 14a  /root/.pi/agent/models.json names the host gateway and an `$ENV` reference,
#      and holds no key-shaped value.
# 14b  no provider key exists anywhere in the box's filesystem or environment —
#      asserted by `bin/devbox-model-proxy verify`, which reads the Keychain in its
#      own memory and pipes the key to `grep -f -`, so the value never reaches this
#      script, a shell argument or a transcript.
# 14c  the token the box holds is rejected by the provider itself.
# 15   `docker inspect` prints no provider key.
# 16   the shipped host policy fragment denies the Keychain routes.
#
# Scratch state lives under $HOME and is removed with `find -delete`. The image must
# carry the current harness: this repo's own harness scripts are outside the agent
# stamp, so a stale image fails here and the message says `--rebuild`.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
devbox="$root/bin/devbox"
proxy="$root/bin/devbox-model-proxy"
work=$(mktemp -d "$HOME/.devbox-credentials.XXXXXX")
export XDG_STATE_HOME="$work/state"
sock="$HOME/.colima/default/docker.sock"
[ -S "$sock" ] || sock="$HOME/.colima/docker.sock"
export DOCKER_HOST="unix://$sock" DOCKER_CONFIG="$XDG_STATE_HOME/devbox/docker"
project=$work/project

box=""
cleanup() {
  [ -n "$box" ] && "$devbox" down sbcl "$project" >/dev/null 2>&1 || true
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
says() { # says <pattern> <label> — assert what the last command printed
  label=$2
  if grep -qF -- "$1" "$work/out"; then
    pass=$((pass + 1)); printf 'ok    %s\n' "$label"
  else
    fail=$((fail + 1)); printf 'FAIL  %s: no %s\n' "$label" "$1"; sed 's/^/      /' "$work/out"
  fi
}
refute() { # refute <pattern> <label> — the last output must not contain it
  label=$2
  if grep -qF -- "$1" "$work/out"; then
    fail=$((fail + 1)); printf 'FAIL  %s: found %s\n' "$label" "$1"; sed 's/^/      /' "$work/out"
  else
    pass=$((pass + 1)); printf 'ok    %s\n' "$label"
  fi
}

mkdir -p "$project"
git -C "$project" init -q
git -C "$project" config user.email devbox@test
git -C "$project" config user.name devbox
printf 'hello\n' > "$project/README"
git -C "$project" add README
git -C "$project" commit -qm init

check "model proxy starts on loopback" "$proxy" ensure
says "127.0.0.1:" "model proxy reports its loopback listener"

check "an agent box comes up with a live token" "$devbox" up sbcl "$project"
box=$(docker ps --format '{{.Names}} {{.Label "com.docker.compose.project"}}' |
  awk -v p="devbox-project-" 'index($2, p) == 1 { print $1; exit }')
if [ -z "$box" ]; then
  printf 'FAIL  the box has no container — the image predates the harness change; run: %s up sbcl %s --rebuild\n' "$devbox" "$project"
  exit 1
fi

# 14a — the box's config names a URL and a variable, never a credential.
check "box reads its models.json" docker exec "$box" cat /root/.pi/agent/models.json
says "http://host.lima.internal:8999/openrouter" "openrouter baseUrl is the host gateway"
says "http://host.lima.internal:8999/deepseek" "deepseek baseUrl is the host gateway"
says "\"apiKey\": \"\$DEVBOX_MODEL_TOKEN\"" "apiKey is an \$ENV reference, not a key"
refute "sk-" "no key-shaped literal in models.json"
refute "Bearer" "no bearer literal in models.json"

# 14b, 15 — no provider key in the box's filesystem or environment.
check "no provider key in the box" "$proxy" verify "$box"
says "clean" "the key is absent from the box filesystem"
refute "leak" "no provider key leaked into the box"

check "docker inspect of the box" docker inspect "$box"
refute "_API_KEY" "inspect prints no provider key variable"
refute "devbox-openrouter" "inspect does not name a Keychain item"
says "DEVBOX_MODEL_TOKEN" "the box does carry the throwaway token (the assertion is inspecting the right thing)"

# 14c — the provider itself rejects the token the box holds.
token_file=$(ls "$XDG_STATE_HOME/devbox/model-proxy/tokens"/* 2>/dev/null | head -1)
if [ -n "$token_file" ]; then
  code=$(sed -n 's/^DEVBOX_MODEL_TOKEN=//p' "$token_file" |
    curl -s -o /dev/null -w '%{http_code}' -H @- https://openrouter.ai/api/v1/models/user)
  if [ "$code" = "401" ] || [ "$code" = "403" ]; then
    pass=$((pass + 1)); printf 'ok    the provider rejects the box token (%s)\n' "$code"
  else
    fail=$((fail + 1)); printf 'FAIL  the provider answered %s for the box token, wanted 401/403\n' "$code"
  fi
else
  fail=$((fail + 1)); printf 'FAIL  no token file under %s/tokens\n' "$XDG_STATE_HOME/devbox/model-proxy"
fi

# The transport that makes the loopback bind worth anything: the box reaches it.
check "the box reaches the proxy on the host gateway" \
  docker exec "$box" curl -fsS http://host.lima.internal:8999/__devbox/health
says "ok" "proxy health answers from inside the box"

# 16 — the shipped host policy fragment denies the Keychain routes.
fragment=$root/host/pi-permissions.json
check "policy fragment is valid json" python3 -m json.tool "$fragment"
check "policy fragment denies the Keychain databases" \
  python3 -c 'import json,sys; p=json.load(open(sys.argv[1]))["permission"]; sys.exit(0 if p["path"]["~/Library/Keychains/**"]=="deny" else 1)' "$fragment"
check "policy fragment denies reading a keychain item" \
  python3 -c 'import json,sys; p=json.load(open(sys.argv[1]))["permission"]; sys.exit(0 if p["bash"]["security find-generic-password*"]=="deny" else 1)' "$fragment"
check "policy fragment denies dumping the keychain" \
  python3 -c 'import json,sys; p=json.load(open(sys.argv[1]))["permission"]; sys.exit(0 if p["bash"]["security dump-keychain*"]=="deny" else 1)' "$fragment"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
