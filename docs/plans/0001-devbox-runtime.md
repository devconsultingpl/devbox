# 0001 — `devbox` runtime: isolated per-project development environments

## Status: proposed — slice 1 signed off (2026-09-24), slice 2 authorized

Slice-1 sign-off accepts the boundary and slr findings (D9, D10, criterion 5, the
answered socket question); it is **not** plan completion. This plan stays in
`docs/plans/` and only moves to `docs/plans/completed/` once the work is
implemented and reviewed clean.

**Amendment A1 (2026-09-24, developer-requested):** added acceptance criterion 11
and decision D9 — the container's shell config is inlined in `images/base` and no
host shell config is ever mounted or copied. Budget rows for
`images/base/Dockerfile` (40 → 55) and this file updated accordingly. No other
scope change.

**Amendment A2 (2026-09-24, developer decision after slice-1 findings):** decision
D10 — `slr`'s `.slr/` is a container-private `type=volume` mount, never the host's
directory. Criterion 5 clarified ("as seen inside the container") and criterion 2
extended so `doctor` distinguishes Docker volumes from host binds. Slice-1 socket
open question answered. Budget rows for `profiles/lisp.yaml`, `compose/`,
`bin/devbox`, and `tests/doctor.test.sh` updated.

**Amendment A3 (2026-09-25, slice-2 findings — image build mechanics).** No change
to any criterion, no change to the file list or to the five slice-2 rows; only this
file's own row is updated (360 → 409).

1. **Chaining images needs a named build context.** Compose/bake builds services
   in parallel, so a leaf's `FROM devbox/base:<tag>` races the base build
   (`pull access denied` on a clean machine). Leaves now take their base as the
   named context `base` (`FROM base`); compose supplies
   `additional_contexts: {base: service:base}` — which is also what expresses the
   build dependency — and a standalone build passes
   `--build-context base=docker-image://devbox/base:local`. D3's mechanism
   (ARG HARNESS + one compose invocation) is unchanged and verified: from zero
   images, one `docker compose build` produced base, lisp and go in 1m19s with the
   harness applied exactly once in each.
2. **BuildKit is required, and this host's Docker CLI does not find its
   plugins.** Without them `docker build` silently uses the legacy builder, whose
   heredoc bodies are written empty — an image with no shell config. The shell
   config is therefore written as `COPY <<'ZSHRC'` heredocs, which *fail* on the
   legacy builder (verified) and satisfy criterion 11 unchanged. Buildx 0.37.1 and
   compose 5.5.1 are already installed at
   `/opt/homebrew/lib/docker/cli-plugins`, but the Apple-Silicon CLI does not
   search that path; exposing them through a `DOCKER_CONFIG` whose `cli-plugins/`
   symlinks them works (verified). **How devbox always gets them is a slice-3
   decision** — devbox-managed `DOCKER_CONFIG` in `bin/devbox`, or a one-time
   `~/.docker/cli-plugins` symlink the developer runs (a host-global write, so
   theirs to make).
3. **slr source input** (answers the "SBCL/slr installation shape inside the
   image" open question). `devconsultingpl/smart-lisp-repl` is private and this
   repo is public, so the source is neither vendored here nor fetched with a
   credential (I4, I5). It arrives as the named build context `slr`, produced from
   the developer's checkout with `git -C <slr> archive HEAD | tar -x -C "$SLR_SRC"`;
   `install.sh --prefix=/usr/local` then rebuilds `slr.core` against the image's
   own SBCL (43 MB, SBCL 2.2.9.debian). Reversible to a one-line `git clone` if
   slr is ever published — it is MIT and the developer owns it.
4. **D10 nuance.** Mounting the volume at `<project>/.slr` makes dockerd create
   that directory in the host project on first run; it stays empty — marker,
   socket, PID and logs all live on the volume (verified on `/dev/vdb1`, ext4).
   "Leaves no artifact in the host project directory" therefore means no *file*.

**Recorded, not started (developer input, 2026-09-25).** The runtime must stay
flexible across many tools and services (postgres, kafka, redis, wordpress, …), and
an environment an agent installs and configures *after* the container starts should
be capturable for reuse. Consequences, none of them slice-2 scope: slice 4's service
pattern generalizes to a per-profile list of pinned upstream images — service
images never derive from `images/base` and so never carry a harness; the capture
path needs its own plan, because turning a configured container into a reusable
*reviewable recipe* (rather than an opaque `docker commit`) is an I6 question;
and further CL implementations (ECL, CCL, Carp) plus other languages become sibling
toolchain layers next to `images/sbcl`.

**Amendment A4 (2026-09-25, developer decision):** the Common Lisp toolchain layer
is named after its implementation — `images/sbcl` (formerly `images/lisp`), with
`images/ecl`, `images/clasp`, `images/ccl`, `images/abcl`, `images/carp`, … to
follow as their own layers. Live plan text updated to match: criteria 2 and 5 say
`sbcl` profile, budget rows now read `images/sbcl/Dockerfile` (35) and
`profiles/sbcl.yaml` (27), D2 and the slice-2 summary name `images/sbcl`. No
substance changed — same file, same 24 lines, same criteria. One useful
consequence: `slr` is SBCL-only, so the private-source build context (`slr`, A3.3)
is needed by exactly one layer. A1–A3 keep their original wording as history.

**Amendment A5 (2026-09-25, slice-2 implementation detail not fixed by D3):** the
harness slot lives in `images/base` — it declares `ARG HARNESS`, copies
`harnesses/<name>.sh` and runs it once, which is what makes the seam "adding one
file" (D3) and means the toolchain layers carry neither the slot nor any agent
name. D2 still holds as written: no image names an agent. Verified — one harness
file and one `pi` binary in each of the three images, zero harness or agent names
under `images/`. A service image never derives from `images/base`, so it can never
inherit a harness (relevant to the service flexibility noted above).

**Amendment A6 (2026-09-25, developer decision — recorded for a future plan, not
scope here).** When an agent configures something inside a running container and it
should be reusable, the saved artifact is a **reviewed recipe**, not a snapshot:
`devbox save <name>` proposes an `images/<name>/Dockerfile` (or a profile/service
fragment) built from a thin install-recorder plus `docker diff`, prints it for the
developer, and writes it into this repo only on confirmation. Rejected: an opaque
`docker commit` (the host would later run content nobody read — the T4/I6 shape —
with no rebase path onto a new base), a persistent environment volume (invisible
drift), and no capture at all (every ad-hoc setup stays throwaway). Consequence:
tiers stay one mechanism — a layer or a profile entry — so ad-hoc work converges
into the canonical form, and service images remain pinned upstream images that
never derive from `images/base` (A5). Belongs in a new plan (0003), with slice 4's
postgres service as its first increment.

**Amendment A7 (2026-09-26, slice-3 decisions the plan left open).**

1. **A profile is a compose override.** `compose/devbox.compose.yaml` is the canonical
   skeleton; `profiles/<name>.yaml` merges on top of it
   (`docker compose -f … -f profiles/<p>.yaml`, plus `--profile build`) and supplies the
   toolchain layer, the harness and any services. No shell YAML parsing exists
   anywhere, and `doctor` inspects the *effective* config. The base→leaf chain is a
   `devbox-base` service (`profiles: ["build"]`, tagged `devbox/base-<profile>:local`)
   that leaf layers consume as `additional_contexts: {base: service:devbox-base}`
   (A3.1): always built, never started.
2. **`doctor` needs `jq`** — a host prerequisite, present here (1.8.2). It checks the
   resolved JSON for a bind allowlist (the project, plus a read-only `.git/hooks`, D4),
   any other mount type, top-level volumes carrying a `driver_opts.device`,
   `privileged`, `cap_add`, `devices`, and `network_mode`/`pid`/`ipc: host`.
   `type=volume` stays clean (criterion 2, D10), which the clean `sbcl` profile
   demonstrates in the suite.
3. **Seams for tests and overrides:** `DEVBOX_PROFILES_DIR`, `DEVBOX_COMPOSE_FILE`,
   `DEVBOX_DOCKER_HOST`, `DEVBOX_DOCKER_CONFIG`. Canonical config that resolves inside
   the project is refused (criterion 9's guard), and that refusal is tested too.
4. **`up` requires a git project**, because D4's `.git/hooks` mount has to exist.
   **`down` drops volumes** (`-v`) — that is what removes the anonymous `.slr` volume
   (D10), and it will drop slice 4's postgres data as well: destructive by design.
5. Budget: no row changed except this file's own; the five slice-3 rows land under
   their estimates (140/61/11/24/22/85 against 185/62/25/27/25/95).

## Goal

A container runtime on macOS that hands an agentic harness a disposable
development environment scoped to exactly **one** project directory, with a
toolchain composition chosen per project, started from a **canonical config that
the agent cannot write**.

The runtime is the enabling condition for plan `0002` (the orchestrator). It is
not the product.

```console
$ cd ~/source/priv/myapp
$ devbox up go-postgres .          # canonical profile from the devbox repo
$ devbox doctor go-postgres .      # validate the effective config before trusting it
```

## Threat model

Three axes. Two of them correspond to incidents that already happened on this
machine, so they are requirements, not hypotheticals.

| # | Threat | Incident | Control | Enforced by |
|---|---|---|---|---|
| T1 | Agent modifies host **global** state (`~/.zshrc`, `~/.config`, `~/.pi`, `/usr/local`, Homebrew prefix, npm globals) | **happened** — environment had to be rebuilt | Container filesystem is a *different* filesystem; global paths do not exist inside it | Mount discipline (invariants I1–I4) |
| T2 | Agent damages **local project** files | acceptable by explicit decision | Read-write project mount; `.git/hooks` read-only | Nested read-only bind mount |
| T3 | Agent damages **remote** infrastructure (AWS prod) | **happened** — prod stack deleted | **Credential absence** (Docker runtime); egress allowlist (deferred, Gondolin) | `devbox doctor` + invariant I5 |
| T4 | Agent writes a **host-trusted file** the host later executes/obeys — `.git/hooks`, a compose file | latent (same class as T1) | read-only hooks mount; canonical config lives outside any mounted workspace | I6 |

T1 and T3 are the two that hurt. Note what each is **not**: T3 is not a
filesystem problem, so no amount of mount isolation addresses it. T1 is not a
network problem. They need separate controls, and T3's control is *absence of a
capability*, not a restriction on one.

**T1 is the runtime's strongest property and the reason it is worth building.**
`~` inside the container is not your `~`; `~/.zshrc` is not a readable file, let
alone a writable one. The agent cannot damage global state because that state is
not present, not because it was asked nicely.

### Invariants

Violating any one of these re-opens T1 or T4, so they are stated as invariants
and checked automatically rather than remembered:

- **I1** — the only host path mounted into the container is the project directory.
- **I2** — no `/var/run/docker.sock` mount. A socket mount is a full host escape.
- **I3** — no `privileged`, `cap_add`, `devices`, `pid: host`, `ipc: host`,
  `network_mode: host`.
- **I4** — no host credential or config directory: `~/.aws`, `~/.ssh`,
  `~/.config/gh`, `~/.docker`, `~/.npmrc`, `~/.pi`.
- **I5** — no cloud-reachable credential in the Docker runtime until the egress
  layer exists (see D6).
- **I6** — every host-trusted config file resolves from the `devbox` repo, never
  from a mounted workspace.

## Acceptance criteria

Binary, each answerable yes/no from the diff or from a named command.

1. `devbox up <profile> <project>` starts a container whose only host mount is
   `<project>` (read-write) plus `<project>/.git/hooks` (read-only).
2. `devbox doctor <profile> <project>` exits non-zero when the **effective**
   `docker compose config` violates any of I1–I4, and exits 0 on a clean profile.
   Docker-managed storage is not a host path: a `type=volume` mount (the `sbcl`
   profile's `.slr/`, D10) must **not** be reported as an I1 violation, while a
   host bind outside the project still must be.
3. From inside the container, no host path outside the project is readable —
   `ls` of a known sibling/parent/global path returns nothing.
4. Host global state is untouched: checksums of `~/.zshrc`, `~/.config`, `~/.pi`,
   and the Homebrew prefix are identical before and after a session that ran
   aggressive commands inside the container.
5. `slr` runs in an `sbcl`-profile container, and its persistent image and client
   socket live under the project's `.slr/` **as seen inside the container** — a
   container-private `type=volume` mount (D10). The host's own `.slr/` is shadowed
   and unchanged, and the container leaves no artifact in the host project
   directory.
6. A `go-postgres` container has working `go` and a reachable postgres service in
   the same session.
7. No image under `images/` references any harness or agent; each harness is
   applied only through `harnesses/<name>.sh` selected by `ARG HARNESS`.
8. Exactly one harness is installed per image, and in the `pi` harness the
   `pi-permission-system` package is **absent** from the sandbox's pi settings.
9. `devbox` never reads a profile or compose file from a mounted workspace:
   `grep -r` finds no path that resolves inside `$PWD`.
10. `README.md` documents the invariants, the doctor command, and the reason
    T3 is out of scope for this runtime.
11. The container's interactive shell config is **inlined at image build** in
    `images/base/Dockerfile` (a heredoc writing `/root/.zshrc` plus the matching
    non-login rc): no `compose/`, `profiles/`, or `harnesses/` file mounts or
    copies any host shell config, and `docker run <base image> cat /root/.zshrc`
    prints exactly the inlined content.

## Budget

**New dependencies: none.** Host prerequisites are already present (Docker CLI,
`colima`, `lima`); `tmux` arrives with `0002`. The repo is shell + Dockerfile +
YAML + Markdown.

| File | Est. physical lines |
|---|---|
| `README.md` | 90 |
| `.gitignore` | 11 |
| `AGENTS.md` | 56 |
| `docs/plans/0001-devbox-runtime.md` (this file) | 469 |
| `docs/plans/0002-devbox-orchestrator.md` (sibling plan) | 233 |
| `docs/plans/backlog.md` | 61 |
| `docs/decisions/0001-sandbox-trust-posture.md` (from Appendix A) | 60 |
| `images/base/Dockerfile` | 55 |
| `images/sbcl/Dockerfile` | 35 |
| `images/go/Dockerfile` | 30 |
| `harnesses/pi.sh` | 30 |
| `harnesses/none.sh` | 10 |
| `bin/devbox` | 185 |
| `compose/devbox.compose.yaml` | 62 |
| `profiles/base.yaml` | 25 |
| `profiles/sbcl.yaml` | 27 |
| `profiles/go-postgres.yaml` | 25 |
| `tests/doctor.test.sh` | 95 |
| **Total** | **~1520–1590** |

Application logic ≈ 270 lines (`bin/devbox` + harness scripts). Everything else
is declarative config, docs, or tests. Growth beyond ~1400 without an updated
budget is a spec violation.

## Decisions

**D1 — Docker on the existing colima/Lima stack.** Already installed, fully
open source, no account, no vendor. Colima is a Lima-managed Linux VM, so
containers on macOS already sit behind a hypervisor boundary in addition to
namespaces. *Rejected:* Docker Sandboxes (`sbx`) — free but proprietary and
requires a Docker OAuth account, which fails the explicit "no external
commercial tools" constraint. *Rejected:* Gondolin as the first runtime — see
D7 and the backlog.

**D2 — Toolchain layers are harness-free.** `images/base` → the toolchain
layers (`images/sbcl`, `images/go`, …) know nothing about any agent. This is what
makes the runtime
extensible to any harness later, and it is why the harness seam is a separate
concern rather than a `RUN` line sprinkled in the toolchain layers.

**D3 — Harness selected by `ARG HARNESS` + `harnesses/<name>.sh`.** Adding a
harness is adding one script. *Rejected:* a Dockerfile per harness — compose
cannot express build ordering between images (no `depends_on` for builds), so
the toolchain image would have to be built by hand first. `ARG` lets one compose
file build the whole chain in order.

**D4 — One project mounted read-write; `.git/hooks` mounted read-only.**
*Rejected:* a fully permissive mount — git hooks are the one file class in the
workspace that escapes into automatic host execution, and `.git diff` does not
show them. *Rejected:* read-only project mount — removes the ability to work,
which is the point. Known residual: `.git/config` stays writable (ordinary
commit work needs it), so a determined agent could repoint `core.hooksPath` at a
hooks directory inside the writable workspace. Recorded, not hidden.

**D5 — Permissive inside the container, by absence.** The sandbox's pi settings
simply do not list `pi-permission-system`. Pi runs with all permissions by
default, so no profile mechanism is needed and the host's
`global-default.json` is untouched. *Rejected:* a "permissive" profile in the
permission extension — a permission system configured to allow everything is a
no-op with extra code, and it would have implied a cross-repo change for no
benefit. The boundary replaces the prompt: a VM/filesystem boundary is a
strictly stronger control than an `ask` dialog on a bash pattern, and unlike the
dialog it does not depend on the user being awake, present, or right.

**D6 — No cloud-reachable credentials in this runtime until an egress layer
exists.** Local-only work (postgres+go, lisp+slr, new projects) is fully served
without any remote credential. When a project genuinely needs cloud access the
answer is a **scoped identity** (separate dev account, role limited to one
stack, short-lived token) plus an egress allowlist — never a prod-capable key
behind a prompt. *Rejected:* relying on the permission system to gate remote
effects — it matches bash text, so one approval on a destructive call is
permanent, which is precisely how the AWS incident class works.

**D7 — Canonical config lives in the `devbox` repo, outside any mounted
workspace.** `devbox up <profile> <project>` invokes a trusted file. *Rejected:*
a compose file in the project validated by a denylist — detection rather than
impossibility, and only as complete as the list. *Rejected:* a project compose
file mounted read-only — the host still trusts a file in a directory the agent
writes to, so its safety depends on the mount list staying correct forever.
`doctor`'s validation still runs, as defence in depth.

**D8 — Installing inside the box is free; reshaping the box is a host-side
edit.** The agent may `apt-get install`, `npm i -g`, `go install`, or clone
repos inside the container at any time with zero host risk. Adding a mount, a
service, or a capability is a proposal the user applies. This is what keeps
autonomy high without reopening T4.

**D9 — The container's shell config is inlined in `images/base`, never mounted.**
The image writes its own `/root/.zshrc` (zsh from the distro; no plugins, no
network fetch at shell start, no host content). *Rejected:* mounting the host's
`~/.zshrc` read-only for familiarity — it imports host-only assumptions into the
box (Homebrew `PATH` entries, `DOCKER_HOST` pointing at a host socket), which
fail silently inside the container, and it makes a host file load-bearing for the
container's usability, which is the coupling D7 and I1 exist to remove. The host
shell config stays unreadable and unused; a shell that is predictable and wholly
owned by the image beats shell parity with the host.

**D10 — `slr`'s `.slr/` is container-private (`type=volume`), never the host's
directory.** Slice 1 proved the socket *does* work on the project mount, and also proved
what that costs: a host `slr` and a container `slr` on the same project both write
`.slr/last-session` and `image-generation`, so each side announces the other's
server as its own lost session (`prev: pid-… this: pid-…`) — indistinguishable
from a real crash — and the container's PIDs land in a host-visible file, a dead
`socket` node is left in the project after the container stops, and virtiofs makes
`ls -la .slr` fail with `EINVAL` on that node. A Docker volume mounted at
`<project>/.slr` removes all four. Verified end-to-end: the container's socket
lands on ext4 (`/dev/vdb1`, no `EINVAL`), `slr "(+ 11 31)"` → `=> 42` with the
image reused on the next call, the host's `.slr/` is shadowed with its file
untouched, and `docker rm -v` takes the volume with it. The volume is anonymous
(disposable by premise), so `devbox down` must remove it with the container.
*Rejected:* the shared mount — the interference makes a false "session lost"
indistinguishable from a real one, which is worse than the visibility it buys.
*Rejected:* `SLR_SOCKET` redirection — unusable in the case that matters, because
slr resolves an existing `.slr/` marker ahead of the environment override.
Consequence for `doctor`: `type=volume` is Docker-managed storage, not a host path.
Consequence for visibility: the container's REPL logs are reachable through
`devbox shell` / `docker exec`, never through the host project directory.

→ worth an ADR: sandbox trust posture — drafted in Appendix A.

## Approach

Four slices. Slice 1 exists to replace the two assumptions that cannot be
checked without running something (slr-in-container, and host-global
immutability) before any of the CLI is written around them.

**Slice 1 — prove the boundary by hand.** No `devbox` CLI yet. A hand-run
`docker run` with a single project mount: confirm the container cannot see host
siblings or any global path; checksum host globals before/after an aggressive
session; confirm `.git/hooks` read-only; get `slr` working inside (the real
question — `bin/slr` is a shell launcher around a precompiled SBCL core, and it
runs a persistent image plus a client socket under the project's `.slr/`, which
sits on the mounted path).

**Slice 2 — image layering + harness seam.** `images/base`, `images/sbcl`,
`images/go`, `harnesses/pi.sh`, `ARG HARNESS`, and the pi settings that
deliberately omit the permission extension.

**Slice 3 — `devbox` CLI + canonical profiles + compose.** `up`, `doctor`, the
invariant checks against the effective config, and the test script.

**Slice 4 — compose services.** The `go-postgres` profile: a second service on a
private network, reachable from the dev container, with no host port exposure
unless asked for.

## Steps

1. `git init` the repo; write `.gitignore`.
2. **Boundary proof (slice 1).** Hand-run the container against a scratch
   project. Record: `ls` of parent/global paths, before/after checksums of
   `~/.zshrc`, `~/.config`, `~/.pi`, Homebrew prefix. **If host globals change,
   stop** — the mount model is wrong and nothing else should be built on it.
3. **slr proof (slice 1).** Get SBCL + slr running inside; confirm the
   persistent image and socket in `.slr/`. **If the socket cannot cross the
   boundary, decide**: socket inside the container with the image on the mount,
   or a `.slr/` exclusion from the read-write mount. **Resolved in slice 1
   (2026-09-24):** the socket works on the mount, but host and container images
   interfere through the shared markers, so a container-private volume at `.slr/`
   was chosen (D10) and verified end-to-end.
4. Write `images/*` + `harnesses/pi.sh`; verify `ARG HARNESS` builds in one
   compose invocation.
5. Write `bin/devbox` (`up`, `doctor`) + `compose/devbox.compose.yaml`.
6. Write `tests/doctor.test.sh` covering each of I1–I4 with a deliberately
   violating profile that must fail.
7. Add the `go-postgres` profile; verify both services in one session.
8. File the ADR from Appendix A as `docs/decisions/0001-sandbox-trust-posture.md`.
9. Write `README.md` + the backlog entry for Gondolin.
10. Run the acceptance checklist; report each line pass/fail.

## Open questions

| Question | Recipe |
|---|---|
| Can the container reach any host path beyond the project? | `docker run … ls /Users/<me>` — slice 1 step 2. |
| Are host globals truly unreachable? | checksum `~/.zshrc`, `~/.config`, `~/.pi`, `brew --prefix` before/after — slice 1 step 2. |
| Does slr's client/server socket work across the boundary? | **Answered (slice 1):** yes on the mount; the design instead uses a container-private volume for isolation — D10. |
| Does `.git/hooks` read-only mount nest correctly inside the project mount? | create a hooks dir, attempt a write from inside, expect EROFS. |
| Does `doctor` see through compose interpolation/includes? | build a profile with an env-var-interpolated dangerous mount; `doctor` must still fail. |
| Does colima allow the nested bind mount? | slice 1; fallback is a `.git/hooks` bind from a host-side path outside the mount. |
| SBCL/slr installation shape inside the image? | Derive from the slr repo's own `install.sh`; the CLAUDE.md-documented install prefix is `/usr/local/lib/slr`. |
| Does postgres need a host port, or is in-network access enough? | slice 4; default to no host port. |
| Does `pi` inside the container need `--approve` / project trust configuration? | Non-interactive modes ignore project resources unless `defaultProjectTrust` is set; verify the container's pi settings. |

## Confidence

**98%.** Constraints written down as invariants I1–I6 plus acceptance criteria
1–10; every edge case has a stated recipe; the fallback is known for each
unverified step (socket location for slr, hooks bind for a colima limitation).
The two historical incidents are mapped to specific controls rather than to good
intentions, and the one threat this runtime explicitly does **not** address (T3)
is stated in the goal, the criteria, and the README so it cannot be assumed
away.

The residual is execution-gated: slice 1 exists to convert the boundary and slr
claims into facts before the CLI is designed around them.

## Review log

_Empty — populated by `/skill:code-review` after implementation._

## Appendix A — ADR draft: sandbox trust posture

To be filed as `docs/decisions/0001-sandbox-trust-posture.md`.

**Context.** Two incidents drove this design. An agent deleted a production AWS
stack. An agent damaged local global state — shell config, application config,
Homebrew prefix — to the point where the environment had to be rebuilt. The
existing mitigation was a permission extension on the host
(`pi-permission-system`: `bash: {"*": "ask"}`, `rm -rf *: deny`,
`external_directory: ask`), which produced continuous prompts and did not
prevent either incident, because pattern-matching bash text gates neither remote
effects nor files the host later executes.

**Decision.** Isolate by container and control by capability, not by prompt.

1. The container's filesystem is the host-filesystem boundary. Global host paths
   are unreachable by construction, not by policy.
2. Inside the container, permissions are fully permissive — the permission
   extension is not installed. The boundary replaces the prompt.
3. Inside the container, only the project directory is mounted read-write, plus
   `.git/hooks` read-only. Installing software inside the box is unrestricted;
   reshaping the box is a host-side edit.
4. Remote blast radius is controlled by **credential absence** and, later, by an
   egress allowlist — never by the runtime. No cloud-reachable credential is
   mounted into the Docker runtime. Cloud-touching projects require a scoped
   identity.
5. Every host-trusted config file resolves from the `devbox` repo, never from a
   mounted workspace.

**Consequences.** Autonomy becomes genuinely unattended for local work, because
the failure modes that matter are structurally absent rather than dialog-gated.
Two costs are accepted deliberately: cloud work is unavailable in the Docker
runtime until an egress layer exists, and the enforcement now lives in
invariants that must be checked (`devbox doctor`) rather than in a dialog a
human reads. The residual risks are named: `.git/config` stays writable so
`core.hooksPath` could be repointed into the workspace; and a project that is
given a prod-capable credential would have the same blast radius as before,
regardless of this runtime. Neither is mitigated by tightening the container —
the first needs a hooks-path check, the second needs scoped identity, and this
ADR must be revisited if either is assumed solved by the sandbox alone.
