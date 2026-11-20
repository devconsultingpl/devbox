#!/bin/sh
# tests/agent-image.test.sh — the agent layer inside a real box (0004: criteria
# 1–5 and 7, plus the stamp half of 6).
#
# Every assertion runs the real CLI or the real container: the packages pi loads,
# the artifacts skillset installed, the tools active before any /playwright, a
# headless screenshot, an unattended `rm -rf` that must not stall on an ask, and
# a `none` box that carries no agent at all.
#
# Scratch state lives under $HOME (colima shares ~ and /tmp/colima only) and is
# removed with `find -delete`; containers are asserted by compose label, never by
# a global count. Needs the same prerequisites as the runtime: colima, jq, and
# slr's source tree (`SLR_SRC`) for the `sbcl` profile.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
devbox="$root/bin/devbox"
work=$(mktemp -d "$HOME/.devbox-agent.XXXXXX")
export XDG_STATE_HOME="$work/state"
sock="$HOME/.colima/default/docker.sock"
[ -S "$sock" ] || sock="$HOME/.colima/docker.sock"
export DOCKER_HOST="unix://$sock" DOCKER_CONFIG="$XDG_STATE_HOME/devbox/docker"
skillset_repo=${SKILLSET_REPO:-$HOME/source/priv/skillset}
pi_ext_repo=${PIEXT_REPO:-$HOME/source/priv/pi-extensions}

cleanup() {
  [ -n "${project:-}" ] && "$devbox" down sbcl "$project" >/dev/null 2>&1 || true
  [ -n "${project:-}" ] && "$devbox" down base "$project" >/dev/null 2>&1 || true
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
  if grep -qF -- "$1" "$work/out"; then
    pass=$((pass + 1)); printf 'ok    %s\n' "$2"
  else
    fail=$((fail + 1)); printf 'FAIL  %s: no %s\n' "$2" "$1"; sed 's/^/      /' "$work/out"
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
absent() { # absent <pattern> <label> — the pattern must not appear in $work/out
  if grep -qE -- "$1" "$work/out"; then
    fail=$((fail + 1)); printf 'FAIL  %s: found %s\n' "$2" "$1"; sed 's/^/      /' "$work/out"
  else
    pass=$((pass + 1)); printf 'ok    %s\n' "$2"
  fi
}
container() { # container <worktree> — the box's container name, empty if none
  slug=$(basename "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/-\{1,\}$//')
  docker ps --format '{{.Names}} {{.Label "com.docker.compose.project"}}' |
    awk -v b="devbox-$slug" 'index($2, b "-") == 1 { print $1; exit }'
}
stamp() { # stamp <profile> — the stamp doctor reports for this machine
  "$devbox" doctor "$1" "$project" | sed -n 's/^devbox doctor: agent stamp //p'
}
derived() { # derived <mode> [slug] — the names skillset derives for pi, from
            # its own declarations: skill name for auto mode, frontmatter slug
            # for slash mode (which becomes the prompt filename).
  for name in $(jq -r --arg m "$1" \
      '.installs | to_entries[] | .key as $k | .value[] | select(.agent == "pi" and .mode == $m) | $k' \
      "$skillset_repo/skillset.config.json"); do
    if [ "${2:-}" = slug ]; then
      awk 'NR == 1 && /^---$/{ fm = 1; next } fm && /^---$/{ exit }
           fm && /^slug:/{ sub(/^slug:[[:space:]]*/, ""); print; exit }' \
        "$skillset_repo/dist/skills/$name/SKILL.md"
    else
      echo "$name"
    fi
  done | sort
}

project="$work/project"
mkdir -p "$project"
git init -q "$project"
git -C "$project" config user.email devbox@test
git -C "$project" config user.name devbox
printf 'hello\n' > "$project/README"
git -C "$project" add README
git -C "$project" commit -qm init

echo "--- the stamp is content, not a clock (0004 D3)"
git clone -q "$pi_ext_repo" "$work/piext"
git clone -q "$skillset_repo" "$work/skillset"
copy_stamp() { # the stamp of the copies, computed through the real CLI
  "$devbox" doctor sbcl "$project" | sed -n 's/^devbox doctor: agent stamp //p'
}
# The box below is built from these clones, not from the live checkouts: the
# payload is whatever content it is handed, and pinning it here keeps the
# "second up reuses the image" assertion from racing a checkout someone is
# editing. The clone carries no ignored file, so the dirty edit made below is
# exactly the working-tree content D2 promises to ship.
export PIEXT_REPO="$work/piext" SKILLSET_REPO="$work/skillset"
base_stamp=$(copy_stamp)
check "the same content yields the same stamp" test "$base_stamp" = "$(copy_stamp)"
printf 'dirty\n' >> "$work/piext/AGENTS.md"
check "a dirty edit moves the stamp" test "$base_stamp" != "$(copy_stamp)"
dirty_stamp=$(copy_stamp)
printf 'new\n' > "$work/piext/untracked-new.md"
check "a new untracked file moves the stamp" test "$dirty_stamp" != "$(copy_stamp)"
new_stamp=$(copy_stamp)
rm "$work/piext/untracked-new.md"
check "a deleted file moves it back" test "$new_stamp" != "$(copy_stamp)"
restored=$(copy_stamp)
check "the stamp is back to the dirty tree's" test "$restored" = "$dirty_stamp"
mkdir -p "$work/piext/node_modules"
printf 'ignored\n' > "$work/piext/node_modules/ignored.js"
check "an ignored file moves nothing" test "$restored" = "$(copy_stamp)"

# The payload guard refuses a credential-shaped name before a context exists.
git init -q "$work/dirty-source"
printf 'not a key\n' > "$work/dirty-source/server.pem"
refute "a credential-shaped payload file refuses up" \
  env PIEXT_REPO="$work/dirty-source" "$devbox" up sbcl "$project"
says "credential-shaped" "the refusal names the rule"

# A missing checkout must not fail doctor — it breaks the build, not an invariant
# — and a quoted HARNESS value must still select the agent.
if PIEXT_REPO="$work/absent" "$devbox" doctor sbcl "$project" > "$work/out" 2>&1; then
  pass=$((pass + 1)); printf 'ok    %s\n' "doctor passes with a missing source"
else
  fail=$((fail + 1)); printf 'FAIL  %s\n' "doctor passes with a missing source"; sed 's/^/      /' "$work/out"
fi
says "agent sources unavailable" "doctor says why the build would refuse"
mkdir -p "$work/profiles"
printf 'services:\n  devbox-base:\n    build:\n      args:\n        HARNESS: "pi"\n' > "$work/profiles/quoted.yaml"
DEVBOX_PROFILES_DIR="$work/profiles" "$devbox" doctor quoted "$project" > "$work/out" 2>&1 || true
says "harness pi" "a quoted HARNESS still selects the agent"
XDG_STATE_HOME="$work/doctor-state" "$devbox" doctor sbcl "$project" > "$work/out" 2>&1 || true
check "doctor writes no payload state" test ! -e "$work/doctor-state/devbox/contexts"

echo "--- an agent box (criteria 1, 2)"
# Dropping the tag forces the "no image yet" branch; the layers stay cached, so
# this also picks up a change to this repo's own Dockerfile or harness, which the
# stamp deliberately does not cover (A8).
docker rmi devbox/dev-sbcl:local >/dev/null 2>&1 || true
check "up sbcl materialises the payload and builds" "$devbox" up sbcl "$project"
says "agent stamp" "up reports the stamp it built"
box=$(container "$project")
check "the box is running" test -n "$box"
check "pi lists the local packages" docker exec "$box" pi list
for pkg in flow flow-workflow pi-subagents pi-playwright pi-permission-system; do
  check "package $pkg resolves inside /opt/devbox/agent" \
    sh -c "docker exec '$box' pi list | grep -qx '    /opt/devbox/agent/pi-extensions/packages/$pkg'"
done
check "the dirty working-tree edit is in the payload" \
  sh -c "docker exec '$box' grep -qx dirty /opt/devbox/agent/pi-extensions/AGENTS.md"
check "an ignored file is not in the payload" \
  sh -c "! docker exec '$box' test -e /opt/devbox/agent/pi-extensions/node_modules/ignored.js"
check "no package comes from a registry" \
  sh -c "! docker exec '$box' pi list | grep '^    ' | grep -qv '^    /opt/devbox/agent/'"
check "no credential-shaped filename under /opt/devbox/agent" \
  sh -c "! docker exec '$box' find /opt/devbox/agent \\( -name .env -o -name '.env.*' -o -name '*.pem' -o -name '*.key' -o -name '*.p12' -o -name 'id_rsa*' -o -name 'id_ed25519*' \\) -print | grep ."
docker run --rm --network none --entrypoint pi devbox/dev-sbcl:local --offline -p hi > "$work/out" 2>&1 || true
says "No API key" "pi starts offline and stops at the missing key"
absent 'failed to (load|install)|extension error' "no package or extension load error"

echo "--- skillset artifacts (criterion 3)"
docker exec "$box" ls /root/.pi/agent/skills 2>/dev/null | sort > "$work/box.skills"
docker exec "$box" ls /root/.pi/agent/agents 2>/dev/null | sort > "$work/box.agents"
docker exec "$box" ls /root/.pi/agent/prompts 2>/dev/null | sort > "$work/box.prompts"
derived auto > "$work/ref.skills"
derived slash slug | sed 's/$/.md/' > "$work/ref.prompts"
ls "$skillset_repo/dist/agents" | sort > "$work/ref.agents"
check "the box's skills are the source's auto-mode skills" diff "$work/ref.skills" "$work/box.skills"
check "the box's agents are the source's agents" diff "$work/ref.agents" "$work/box.agents"
check "the box's prompts are the source's slash slugs" diff "$work/ref.prompts" "$work/box.prompts"
check "the set is not empty" test -s "$work/box.skills"

echo "--- browser (criteria 4, 5)"
cat > "$work/active-tools.ts" <<'TS'
import { writeFileSync } from "node:fs";
export default function (pi: any) {
  pi.on("session_start", () => writeFileSync("/tmp/active-tools.json", JSON.stringify(pi.getActiveTools())));
}
TS
docker cp "$work/active-tools.ts" "$box:/tmp/active-tools.ts" >/dev/null
docker exec "$box" pi --offline --no-session -e /tmp/active-tools.ts -p hi >/dev/null 2>&1 || true
docker exec "$box" cat /tmp/active-tools.json > "$work/tools" 2>/dev/null || true
for tool in browser_navigate browser_click browser_fill_form browser_type browser_press_key \
            browser_snapshot browser_take_screenshot browser_console_messages browser_wait_for \
            browser_evaluate browser_tabs browser_resize browser_close; do
  check "$tool is active before any /playwright" grep -q "\"$tool\"" "$work/tools"
done
check "the default tools are still active" grep -q '"bash"' "$work/tools"
check "a headless browser screenshots a data: URL" \
  docker exec "$box" node -e '
    const { chromium } = require("/opt/devbox/agent/pi-extensions/node_modules/playwright-core");
    (async () => {
      const b = await chromium.launch({ executablePath: process.env.PI_PLAYWRIGHT_EXECUTABLE, headless: true });
      const p = await b.newPage();
      await p.setContent("<h1>devbox</h1>");
      const shot = await p.screenshot();
      await b.close();
      if (shot.subarray(1, 4).toString() !== "PNG") { console.error("not a png"); process.exit(1); }
      console.log("screenshot", shot.length, "bytes");
    })().catch((e) => { console.error("browser smoke failed:", e.message); process.exit(1); });'
check "the pinned browser is exported in the container's environment" \
  sh -c "docker exec '$box' sh -c 'test -x \"\$PI_PLAYWRIGHT_EXECUTABLE\"'"
check "the default build carries the headless shell only" \
  sh -c "docker exec '$box' ls /root/.cache/ms-playwright | grep -q '^chromium_headless_shell'"
check "the default build carries no full chromium" \
  sh -c "! docker exec '$box' ls /root/.cache/ms-playwright | grep -q '^chromium-[0-9]'"

echo "--- no permission dialog can be raised (criterion 4, ADR 0001 decision 2)"
check "the permission extension is loaded" \
  sh -c "docker exec '$box' pi list | grep -q pi-permission-system"
check "the box config turns yoloMode on" \
  sh -c "docker exec '$box' grep -q yoloMode /root/.pi/agent/extensions/pi-permission-system/config.json"
check "the box config turns the review log on" \
  sh -c "docker exec '$box' grep -q permissionReviewLog /root/.pi/agent/extensions/pi-permission-system/config.json"
check "slr's policy library is seeded disabled" \
  sh -c "docker exec '$box' cat /root/.pi/agent/extensions/pi-permission-system-slr/config.json | grep -qx '{ \"enabled\": false }'"
( printf '{"id":"1","type":"bash","command":"rm -rf /tmp/devbox-probe && printf ok > /root/probe && echo DONE"}\n'; sleep 10 ) |
  docker exec -i "$box" pi --offline --mode rpc --no-session > "$work/rpc" 2>&1 || true
check "an unattended rm -rf and an out-of-cwd write complete" \
  grep -q '"command":"bash".*"success":true' "$work/rpc"
check "the write landed" sh -c "docker exec '$box' cat /root/probe | grep -qx ok"

# The behavioural half of this — a wrapper command (`find -exec`, `xargs`) raising no
# dialog and landing a review row — is proven by a real unattended run and recorded in
# `docs/plans/0002-devbox-orchestrator.md` (Measurement: run 2026-11-20, zero dialogs,
# `READY-FOR-REVIEW.md`). It is deliberately NOT asserted here: driving it needs a live
# model turn, which made this suite flaky rather than stronger — the same probe passed in
# one container and not in another purely on first-session startup timing. What the image
# can pin is the configuration that makes it possible, and the extension's own suite pins
# the gate behaviour (`pi-permissions-system/test/yolo-unattended.test.ts`).

echo "--- the stamp is what up compares (criterion 6)"
image_stamp=$(docker image inspect devbox/dev-sbcl:local --format '{{ index .Config.Labels "devbox.agent.stamp" }}')
check "the image carries the stamp as a label" test -n "$image_stamp"
check "doctor reports the stamp the image carries" test "$image_stamp" = "$(stamp sbcl)"
check "up reuses the image when the stamp has not moved" "$devbox" up sbcl "$project"
says "image reused" "the second up builds nothing"

# Criterion 4's second half and the stamp's two other inputs, through the real
# product path: a dirty source and DEVBOX_BROWSER=full must both reach the image,
# and neither may be lost to a reuse decision.
printf 'stamp-move-probe\n' >> "$work/piext/AGENTS.md"
check "a moved stamp rebuilds the box" env DEVBOX_BROWSER=full "$devbox" up sbcl "$project"
says "devbox: building" "the rebuild is announced, not silent"
box=$(container "$project")
check "DEVBOX_BROWSER=full carries full chromium as well" \
  sh -c "docker exec '$box' ls /root/.cache/ms-playwright | grep -q '^chromium-[0-9]'"
check "the dirty edit of the second build is in the payload" \
  sh -c "docker exec '$box' grep -qx stamp-move-probe /opt/devbox/agent/pi-extensions/AGENTS.md"
sed -i '' '/^stamp-move-probe$/d' "$work/piext/AGENTS.md"
check "down removes the agent box" "$devbox" down sbcl "$project"
check "no container left" test -z "$(container "$project")"

echo "--- a none box carries no agent (criterion 7)"
check "up base on the same project" "$devbox" up base "$project"
none_box=$(container "$project")
check "the none box is running" test -n "$none_box"
check "no agent payload" sh -c "! docker exec '$none_box' test -e /opt/devbox/agent"
check "no /root/.pi" sh -c "! docker exec '$none_box' test -e /root/.pi"
check "no browser" sh -c "! docker exec '$none_box' test -e /opt/devbox/browser"
check "no chromium in the cache" sh -c "! docker exec '$none_box' test -e /root/.cache/ms-playwright"
check "doctor names the harness" "$devbox" doctor base "$project"
says "harness none" "the hierarchy is visible in doctor"
"$devbox" down base "$project" >/dev/null

printf '\n%s ok, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
