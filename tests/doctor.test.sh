#!/bin/sh
# tests/doctor.test.sh — `devbox doctor` must exit non-zero for a config that
# violates I1–I4, including one whose offending path arrives through compose
# interpolation, and zero for the clean profiles in profiles/.
#
# The violating profiles are generated into a scratch dir under $HOME and pointed
# at with DEVBOX_PROFILES_DIR, so nothing is ever written into the repo or into a
# project (doctor refuses canonical config that resolves inside the project).
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
devbox="$root/bin/devbox"
work=$(mktemp -d "$HOME/.devbox-doctor.XXXXXX")
project="$work/project"
mkdir -p "$project" "$work/profiles"
git init -q "$project"
trap 'find "$work" -depth -delete 2>/dev/null || true' EXIT

export DEVBOX_PROFILES_DIR="$work/profiles"
export DANGEROUS_SRC=/etc

pass=0
fail=0
expect() { # expect <ok|deny> <name> [env ...]
  want=$1
  name=$2
  shift 2
  if "$@" "$devbox" doctor "$name" "$project" > "$work/out" 2>&1; then got=ok; else got=deny; fi
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
    printf 'ok    %-14s %s\n' "$name" "$want"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-14s wanted %s, got %s\n' "$name" "$want" "$got"
    sed 's/^/      /' "$work/out"
  fi
}

profile() { printf 'services:\n  devbox:\n%s\n' "$2" > "$work/profiles/$1.yaml"; }

# The canonical profiles must be clean (sbcl also proves a type=volume mount is
# not an I1 violation — criterion 2, D10).
expect ok base env DEVBOX_PROFILES_DIR="$root/profiles"
expect ok sbcl env DEVBOX_PROFILES_DIR="$root/profiles"
expect ok go-postgres env DEVBOX_PROFILES_DIR="$root/profiles"

# I1 — the only host path is the project.
profile i1-host-bind '    volumes: ["/etc:/host-etc:ro"]'
expect deny i1-host-bind
profile i1-var-bind '    volumes: ["${DANGEROUS_SRC}:/host-etc:ro"]'
expect deny i1-var-bind
profile i1-driver '    volumes: ["probe:/probe"]
volumes:
  probe:
    driver_opts: {type: none, device: /etc, o: bind}'
expect deny i1-driver

# I2 — a Docker socket mount is a full host escape.
profile i2-socket '    volumes: ["/var/run/docker.sock:/var/run/docker.sock"]'
expect deny i2-socket

# I3 — no privileged, no added capabilities, no host namespaces.
profile i3-privileged '    privileged: true'
expect deny i3-privileged
profile i3-cap-add '    cap_add: [SYS_ADMIN]'
expect deny i3-cap-add
profile i3-pid '    pid: host'
expect deny i3-pid
profile i3-ipc '    ipc: host'
expect deny i3-ipc
# networks is reset because compose rejects network_mode beside it; the point is
# that the I3 check itself fires, not that compose refuses the file.
profile i3-network '    network_mode: host
    networks: !reset []'
expect deny i3-network

# I4 — no host credential or config directory.
profile i4-ssh "    volumes: [\"$HOME/.ssh:/root/.ssh:ro\"]"
expect deny i4-ssh

# Criterion 9 — canonical config may not resolve inside the project.
expect deny base env DEVBOX_PROFILES_DIR="$project"

printf '\n%s ok, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
