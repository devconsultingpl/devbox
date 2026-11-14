#!/bin/sh
# devbox harness — the `pi` coding agent and the tools it needs. Selected by ARG
# HARNESS at image build; the harness scripts are the only place an agent is
# named (D1, criterion 7), so `none` stays agent-free and a future harness is one
# more file consuming the same payload.
#
# The packages and the skills arrive as build contexts that bin/devbox
# materialises from the two checkouts and stamps (D2/D3) — installed here, never
# fetched to decide *which* version. pi loads the TypeScript sources directly
# (0004 F2), so only dependencies are installed; skillset builds its own bundle
# and syncs its artifacts.
#
# D4 — permissions are explicit allow-all: an `ask` in an unattended run is a
# stall, and absence would leave nothing to audit. D5 — all 13 browser tools are
# active at startup and the browser is Playwright's headless shell, pinned.
# I4 / I5 — no credential is baked, copied or mounted; a provider key arrives at
# run time through the environment, from the operator.
set -eu

node_version=22.19.0
pi_version=1.5.2
playwright_version=1.63.0

payload=/opt/devbox/payload
agent=/opt/devbox/agent
# The empty sentinel context carries neither source; check both before moving one,
# or a partial payload fails as a bare `mv`.
for name in pi-extensions skillset; do
  [ -f "$payload/$name/package.json" ] || {
    echo "harness pi: no agent payload in $name — run devbox up, which materialises the sources" >&2
    exit 1
  }
done

case "$(dpkg --print-architecture)" in
  amd64) node_arch=x64 ;;
  arm64) node_arch=arm64 ;;
  *) echo "harness: unsupported arch: $(dpkg --print-architecture)" >&2; exit 1 ;;
esac
curl -fsSL "https://nodejs.org/dist/v${node_version}/node-v${node_version}-linux-${node_arch}.tar.gz" \
  | tar -xz -C /usr/local --strip-components=1

mkdir -p "$agent"
mv "$payload/pi-extensions" "$agent/pi-extensions"
mv "$payload/skillset" "$agent/skillset"

{
  printf 'pi-extensions %s\n' "${PIEXT_SOURCE:-}"
  printf 'skillset %s\n' "${SKILLSET_SOURCE:-}"
} > "$agent/SOURCES"

npm install -g --ignore-scripts --no-audit --no-fund \
  "@earendil-works/pi-coding-agent@$pi_version"

# The peers are what the extensions import at runtime (typebox breaks
# pi-playwright at load; the agent API modules are imported for real, not only
# for types), and --omit=dev does not install them (F9).
#
# `npm install`, not `npm ci`: this is a working tree, and a workspace member
# added but not locked — the very dirty-tree case D2 exists to ship — makes
# `npm ci` refuse the tree (measured 2026-11-13). Reproducibility here comes from
# the stamp, not from the lock.
cd "$agent/pi-extensions"
npm install --omit=dev --no-save --ignore-scripts --legacy-peer-deps --no-audit --no-fund
npm install --omit=dev --no-save --ignore-scripts --no-audit --no-fund --legacy-peer-deps \
  "@earendil-works/pi-ai@$pi_version" "@earendil-works/pi-coding-agent@$pi_version" \
  "@earendil-works/pi-tui@$pi_version" @sinclair/typebox@0.34.52 typebox@1.4.7 \
  yaml@2.9.1 @standard-schema/spec@1.1.0

# skillset builds its own dist/ (untracked in the source, so never in the
# context) and installs its artifacts; sync declares every target, so the
# claude-code and opencode writes land in the box's HOME and are harmless noise.
cd "$agent/skillset"
npm ci --ignore-scripts --no-audit --no-fund
npm run build
HOME=/root node dist/cli.js sync
npm prune --omit=dev --no-audit --no-fund

npm install -g --no-audit --no-fund "playwright@$playwright_version"
case "${BROWSER:-headless}" in
  full) set -- chromium-headless-shell chromium ;;
  headless) set -- chromium-headless-shell ;;
  *) echo "harness pi: BROWSER must be headless or full, not: $BROWSER" >&2; exit 1 ;;
esac
playwright install --with-deps "$@"

# D5 — one stable path for the pinned headless binary: the cache directory is
# version-suffixed, the symlink is not. `PI_PLAYWRIGHT_EXECUTABLE` points at it in
# the container's environment (compose), so pi sees it however it is launched —
# not only under a zsh that sources `~/.zshenv`.
shell_bin=$(find /root/.cache/ms-playwright -type f \( -name headless_shell -o -name chrome-headless-shell \) | LC_ALL=C sort | head -1)
[ -n "$shell_bin" ] || { echo "harness pi: no headless shell after playwright install:" >&2; find /root/.cache/ms-playwright -maxdepth 3 >&2; exit 1; }
mkdir -p /opt/devbox/browser
ln -sf "$shell_bin" /opt/devbox/browser/headless_shell

mkdir -p /root/.pi/agent/extensions/pi-permission-system
cat > /root/.pi/agent/extensions/pi-permission-system/config.json <<'JSON'
{
  "permission": {
    "*": "allow",
    "bash": { "*": "allow" },
    "external_directory": "allow"
  }
}
JSON

# D1 — every package is a path inside this image, resolved without copying
# (0004 F2). D5 — the 13 browser tools are `+name` entries, so they are active
# from the first turn instead of after a /playwright.
cat > /root/.pi/agent/settings.json <<'JSON'
{
  "defaultProjectTrust": "always",
  "enableInstallTelemetry": false,
  "packages": [
    "/opt/devbox/agent/pi-extensions/packages/flow",
    "/opt/devbox/agent/pi-extensions/packages/flow-workflow",
    "/opt/devbox/agent/pi-extensions/packages/flow-advisor",
    "/opt/devbox/agent/pi-extensions/packages/flow-args",
    "/opt/devbox/agent/pi-extensions/packages/flow-ask-user-question",
    "/opt/devbox/agent/pi-extensions/packages/flow-i18n",
    "/opt/devbox/agent/pi-extensions/packages/flow-todo",
    "/opt/devbox/agent/pi-extensions/packages/flow-web-tools",
    "/opt/devbox/agent/pi-extensions/packages/pi-subagents",
    "/opt/devbox/agent/pi-extensions/packages/pi-playwright",
    "/opt/devbox/agent/pi-extensions/packages/pi-permission-system"
  ],
  "defaultTools": [
    "+browser_navigate",
    "+browser_click",
    "+browser_fill_form",
    "+browser_type",
    "+browser_press_key",
    "+browser_snapshot",
    "+browser_take_screenshot",
    "+browser_console_messages",
    "+browser_wait_for",
    "+browser_evaluate",
    "+browser_tabs",
    "+browser_resize",
    "+browser_close"
  ]
}
JSON

npm cache clean --force
rm -rf /root/.npm /tmp/* /var/lib/apt/lists/* /usr/local/include/node 2>/dev/null || true
