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
- **I5** — no credential that reaches cloud infrastructure is present in the box; the
  model credential is host-resident behind a loopback proxy, and the box holds only a
  single-purpose token the provider rejects (amendment).
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
credential (I5): authenticate in the session (`/login`) or give pi its own environment
for that run only, never bake a key into the image. The durable route for an unattended
box — a host-resident credential and a proxy, so the box never holds one — is
[Model credentials](#model-credentials-the-keychain) below.

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
switching rebuilds. Permissions are **allow-all with `yoloMode` on**
(`/root/.pi/agent/extensions/pi-permission-system/config.json`): a dialog in an unattended
run is a stall, and yolo mode now covers **every** ask source — rule-based asks, the wrapper
sentinels a bash command synthesizes (`find -exec`, `xargs`, `sh -c` →
`<indirection-bash-wrapper>`; `bash -c`/`eval` → `<opaque-bash-wrapper>`), an unparseable
command, `external_directory`, and subagent approval forwarding — while `deny` still
denies. Every auto-approval is written to
`logs/pi-permission-system-permission-review.jsonl` with its surface, command, matched
pattern and reason, so removing the dialog does not remove the record. slr ships its own
policy library (`enabled: true`, every surface `ask`); the image seeds it
`{"enabled": false}`. All thirteen `browser_*` tools are active from the first turn.

**Adding a tool** is a source change: a package goes into `settings.json` and a
setting beside it, both in `harnesses/pi.sh`, and the next `up` carries it.
**Adding a harness** (another agent) is one new `harnesses/<name>.sh` consuming
the same `/opt/devbox/payload`, selected by `HARNESS` in the profile;
`harnesses/none.sh` stays bare, so `base` carries no agent at all.

## Model credentials (the Keychain)

An agent needs a model credential, and it never enters the box: the agent there runs as
root with allow-all permissions, so anything inside the container — an environment
variable, a tmpfs file, a mount, an image layer — is readable by the very process it is
meant to be kept from. So the credential lives in the macOS **login Keychain**, and a
host-side proxy (plan `0002`) reads it once at start and gives the box a host-gateway
URL plus a throwaway token the provider rejects. That proxy is
`bin/devbox-model-proxy`: `devbox up` starts it, and no box authenticates with `/login`.

| Keychain item (`-s`) | Account (`-a`) | Provider |
|---|---|---|
| `devbox-openrouter` | `devbox` | OpenRouter |
| `devbox-deepseek` | `devbox` | DeepSeek |

### On a new machine

Run these **in your own terminal**, not through an agent session. `-w` comes last and
takes no value, which is what makes `security` prompt: the secret then lands in neither
shell history nor `ps` nor a transcript.

```console
$ security add-generic-password -s devbox-openrouter -a devbox -w
password data for new item:            # paste the key
retype password for new item:          # and again
$ security add-generic-password -s devbox-deepseek -a devbox -w

$ security find-generic-password -s devbox-openrouter -a devbox >/dev/null && echo present
present
```

The first read by the proxy raises *“security wants to access key `devbox-openrouter`”*
— click **Always Allow**, once per item. To pre-authorise instead (no prompt ever, and
no alert when something else reads it):

```console
$ security add-generic-password -U -T /usr/bin/security -s devbox-openrouter -a devbox -w
```

### Rotate, and remove

```console
$ security add-generic-password -U -s devbox-openrouter -a devbox -w   # replace in place
$ security delete-generic-password -s devbox-openrouter -a devbox      # remove
```

Rotate when a key has ever been typed as a command argument, written into a file or a
dotfile export, pasted into a session, or when a machine changes hands. **Rotate at the
provider first, then update the Keychain item** — updating first leaves a live stale key
behind. After rotating, the running proxy holds the old value until it restarts, so
`devbox down`/`up` (or a proxy restart) is part of the rotation.

### Never

- `… -w "<key>"`, or the legacy `-p "<key>"`: the value lands in shell history and
  briefly in `ps`. `-A` (“any application, no warning”) makes that mistake permanent.
- A `.env`, a dotfile export, a repo file, an image layer. `harnesses/lib/agent-payload.sh`
  refuses a credential-shaped filename at build time — a backstop, not the plan.
- Reading the item with `-w` “to check it”: that prints the key. `>/dev/null && echo
  present` is the check.
- A model key with no **spend cap**. Give each one a limit (OpenRouter per-key credit,
  DeepSeek balance) so a leak costs a bounded amount and rotation stays cheap.

The login Keychain is locked until you log in, so `up` must refuse to proceed without a
readable item rather than start a box that cannot think.

### The proxy and the box token

- `devbox up` starts `bin/devbox-model-proxy` on `127.0.0.1:8999` if it is not already
  listening, and mints one token per box under
  `~/.local/state/devbox/model-proxy/tokens/<compose project>`. One proxy serves every
  box; that file name is what attributes a request to a project.
- It binds loopback only. The box reaches it as `host.lima.internal:8999`, which colima
  forwards; nothing on the LAN can.
- The box's `/root/.pi/agent/models.json` points `openrouter` and `deepseek` at
  `http://host.lima.internal:8999/<provider>` with `apiKey: "$DEVBOX_MODEL_TOKEN"`. A
  provider-level `baseUrl`/`apiKey` keeps each built-in model catalog and changes only
  the endpoint and the credential.
- `devbox down` deletes that one token file, so the token dies with the box while the
  proxy and the Keychain item stand. `bin/devbox-model-proxy stop` stops the listener;
  `up` starts it again.
- **Proxy down** → the box fails as a transport error naming the gateway, never as a
  provider 401. `doctor` reports it rather than letting `up` imply a box that can think.
- Verify without printing anything: `bin/devbox-model-proxy verify <box>` prints `clean`
  per provider. It reads the Keychain in its own memory and pipes the key to `grep -f -`,
  so the value never reaches a shell argument or a transcript.
- A box's `models.json` and `docker inspect` show the **token**, never a provider key.
  `tests/credentials.test.sh` asserts exactly that, and that the provider itself answers
  `401` for the token.

> **Filed:** the rule behind this section is amendment 2026-11-16 of
> `docs/decisions/0001-sandbox-trust-posture.md`, and `AGENTS.md`'s I5 carries the restated
> form — no credential that reaches cloud infrastructure is present in the box; the model
> credential is host-resident behind a loopback proxy, and what the box holds is a
> single-purpose token the provider rejects.

## The walk-away loop

A brief in, a review-ready artifact out, nobody watching:

```console
$ devbox work sbcl ~/source/priv/myapp docs/plans/0007-thing.md   # up, then run it detached
$ devbox watch ~/source/priv/myapp                                # notify, then exit
# …walk away…
$ devbox attach sbcl ~/source/priv/myapp                          # look in whenever you like
```

`work` brings the box up, starts an interactive `pi` in a detached tmux session, waits for
its prompt and submits `/wf <workflow> <brief>` (`DEVBOX_WORKFLOW`, default `deliver`). No
keypress is needed after that: the box raises no permission dialog by design.

**The one artifact.** A run ends by writing exactly one of these at the project root:

| Artifact | Means | What you do |
|---|---|---|
| `READY-FOR-REVIEW.md` | every task reached `done`, the lenses are clean | review the diff, then commit on the host |
| `BLOCKED.md` | at least one task hit its round cap, or a lens found blockers | read the blocked task's last verdict — it names what could not be satisfied — fix the brief, then re-run |

Never both, never neither; `devbox watch` fires on either and stays silent for everything
else.

**Inspect and resume.** Every run leaves `.flow/workflows/runs/<run-id>.jsonl` plus a
session directory per stage under `runs/<run-id>/sessions/`, and the task lane keeps
`.flow/tasks/task-<n>.json` and `.flow/artifacts/verdicts/`. Re-enter a finished run with
`/wf @<run-id>` inside the box (`devbox attach` first): a run that stopped on a transient
failure resumes from the stage it reached, and a `BLOCKED.md` run resumes the tasks that are
not yet `done`.

**When a task cannot be satisfied**, `BLOCKED.md` is the correct outcome, not a bug: the
supervisor stops that task at its round cap and spends no other task's rounds. Fix the
criterion (or the code), then re-run; nothing retries forever.

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
| `docs/plans/completed/0002-*`, `backlog.md` | the supervisor `0002` (delivered) and the backlog behind it |
| `docs/decisions/` | the durable *why*: trust posture, payload-from-source-content |
