#!/bin/sh
# devbox harness — the `pi` coding agent, selected by ARG HARNESS at image
# build; the harness scripts are the only place an agent is named (criterion 7).
#
# D5 / criterion 8 — the settings below list no packages at all: the host's
# permission extension is deliberately absent, because inside the box the
# boundary replaces the prompt — permissive by absence, not by a profile.
# I4 / I5 — no credential is baked, copied, or mounted; a provider key arrives
# at run time through the environment, from the operator.
set -eu

# pi needs Node >= 22.19; Ubuntu ships 18, so take the official build.
node_version=22.19.0
case "$(dpkg --print-architecture)" in
  amd64) node_arch=x64 ;;
  arm64) node_arch=arm64 ;;
  *) echo "harness: unsupported arch: $(dpkg --print-architecture)" >&2; exit 1 ;;
esac
curl -fsSL "https://nodejs.org/dist/v${node_version}/node-v${node_version}-linux-${node_arch}.tar.gz" \
  | tar -xz -C /usr/local --strip-components=1

npm install -g --ignore-scripts @earendil-works/pi-coding-agent

mkdir -p /root/.pi/agent
cat > /root/.pi/agent/settings.json <<'JSON'
{
  "defaultProjectTrust": "always",
  "enableInstallTelemetry": false
}
JSON
