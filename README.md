# devbox

A disposable development environment on macOS, scoped to exactly **one** project
directory and started from a canonical config the agent cannot write.

`devbox up <profile> <project>` starts a container whose only host mount is that
project. Inside it an agentic harness (`pi`) has full permissions, a toolchain,
and nothing else: no host shell config, no credentials, no sibling projects, no
Docker socket. `devbox down` throws it away.

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

- **I1** — the only host path mounted into a container is the project directory.
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
```

Profiles live in `profiles/`: `base` (bare container), `sbcl` (SBCL + slr, harness
`pi`), `go-postgres` (Go plus a postgres service). A profile is a compose override
merged onto `compose/devbox.compose.yaml`; its toolchain layer comes from
`images/<name>/Dockerfile`, and its harness is chosen with `ARG HARNESS` at the base
layer. A project with no repository gets one initialised; a path *inside* another
repository is refused rather than nested.

## `devbox doctor`

`doctor` resolves the effective config through compose and refuses any that breaks
the invariants above: a bind mount outside the project, a Docker socket,
`privileged`, added capabilities, host namespaces, a top-level volume that is really
a host path, or a `.git/hooks` mount that is not read-only. Docker-managed
`type=volume` mounts are storage rather than host paths, so they pass. It exits
non-zero naming every violation; `tests/doctor.test.sh` runs one violating config
per invariant alongside the clean profiles.

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
the Apple-Silicon CLI does not search that path — `jq` for `doctor`, and `git` at
the project (a repository is initialised when missing). The `sbcl` profile also
needs slr's source tree as a build context, since that repo is private and this one
is public:

```console
$ git -C <slr checkout> archive HEAD | tar -x -C ~/.cache/devbox/slr-src
```

## Layout

| Path | What it is |
|---|---|
| `bin/devbox` | the CLI: `up`, `shell`, `down`, `doctor` |
| `compose/devbox.compose.yaml` | the canonical compose skeleton |
| `profiles/*.yaml` | per-profile overrides: toolchain, harness, services |
| `images/*/Dockerfile` | toolchain layers (`base` → `sbcl`, `go`, …) |
| `harnesses/*.sh` | the harness seam: exactly one applied per image |
| `tests/doctor.test.sh` | invariant tests, one per I1–I4 |
| `docs/plans/0001-*` | the specification this repo is built to |
| `docs/decisions/` | the durable *why* behind the posture |
