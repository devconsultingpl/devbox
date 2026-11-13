# devbox — agent orientation

Container runtime on macOS: a disposable dev environment scoped to **one** project
directory, from a canonical config the agent cannot write. Enabling condition for a
separate orchestrator; not the product.

**Spec:** `docs/plans/completed/0001-devbox-runtime.md` (delivered, signed off 2026-09-26;
its Review log holds three rounds) — binding, and what review checks against. Context only,
do not start: `docs/plans/0002-devbox-orchestrator.md`, `docs/plans/backlog.md`.

## Why it exists

Two incidents on this machine: an agent modified host **global** state badly enough that the
environment had to be rebuilt, and an agent deleted a **production AWS stack**. Both are made
structurally impossible here, not prompt-gated — see `docs/decisions/0001-sandbox-trust-posture.md`.

## Invariants — violating one re-opens an incident class

- **I1** The only host paths mounted into a container are the worktree, its gitdir and the
  gitdir's hooks (read-only), each mounted at its own absolute host path — never a
  `/workspace` alias.
- **I2** Never mount `/var/run/docker.sock` — full host escape.
- **I3** No `privileged`, `cap_add`, `devices`, `pid/ipc/network_mode: host`.
- **I4** Never mount or export `~/.aws`, `~/.ssh`, `~/.config/gh`, `~/.docker`,
  `~/.npmrc`, `~/.pi`.
- **I5** No cloud-reachable credential in this runtime (no egress layer yet).
- **I6** Every host-trusted config resolves from this repo, never from a mounted
  workspace.

If a step seems to need an exception, **stop and ask** — never "temporarily to test".

## Working discipline

- **Gate:** not done until the criterion is verified **by running it**; never claim
  `DONE`/passing/green before the command passed.
- **Budget:** the file list and each file's line budget are binding — write to the budget
  and `wc -l` right after the file, trim comments before content, and amend the row rather
  than growing silently. Exceeding either needs approval first.
- **Records:** live text follows a rename or move (`grep -rn` the old name in the same
  commit) while amendments keep their original wording as history. A "verified" claim
  names the states tested — running/stopped/removed, clean/dirty — not just the happy path.
- **Verification:** serialize commands that mutate or count the same containers, volumes or
  images; a surprising count is measurement interference until proven otherwise. Feed SQL and
  heredocs over stdin (`printf … | docker exec -i … psql -f -`), never nested `sh -c` quoting
  — empty output ⇒ suspect the harness before the code.
- **Docs:** do not edit architecture or conventions docs — propose the change instead.

## Host hygiene

Never write to host-sensitive paths (`~/.zshrc`, `~/.config`, `~/.pi`, `/opt/homebrew`);
read-only checksums are permitted. Scratch projects live under `$HOME` — colima shares
only `~` and `/tmp/colima`, so `/tmp` and `/Volumes` binds fail. Never aim a write
redirection at a shared host path; if one could have been written, verify it wasn't.
`rm -rf *` is denied by the host permission system — clean up with `find … -delete`.

## Environment facts (verified) — do not re-derive

- colima 0.10.3 / lima 2.2.0; Docker server 28.4.0; socket `~/.colima/default/docker.sock`;
  `$DOCKER_HOST` points at the legacy path, so `bin/devbox` resolves the socket itself.
- No host path is visible outside a container's own mounts; a nested read-only `.git/hooks`
  mount yields EROFS on write.
- Docker CLI plugins are **not** on the CLI's search path (buildx/compose live in
  `/opt/homebrew/lib/docker/cli-plugins`; `bin/devbox` links them via `DOCKER_CONFIG`).
  Without buildx, `docker build` silently uses the legacy builder, which parses heredocs and
  writes **empty** files — an empty in-image file means the wrong builder, not a wrong
  Dockerfile.
- `slr`'s source is private while this repo is public, so `images/sbcl` takes it as a build
  context from `~/.cache/devbox/slr-src` (export line in `profiles/sbcl.yaml`).
- `slr` runs in-container (apt `sbcl` + `./install.sh --prefix=/usr/local`); virtiofs makes
  listing `.slr/` error `EINVAL` on the socket node, the host cannot reach the container's
  listener, and host-side and container `slr` on one project interfere via the shared
  `.slr/` markers. `.slr/` is a volume under the worktree's own path, named per worktree.
- A worktree's `.git` is a file naming an absolute gitdir, and `<gitdir>/gitdir` points
  back absolutely; mounting only the worktree gives `fatal: not a git repository`. The
  box therefore mounts the worktree and the repository's gitdir at those same host paths.
- Container git is 2.43 while the host may be 2.56: a repo carrying
  `extensions.relativeworktrees` (written by `git worktree add --relative-paths`) is
  unreadable in-box, so `up` and `doctor` refuse such a repository up front. `up` also
  appends `.devbox/` to `<gitdir>/info/exclude`, keeping the worktree home out of status.
