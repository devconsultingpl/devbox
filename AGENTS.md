# devbox — agent orientation

Container runtime on macOS: a disposable dev environment scoped to **one** project
directory, from a canonical config the agent cannot write. Enabling condition for a
separate orchestrator; not the product.

**Spec — binding, its acceptance criteria and file/line budget are what review
checks against:** `docs/plans/0001-devbox-runtime.md`. Context only, do not start:
`docs/plans/0002-devbox-orchestrator.md`, `docs/plans/backlog.md`.

## Why it exists (both incidents happened on this machine)

- An agent modified host **global** state — shell config, app config, Homebrew
  prefix — and the environment had to be rebuilt.
- An agent deleted a **production AWS stack**.

Both are made structurally impossible, not prompt-gated.

## Invariants — violating one re-opens an incident class

- **I1** The only host path mounted into a container is the project directory.
- **I2** Never mount `/var/run/docker.sock` — full host escape.
- **I3** No `privileged`, `cap_add`, `devices`, `pid/ipc/network_mode: host`.
- **I4** Never mount or export `~/.aws`, `~/.ssh`, `~/.config/gh`, `~/.docker`,
  `~/.npmrc`, `~/.pi`.
- **I5** No cloud-reachable credential in this runtime (no egress layer yet).
- **I6** Every host-trusted config resolves from this repo, never from a mounted
  workspace.

If a step seems to need an exception, **stop and ask** — never "temporarily to test".

## Gate discipline

Not done until the relevant criteria are verified **by running them**; never claim
`DONE`/passing/green before the command passed. Budget and file list are binding —
exceeding either needs approval first, and the plan is amended rather than silently
deviated. Do not edit architecture or conventions docs.

## Host hygiene

Never write to host-sensitive paths (`~/.zshrc`, `~/.config`, `~/.pi`,
`/opt/homebrew`); read-only checksums are permitted. Scratch projects live under
`$HOME` — colima shares only `~` and `/tmp/colima`, so `/tmp` and `/Volumes` binds
fail.

## Verified in slice 1 (2026-09-24) — do not re-derive

- colima 0.10.3 / lima 2.2.0; Docker server 28.4.0; socket
  `~/.colima/default/docker.sock`. The host's `$DOCKER_HOST` points at the legacy
  path — `bin/devbox` must resolve the socket, not inherit the ambient value.
- No host path is visible outside a container's own mounts; a nested readonly
  `.git/hooks` mount yields EROFS on write.
- `slr` runs in-container (apt `sbcl` + `./install.sh --prefix=/usr/local`), its
  `.slr/` on the mount. virtiofs: long listing of `.slr/` errors `EINVAL` on the
  socket node; the host cannot connect to the container's listener; host-side and
  container `slr` on one project interfere via the shared `.slr/` markers.
