# devbox

A disposable development environment on macOS, scoped to exactly **one**
repository checkout or worktree — that tree and its gitdir, nothing else — and
started from a canonical config the agent cannot write.

`devbox up <profile> <path>` starts a container whose only host paths are that
tree, its gitdir and the gitdir's hooks (read-only). Inside it an agentic harness
(`pi`) has full permissions, a toolchain, and nothing else: no host shell config,
no credentials, no sibling projects, no Docker socket. `devbox down` throws it
away.

## Why it exists

Two incidents on this machine: an agent deleted a production AWS stack, and an
agent damaged host global state badly enough that the environment had to be
rebuilt. Both were supposedly gated by a permission extension that prompted on bash
patterns — and both happened anyway. devbox makes those failure modes structurally
absent instead of prompt-gated; the reasoning is in
[`docs/decisions/0001-sandbox-trust-posture.md`](docs/decisions/0001-sandbox-trust-posture.md).

## Invariants

Violating any of these re-opens an incident class, so they are checked rather than
remembered.

- **I1** — the only host paths mounted into a container are the worktree, its
  gitdir and the gitdir's hooks (read-only), each at its own absolute host path
  (`docs/decisions/0001-sandbox-trust-posture.md`, amendment).
- **I2** — never `/var/run/docker.sock`: a socket mount is a full host escape.
- **I3** — no `privileged`, `cap_add`, `devices`, `pid`/`ipc`/`network_mode: host`.
- **I4** — never `~/.aws`, `~/.ssh`, `~/.config/gh`, `~/.docker`, `~/.npmrc`,
  `~/.pi`.
- **I5** — no cloud-reachable credential in this runtime (no egress layer yet).
- **I6** — every host-trusted config resolves from this repo, never from a mounted
  workspace.

## Usage

```console
$ devbox up sbcl ~/source/priv/myapp      # build if needed, start detached
$ devbox shell sbcl ~/source/priv/myapp   # shell into the box
$ devbox doctor sbcl ~/source/priv/myapp  # validate the effective config
$ devbox down sbcl ~/source/priv/myapp    # stop, remove, drop slr's volume
$ devbox down --purge sbcl ~/source/priv/myapp   # also drop service data

$ devbox policy review-only ~/source/priv/myapp   # no commits inside; propose instead
$ devbox policy --list
```

`<path>` is a repository root or a git worktree root. There is no `/workspace`:
the working directory is the tree's own host path.

Profiles live in `profiles/`: `base` (bare container), `sbcl` (SBCL + slr, harness
`pi`), `go-postgres` (Go plus a postgres service). A profile is a compose override
merged onto `compose/devbox.compose.yaml`; its toolchain layer comes from
`images/<name>/Dockerfile`, and its harness is chosen with `ARG HARNESS` at the base
layer. A project with no repository gets one initialised; a path *inside* another
repository is refused rather than nested.

## `devbox doctor`

`doctor` resolves the effective config through compose and refuses any that breaks
the invariants above: a bind mount outside the worktree/gitdir allow-list, a
hooks mount that is writable or missing, a Docker socket, `privileged`, added
capabilities, host namespaces, a top-level volume that is really a host path, or
canonical config that resolves inside the worktree. It also refuses a repository
carrying a git extension the image's git cannot read, before anything starts.
Docker-managed `type=volume` mounts are storage rather than host paths, so they
pass. It exits non-zero naming every violation; `tests/doctor.test.sh` runs one
violating config per invariant alongside the clean profiles.

## Worktrees

```console
$ git -C ~/source/priv/myapp worktree add .devbox/wt/feat-a -b feat-a
$ devbox up sbcl ~/source/priv/myapp/.devbox/wt/feat-a
$ devbox up base ~/source/priv/myapp/.devbox/wt/feat-b   # same repo, at the same time
```

Each worktree gets its own container, compose project and slr volume, so several
features proceed in parallel on one repository. A worktree's `.git` is a file
whose pointer, and the gitdir's backlink, are absolute host paths — so the box
mounts the worktree *and* the repository's gitdir at those same host paths and no
metadata is rewritten. `up` appends `.devbox/` to the gitdir's `info/exclude` when the tree
hosts the worktree home, so it never appears as untracked; other repositories are
left untouched.

Two limits. A subdirectory of a worktree is refused (point devbox at the worktree
root), and a repository carrying a git extension the image's git does not
understand — for example one created with `git worktree add --relative-paths` on
git ≥ 2.48 — is refused by `up` and `doctor` rather than half-started.

## Commit policy

`devbox policy review-only <path>` mounts the container's gitdir read-only: the
agent reads history and runs `git status`, but cannot stage or commit, and writes
`COMMIT_PROPOSAL.md` at the worktree root instead. You review it in the host
checkout and commit there. `devbox policy commits-allowed <path>` restores
committing; `devbox policy --list` shows every recorded path. The state is
machine-local under `~/.local/state/devbox/policy/`, keyed by absolute path, and
is never read from the workspace — a project cannot rewrite its own restriction.

## What this runtime does not do

**Remote effects (T3).** The AWS incident was not a filesystem problem, so no amount
of mount discipline addresses it. The control here is *credential absence*: this
runtime is for local work — toolchains, services, local databases — until an egress
allowlist exists (the Gondolin entry in `docs/plans/backlog.md`). A project that
genuinely needs cloud access needs a scoped identity plus that egress layer, not a
smarter prompt.

## Host prerequisites

Docker on colima, plus the `compose` and `buildx` CLI plugins — devbox points
`DOCKER_CONFIG` at a devbox-managed directory linking the Homebrew plugins, because
the Apple-Silicon CLI does not search that path — `jq` for `doctor`, `git` (≥ 2.31)
at the project (a repository is initialised when missing), and the worktree's
repository on the same filesystem. The `sbcl` profile also needs slr's source tree
as a build context, since that repo is private and this one is public:

```console
$ git -C <slr checkout> archive HEAD | tar -x -C ~/.cache/devbox/slr-src
```

## Layout

| Path | What it is |
|---|---|
| `bin/devbox` | the CLI: `up`, `shell`, `down`, `doctor`, `policy` |
| `compose/devbox.compose.yaml` | the canonical compose skeleton |
| `profiles/*.yaml` | per-profile overrides: toolchain, harness, services |
| `images/*/Dockerfile` | toolchain layers (`base` → `sbcl`, `go`, …) |
| `harnesses/*.sh` | the harness seam: exactly one applied per image |
| `tests/doctor.test.sh` | invariant tests, one per I1–I4 |
| `tests/worktree.test.sh` | the worktree boundary end to end |
| `docs/plans/completed/0001-*` | the specification this repo is built to |
| `docs/decisions/` | the durable *why* behind the posture |
