# devbox — agent orientation

Container runtime on macOS: a disposable dev environment scoped to **one** project
directory, from a canonical config the agent cannot write. Enabling condition for a
separate orchestrator; not the product.

**Spec:** `docs/plans/completed/0001-devbox-runtime.md` (delivered, signed off 2026-09-26;
its Review log holds three rounds) — binding, and what review checks against. Context
only, do not start: `docs/plans/0002-devbox-orchestrator.md`, `docs/plans/backlog.md`.

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

Not done until the criteria are verified **by running them**; never claim
`DONE`/passing/green before the command passed. Budget and file list are binding:
exceeding either needs approval, and the plan is amended rather than silently deviated —
write to the per-file budget and `wc -l` right after each file, trimming comments before
content. After a rename or move, `grep -rn` the old name in the same commit: live text
follows the change, amendments keep their wording as history. Do not edit architecture or
conventions docs.

## Host hygiene

Never write to host-sensitive paths (`~/.zshrc`, `~/.config`, `~/.pi`, `/opt/homebrew`);
read-only checksums are permitted. Scratch projects live under `$HOME` — colima shares
only `~` and `/tmp/colima`, so `/tmp` and `/Volumes` binds fail. Never aim a write
redirection at a shared host path; if one could have been written, verify it wasn't.
`rm -rf *` is denied by the host permission system — clean up with `find … -delete`.

## Environment facts (verified) — do not re-derive

- colima 0.10.3 / lima 2.2.0; Docker server 28.4.0; socket
  `~/.colima/default/docker.sock`. The host's `$DOCKER_HOST` points at the legacy
  path — `bin/devbox` must resolve the socket, not inherit the ambient value.
- No host path is visible outside a container's own mounts; a nested readonly
  `.git/hooks` mount yields EROFS on write.
- `slr` runs in-container (apt `sbcl` + `./install.sh --prefix=/usr/local`), its
  `.slr/` on the mount. virtiofs: long listing of `.slr/` errors `EINVAL` on the
  socket node; the host cannot connect to the container's listener; host-side and
  container `slr` on one project interfere via the shared `.slr/` markers.
- Docker CLI plugins are **not** on the CLI's search path: buildx and compose live in
  `/opt/homebrew/lib/docker/cli-plugins`, and `bin/devbox` injects a `DOCKER_CONFIG`
  that links them. Without buildx `docker build` silently falls back to the legacy
  builder, which *parses heredocs and writes empty files* — an empty in-image file means
  the wrong builder, not a wrong Dockerfile.
- `slr`'s source is private while this repo is public, so `images/sbcl` takes it as a
  build context from `~/.cache/devbox/slr-src`; `profiles/sbcl.yaml` carries the export
  line (`git -C <slr checkout> archive HEAD | tar -x -C …`).

## Verification discipline

Serialize commands that mutate or count the same containers, volumes or images — a
surprising count is measurement interference until proven otherwise. Feed SQL and
heredocs over stdin (`printf … | docker exec -i … psql -f -`), not through nested
`sh -c` quoting, which swallows arguments; empty output ⇒ suspect the harness before the
code. A "verified" claim covers only the states tested — name them, or state the scope.
