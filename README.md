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
$ devbox up --rebuild sbcl ~/source/priv/myapp   # force the build after editing this repo
$ devbox shell sbcl ~/source/priv/myapp   # shell into the box
$ devbox doctor sbcl ~/source/priv/myapp  # validate the effective config
$ devbox down sbcl ~/source/priv/myapp    # stop, remove, drop slr's volume
$ devbox down --purge sbcl ~/source/priv/myapp   # also drop service data

$ devbox policy review-only ~/source/priv/myapp   # no commits inside; propose instead
$ devbox policy --list
```

`<path>` is a repository root or a git worktree root. There is no `/workspace`:
the working directory is the tree's own host path.

Profiles live in `profiles/`:

| Profile | Toolchain | Agent |
|---|---|---|
| `base` | bare Ubuntu shell (git, zsh, rg, tmux, curl, wget, …) | none |
| `sbcl` | SBCL + slr | pi, the `@joozik/*` packages, skillset, browser |
| `go-postgres` | Go + a postgres 17 service | the same agent |

The toolchain layer is `images/<name>/Dockerfile`, built `FROM base`; the **agent
arrives with the harness**, not with the toolchain, which is why `base` is a bare
shell and the other two carry the full payload. A profile is a compose override
merged onto `compose/devbox.compose.yaml`, and its harness is chosen with
`ARG HARNESS` at the base layer.

**Adding a toolchain** (python, rust, another database) is two files: `images/<name>/Dockerfile`
with `FROM base`, and `profiles/<name>.yaml` with `HARNESS: pi` when the box should
also carry the agent. There is no toolchain-free agent profile yet: to work with
only the agent, use `sbcl` or add a profile whose Dockerfile is just `FROM base`.

A project with no repository gets one initialised; a path *inside* another
repository is refused rather than nested.

## Working in a box

`devbox shell <profile> <path>` drops you into the box. `pi` is on `PATH` there
with the skills, agents and browser tools already installed, and the box carries no
credential (I5) — authenticate once per box, in the session (`/login`) or by giving
pi its own environment, never by baking a key into the image:

```console
$ devbox up sbcl ~/source/priv/myapp      # shell needs a running box
$ devbox shell sbcl ~/source/priv/myapp
box$ pi                      # then /login, or: API key in pi's env for this run only
```

Nothing else is needed to *use* the box interactively: plan, implement, test and
review there exactly as on the host, answering the agent's questions in the TUI.
Everything a session writes — a plan, code, a commit — lands on the mounted worktree
at its own host path, so the host sees it immediately and `devbox down` cannot take
it with it. `devbox policy review-only <path>` is the "propose, do not commit"
variant.

Two things to know before you rely on it. A session sees the payload **as built**:
edits to your `pi-extensions`/`skillset` checkouts reach the box at the next `up`
(which rebuilds itself when their content changed), never mid-session. And the box
is deliberately smaller than a workstation — no Docker socket (I2), and no Python,
`jq`, `make` or C compiler unless a profile adds them — which is why *this* repo's
test suite runs on the host rather than inside a box.

## The agent payload

A profile whose harness is an agent (`sbcl`, `go-postgres`) builds that agent from
**your checkouts**, never from whatever npm published: `PIEXT_REPO` (default
`~/source/priv/pi-extensions`) and `SKILLSET_REPO` (default
`~/source/priv/skillset`). `up` copies each into a build context under
`$XDG_STATE_HOME/devbox/contexts/<name>.<digest>/` (the state directory defaults to
`~/.local/state`) by git's own include rule —
`git ls-files --cached --others --exclude-standard`, working-tree content — so
unreleased and uncommitted work ships while `node_modules`, `.env` and anything
else git ignores never enters the image. A credential-shaped filename (`.env*`,
`*.npmrc`, `*.pem`, `*.key`, `*.p12`, `id_rsa*`, …) refuses the build outright, and
so does a file whose *content* looks like a secret (an AWS key, a private-key
block, a GitHub token) — reported by filename, never by value, because the image
layer is shared by every box built from the profile.

The result is identified by a **stamp**: per source, its commit plus a digest of
the materialised file set, plus the two build inputs the sources do not describe
— the harness and the browser mode — so `DEVBOX_BROWSER=full` rebuilds instead of
reusing a headless image. `up` builds when the image's stamp
(`devbox.agent.stamp`) differs from the current one and reuses the image
otherwise, so a dirty edit, a new untracked file and a deletion each rebuild,
while an ignored file never does. `devbox doctor` prints the stamp it would
build, and the image keeps a `/opt/devbox/agent/SOURCES` record beside the label.
This repo's own
Dockerfiles and harness scripts are outside the stamp: edit one and use
`devbox up --rebuild`.

Inside the box the payload lands under `/opt/devbox/agent/`: eleven `@joozik/*`
workspace packages as local paths — flow, flow-workflow and flow's six sibling
extensions, plus pi-subagents, pi-playwright and pi-permission-system (pi loads
their TypeScript sources; nothing is fetched from a registry) — skillset's skills,
agents and prompts installed by `skillset sync`, and Playwright's headless
chromium shell pinned at `/opt/devbox/browser/headless_shell` and exported as
`PI_PLAYWRIGHT_EXECUTABLE` in the container's environment. `DEVBOX_BROWSER=full`
adds full chromium for headed work (+~0.6 GB); it is part of the stamp, so
switching rebuilds. Permissions are explicit
allow-all (`/root/.pi/agent/extensions/pi-permission-system/config.json`) and the
thirteen `browser_*` tools are active from the first turn: an unattended session
cannot answer a prompt, so the container boundary — not a dialog — is what
isolates it.

**Adding a tool** is a source change: a package goes into `settings.json` and a
setting beside it, both in `harnesses/pi.sh`, and the next `up` carries it.
**Adding a harness** (another agent) is one new `harnesses/<name>.sh` consuming
the same `/opt/devbox/payload`, selected by `HARNESS` in the profile;
`harnesses/none.sh` stays bare, so `base` carries no agent at all.

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

**Unattended runs.** There is no supervisor yet: a box is interactive. Planning a
change, building it, verifying it and reviewing it inside a box all work today, with
you answering the agent's questions; plan-in, result-out without you is plan
`0002`, not a shipped capability.

## Host prerequisites

Docker on colima, plus the `compose` and `buildx` CLI plugins — devbox points
`DOCKER_CONFIG` at a devbox-managed directory linking the Homebrew plugins, because
the Apple-Silicon CLI does not search that path — `jq` for `doctor`, `git` (≥ 2.31)
at the project (a repository is initialised when missing), the worktree's repository
on the same filesystem, and the two agent sources (see
[The agent payload](#the-agent-payload); `PIEXT_REPO` and `SKILLSET_REPO` override
their locations). The `sbcl` profile also needs slr's source tree as a
build context, since that repo is private and this one is public:

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
| `harnesses/lib/agent-payload.sh` | materialising, guarding and stamping the agent's sources |
| `images/payload-empty/` | the empty context a `none` build receives instead of them |
| `tests/doctor.test.sh` | invariant tests, one per I1–I4 |
| `tests/worktree.test.sh` | the worktree boundary end to end |
| `tests/agent-image.test.sh` | the agent layer inside a real box |
| `docs/plans/completed/` | the delivered specifications: `0001` runtime, `0003` worktrees, `0004` agent workstation |
| `docs/plans/0002-*`, `backlog.md` | not delivered: the supervisor `0002`, and the backlog behind it |
| `docs/decisions/` | the durable *why*: trust posture, payload-from-source-content |
