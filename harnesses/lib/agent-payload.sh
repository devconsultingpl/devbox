#!/bin/sh
# devbox agent payload — the agent's sources, as a reproducible build input.
#
# Sourced by bin/devbox (0004 D2/D3); everything here runs on the host, before a
# build. Each source checkout is copied into its own build context by the include
# rule git itself defines — tracked plus untracked files that are not ignored,
# working-tree content — so unreleased work ships and an ignored .env or
# node_modules cannot. The guard refuses a credential-shaped filename and a
# secret-shaped match alike, naming files and never values: an image layer is
# shared by every box using the profile, so a mistaken inclusion here outlives
# the run that made it. The stamp is per source: commit plus a digest of the
# materialised set, so a dirty, added or deleted file moves it and an ignored
# file never does.
#
# `dgit` comes from bin/devbox: an exported GIT_DIR would divert ls-files exactly
# as it would divert the paths that CLI mounts.

payload_materialize() { # payload_materialize <repo> <dest>
  payload_repo=$1
  payload_dest=$2
  mkdir -p "$payload_dest"
  find "$payload_dest" -mindepth 1 -delete
  list=$payload_dest.files
  dgit -C "$payload_repo" ls-files -z --cached --others --exclude-standard > "$list" || return 1
  tar -C "$payload_repo" --null -T "$list" -cf - | tar -C "$payload_dest" -xf -
  rm -f "$list"
}

payload_digest() { # payload_digest <dir> — digest of names and contents
  ( cd "$1" && find . \( -type f -o -type l \) -print0 | LC_ALL=C sort -z |
      xargs -0 shasum -a 256 | shasum -a 256 | cut -c1-64 )
}

payload_guard() { # payload_guard <dir> — 0 clean, 1 credential- or secret-shaped
  bad=$( cd "$1" && find . -type f \
           \( -name '.env' -o -name '.env.*' -o -name '.npmrc' -o -name '.netrc' \
              -o -name 'credentials.json' -o -name '*.pem' -o -name '*.key' \
              -o -name '*.p12' -o -name '*.pfx' -o -name '*.jks' -o -name '*.keystore' \
              -o -name '*.token' -o -name 'id_rsa*' -o -name 'id_dsa*' -o -name 'id_ecdsa*' \
              -o -name 'id_ed25519*' \) -print | head -5 )
  if [ -n "$bad" ]; then
    printf '%s\n' "$bad" | sed 's|^\./|credential-shaped: |'
    return 1
  fi
  if grep -rlE 'AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|ghp_[A-Za-z0-9]{36}' "$1" 2>/dev/null |
       sed "s|^$1/|secret-shaped: |" | head -5 | grep . ; then
    return 1
  fi
  return 0
}
