# 0004 — agent workstation: the box carries the harness and its tools

## Status: completed — delivered, reviewed, signed off 2026-11-14

Depends on `0001` (delivered) and `0003` (delivered). Prerequisite for `0002`:
the supervisor loop needs pi with the flow packages, the skillset skills and a
browser, inside the box, before any `/wf` run is worth measuring.

## Goal

Choosing a harness selects the agent that lands in the box, and with it the tools
that agent needs — from **this machine's current state of our projects**, not from
whatever npm published:

```console
$ devbox up sbcl ~/source/priv/myapp
# box now has: pi · every @joozik/* extension (flow, flow-workflow, pi-subagents,
#              pi-playwright, pi-permission-system) · skillset's skills/agents/prompts
#              · chromium + playwright, browser tools ACTIVE at startup
#              · an explicit allow-all permission policy · slr (sbcl profile)

$ devbox up go-postgres ~/source/priv/other    # same agent payload, Go toolchain
$ devbox up base ~/source/priv/scratch         # no agent at all — harness "none"
```

"Always the latest versions of those tools" means: **whatever is in the local
checkout right now, including uncommitted work**, identified by a content stamp so
the box is still reproducible. Nothing floats from a registry at `up` time.

## Facts this plan is built on (measured 2026-11-12)

| # | Claim | Evidence |
|---|---|---|
| F1 | The `pi` harness installs pi and nothing else | `harnesses/pi.sh`: one `npm install -g @earendil-works/pi-coding-agent`, then `settings.json` with two keys |
| F2 | pi loads packages from a local path without copying, and discovers TS extensions | `docs/packages.md`: "Local · `./pi-tools` · Loaded from the resolved path without copying"; "Without a `pi` manifest, Pi discovers TypeScript and JavaScript extensions" |
| F3 | `defaultTools` accepts `+name` entries and activates tools that register with `defaultActive: false` | `docs/cli.md:130`; `docs/extensions.md:2311`; `pi-playwright/extensions/tools.ts:445` sets `defaultActive: false` on all 13 |
| F4 | The permission extension reads `~/.pi/agent/extensions/pi-permission-system/config.json`, and `ask` needs a UI answer | `pi-permission-system/README.md` (Quick Start; "Prompts the user for confirmation via UI") — in an unattended box an `ask` is a stall |
| F5 | `skillset` has a non-interactive `sync` that reconciles every declared install to repository sources | `node dist/cli.js sync --help`: `--dry-run`, `--prune` |
| F6 | Our packages are local, not published under one name: `@joozik/pi-subagents`, not `@gotgenes/pi-subagents` | `packages/pi-subagents/package.json` vs `0002-devbox-orchestrator.md:102` |
| F7 | `flow` declares its siblings as peers, so they must be installed explicitly | `packages/flow/package.json` peerDependencies |
| F8 | slr and `pi-slr-service` both exist locally | `~/source/priv/smart-lisp-repl`, `packages/pi-slr-service` |

**Measured while preparing the plan (2026-11-13), in `ubuntu:24.04`, arm64:**

| # | Result |
|---|---|
| F9 | `npm ci --omit=dev --legacy-peer-deps` in a materialised pi-extensions context succeeds in **1 s** (22 packages) but does **not** install the peers: `require.resolve("typebox")` and `require.resolve("yaml")` fail. Installing the peers of the five declared packages explicitly adds **151 packages in 12 s** and all resolve. A test-only peer (`vitest`, from `flow-test-utils`) is not among them once only declared packages are considered. |
| F10 | `pi list` resolves all five local-path packages, and `pi` starts with them and stops at `No API key found` — no package or extension load error. |
| F11 | `npx playwright install --with-deps chromium` takes **41 s** and downloads **chromium 393 MB + headless shell 266 MB + ffmpeg 3.3 MB**; headless launch, navigation to a `data:` URL and a screenshot all work. `--with-deps` pulled the OS libraries, so no apt browser is needed. |
| F12 | skillset: `npm ci` 4 s (65 packages), `npm run build` 7 s → `dist/skills` + `dist/agents`; `sync --dry-run` with `HOME=/root` exits 0 and enumerates installs for **both the `pi` and the `claude-code` target**. |
| F13 | A representative image with dev cruft committed at **2.7 GB**; parts measured: pi global 179 MB, pi-extensions `node_modules` 305 MB (full peer set), skillset `node_modules` 110 MB, browsers 662 MB. A lean build — `--omit=dev` for pi-extensions, pruned skillset, headless-only browser — is the target in the budget below. |

The two remaining hypotheses are decided by this evidence rather than measured
again: Ubuntu 24.04 needs no apt browser (F11), and `sync` works outside its own
host state (F12).

## Decisions

**D1 — the payload is harness-gated, not profile-gated.** `harnesses/pi.sh` grows
into the agent installer; `harnesses/none.sh` stays bare, so `base` remains the
agent-free reference profile and the reference `doctor` is exercised against. A
future harness (`claude-code`, …) is a new `harnesses/<name>.sh` consuming the same
payload directory. *Rejected:* putting the agent in `images/base/Dockerfile` — the
image then carries an agent for profiles that deliberately have none, and the
harness seam (D3 of 0001) stops being the single place an agent is named.

**D2 — the sources are the checkouts themselves; `up` materialises a build context
from each, and nothing is mounted.** Defaults
`PIEXT_REPO=~/source/priv/pi-extensions`, `SKILLSET_REPO=~/source/priv/skillset`,
overridable. For each, `bin/devbox` writes a context under
`$XDG_STATE_HOME/devbox/contexts/<name>/` from **exactly the files git does not
ignore** — `git ls-files --cached --others --exclude-standard`, taking working-tree
content — so unreleased and dirty work ships, `node_modules` and `.env` do not, and
a tree that is dirty is still coherent (measured: pi-extensions currently has three
untracked files that modified code imports; a `git archive HEAD` copy would be
inconsistent).

The context is then *installed*, not merely copied: `npm ci --omit=dev
--legacy-peer-deps`, then the peer set of the **five declared packages** explicitly
(F9 measured that `--omit=dev` skips them, and a missing `typebox` breaks
`pi-playwright` at load), for pi-extensions — pi loads the TypeScript sources
directly (F2), so no build step; and `npm ci && npm run build` for skillset, whose
`dist/` is **not** tracked (0 tracked files under `dist`), pruned of dev
dependencies afterwards. A build-time guard refuses the context if
it contains a credential-shaped filename (`.env*`, `*.pem`, `*.key`, `*.p12`,
`id_*`) and reports, by name only, any file matching a secret-shaped pattern.

*Rejected:* a hand-filled staging cache like slr's (`~/.cache/devbox/*-src`) — a
second place to go stale; *rejected:* npm-pinned installs — they cannot ship
unreleased work; *rejected:* mount the checkouts (I1, I6); *rejected:*
`git archive HEAD` alone — it hides the untracked files a dirty tree depends on.

**D3 — "latest" is identified by a content stamp, and `up` rebuilds when it moves.**
Stamp = per source: `git rev-parse HEAD` plus a digest of the materialised file set
(names and contents), so a dirty tree, a new untracked file and a deleted file each
produce a different stamp, while an ignored file changes nothing. Written to
`/opt/devbox/agent/SOURCES`, stamped as an image label, printed by `doctor`; `up`
compares the stamp of the running box and rebuilds when it differs. Reproducible
after the fact, current by construction. *Rejected:* floating `@latest` npm at
`up` (unreproducible, network on the critical path, breaks the moment egress is
restricted); *rejected:* a manual `--refresh` flag only (fails the "always latest"
requirement the moment it is forgotten).

**D4 — the permission policy is explicit and allow-all, in a canonical file.** The
box gets `pi-permission-system` installed *with* a config that allows everything
(`{"*":"allow"}`, `bash: {"*":"allow"}`, `external_directory: "allow"`), because
`ask` would stall an unattended run (F4) and absence would leave nothing to audit.
This is the future seam for a restricted box: the same file, narrower values.
*Rejected:* relying on the extension's documented defaults (`bash: ask`) — that is
an interactive-machine policy; *rejected:* no extension at all — today's state,
which is permissive by absence and gives no place to record intent.

**D5 — browser tools are active at startup and the browser is baked, headless by
default.** All 13 `browser_*` names go into `defaultTools` with `+` entries (F3), so
no `/playwright` is needed before use. The build installs Playwright's
**`chromium-headless-shell` only** (266 MB measured) and pins
`PI_PLAYWRIGHT_EXECUTABLE` to it; `DEVBOX_BROWSER=full` adds full chromium
(+393 MB) for `headed: true`, which is a review convenience, not an unattended
need. *Rejected:* apt `chromium-browser` — a snap stub; *rejected:* always full
chromium — 393 MB for a mode an unattended run cannot see; *rejected:* an
image-local extension calling `setActiveTools()` on session start — more code for
the same effect.

**D6 — skillset artifacts are generated at build by skillset itself.** After D2's
install and build, run `node dist/cli.js sync` with `HOME=/root` (F5) so every
declared install lands in `/root/.pi/agent/{skills,agents,prompts}`. `sync` also
targets `claude-code` by declaration (F12); in a pi box those writes are noise and
the step restricts targets to the harness being built, or verifies the extra
directory is harmless. Fallback if H3
fails: stage the built bundle (`dist/skills`, `dist/agents`, `dist/prompts`) into
the same locations by the same include rule, and record the fallback as an
amendment. *Rejected:* copying files from
the host's `~/.pi/agent` — an installed copy is an output, and copying it would
smuggle host-specific state past the build.

**D7 — the loop itself is not this plan.** 0002 owns the supervisor, its task
decomposition, per-task builder/reviewer rounds and the final review cap; 0004 only
guarantees the box has the pieces those stages need. `pi-slr-service` and the
"slr as our codemode" question are recorded in the backlog, not built here.

→ worth an ADR: the payload is identified by source content, and a box's tools are
reproducible only together with that stamp. Draft in Appendix A.

## Acceptance criteria

1. `devbox up sbcl <path>` yields a box where `pi list` resolves **five** local
   packages — flow, flow-workflow, pi-subagents, pi-playwright,
   pi-permission-system (and flow's peers) — all under `/opt/devbox/agent/`, none
   from a registry; and no file under `/opt/devbox/agent/` has a credential-shaped
   name (`.env*`, `*.pem`, `*.key`, `*.p12`, `id_*`).
2. `pi` starts in the box without network access and reports no package or
   extension load error.
3. `/root/.pi/agent/skills` contains the same skill names as
   `<SKILLSET_SRC>/dist/skills` (set equality, not a count), and the same for
   `agents` and `prompts`.
4. The 13 `browser_*` tools are **active at startup** (present in the session's
   active set before any `/playwright`), and a headless chromium smoke test
   navigates to a `data:` URL and screenshots it; with `DEVBOX_BROWSER=full` the
   headed binary is present too and the default build does not carry it.
5. Inside the box, `rm -rf /tmp/devbox-probe` and a write to `/root/probe` complete
   with no prompt and no denial, and the permission config at the canonical path
   contains an allow-all policy — i.e. an unattended session cannot block on a
   permission ask.
6. The stamp moves for a dirty edit, a **new untracked** source file and a deleted
   one, and does not move for an ignored file; `up` rebuilds exactly on a move,
   reuses the image otherwise; `doctor` prints the stamp; the new untracked file is
   present in the payload.
7. `harnesses/none.sh` still produces a box with no agent payload, no chromium and
   no `/root/.pi` — the hierarchy `harnesses/none.sh` → `pi` → future harnesses is
   visible in `devbox doctor`'s output.
8. I1/I4 are unchanged: no host path outside `{worktree, gitdir, hooks}` is
   mounted, and no host `~/.pi`, `~/.config`, `~/.aws` or credentials appear in the
   image or the mounts. `devbox doctor` passes on all canonical profiles.
9. `tests/agent-image.test.sh` asserts 1–5 and 7 inside a real container, the lean
   image measures **≤ 2.2 GB** and a cold build **≤ 6 minutes** on this machine
   (recorded in the plan), and the full suite passes twice with no leftover
   containers, volumes or images.
10. `README.md` and `AGENTS.md` document the sources, the stamp, the rebuild
    behaviour and how to add a tool; 0002's `@gotgenes/pi-subagents` line is
    corrected to `@joozik/pi-subagents`.

## Budget

**New dependencies:** Playwright's browser download (build-time only), the
`@joozik/*` sources as build contexts, `skillset` as a build context. No host
runtime dependency beyond what 0003 already requires.

| File | Est. physical lines |
|---|---|
| `docs/plans/0004-agent-workstation.md` (this file) | ~230 | 293 |
| `harnesses/pi.sh` (rewrite: payload install, settings, permission config, browser) | ~140 |
| `harnesses/lib/agent-payload.sh` (new: materialisation, guard, stamping, wiring) | ~70 |
| `compose/devbox.compose.yaml` (edit: build args + additional contexts for the two sources) | +14 |
| `bin/devbox` (edit: resolve sources, compute stamp, rebuild decision, doctor line) | +55 |
| `tests/agent-image.test.sh` (new: criteria 1–5, 7) | ~110 |
| `README.md` / `AGENTS.md` (edit: sources, stamp, rebuild, tools) | +45 |
| **Total** | **~640–730** |

Application logic ≈ 250 lines (materialisation, harness wiring, stamping, rebuild
decision, test assertions). Growth beyond ~730 without an amended budget is a spec
violation.

## Steps

1. **Preparation is done** (F9–F13): the mechanism holds end to end. What remains
   here is to pin the exact versions measured (pi 1.5.2, playwright 1.63.0,
   node 22.19) and to record them in the plan as the build's floor.
2. Add `harnesses/lib/agent-payload.sh`: source resolution, materialisation by the
   include rule, the credential-shaped-name guard, stamp computation, and the
   `SOURCES` file.
3. Rewrite `harnesses/pi.sh` around it: install the packages as local paths, write
   the permission config, set `defaultTools` with the browser names, pin
   `PI_PLAYWRIGHT_EXECUTABLE`, install chromium.
4. Wire the skillset build and `skillset sync` (H3); if it cannot run detached from
   its repository, stage the bundle and record the amendment.
5. compose: pass both sources as `additional_contexts` and the stamp as an image
   label; keep `base`'s build unchanged.
6. `bin/devbox`: resolve the sources, compute the stamp, rebuild only when it
   differs, print it in `doctor`.
7. Write `tests/agent-image.test.sh`; keep `doctor.test.sh` and
   `worktree.test.sh` green (criterion 8).
8. Measure size and build time; record them in this plan (criterion 9's budget).
9. Update README/AGENTS, correct 0002's package name, and file Appendix A as an
   ADR if the stamp earns it.

## Verification invariants

- The same source content produces the same stamp on two consecutive builds; a
  one-line edit to either source changes it.
- After `down`, no container or volume from the run remains (asserted by compose
  label), and the image is reused rather than rebuilt on the next `up`.
- Skill set equality is asserted against the source bundle, never against a count.
- The unattended assertion is behavioural: a command that the interactive policy
  would ask about completes without a prompt, in a session with no client attached.

## Open questions

| Question | Recipe |
|---|---|
| Does `npx playwright install --with-deps chromium` succeed on `ubuntu:24.04` and launch headless? | Step 1 (H1) |
| Does pi load five local-path packages, with TS sources, and start clean? | Step 1 (H2) |
| Can `defaultTools` name extension tools that registered `defaultActive: false`? | Step 1: read the active set from a real session |
| Does `skillset sync` work with `HOME=/root` inside the image? | Step 4 (H3) |
| Does `skillset sync` take a target filter, or must the claude-code writes be tolerated? | `node dist/cli.js sync --help` and the config's target list |
| What is the exact lean image size after pruning skillset's dev deps and the npm cache in the same layer? | Step 8, recorded against criterion 9 |
| What do the payload and chromium cost in image size and build time? | Step 8 (H4) |
| Is `pi-slr-service` part of the toolbox now, or after the codemode research? | Backlog entry; not this plan |
| Are flow's peers all needed, or only the ones the skills import? | Step 3: remove one and assert nothing breaks |

Every row above is now settled, and the settlement lives in the Amendments rather
than here as history: the playwright and pi-load questions by F11/F10 and the
suite; `defaultTools` by the thirteen tools the probe reads from a real session;
`sync` under `HOME=/root` by the build, and its lack of a target filter by A4;
the lean size and the payload's cost by A7 (2.03 GB, 1 m 49 s cold); flow's peers
by A5 — the six are required *declarations*, while the installed peer set was
left whole because the extensions import the agent API modules for real, so
trimming it is a follow-up, not a condition of this plan. `pi-slr-service` stays
in the backlog (D7).

## Needs the developer

- Confirm the two checkouts — `~/source/priv/pi-extensions` and
  `~/source/priv/skillset` — are the sources, and that everything git does **not**
  ignore in them is safe to bake into an image, because it becomes readable to every
  agent inside the box (including the three untracked files currently in
  pi-extensions). Tracked content was scanned: no secret-shaped strings in either
  repository as of 2026-11-12, and ignored files (`.env`, `node_modules`) never
  enter the context.
- Accept the image growth and build time recorded in step 8.
- Sign off the plan; then 0002 may start against a box that already has the agent.

## Amendments

**A1 (2026-11-13) — two files the budget did not list, and delivered sizes.**
`images/base/Dockerfile` (+13: the payload contexts, the stamp label and four
build args) and `images/payload-empty/` (the empty context a `none` build
receives) are unavoidable: a named build context is consumed only by a `COPY` in
the Dockerfile, and a single harness-free Dockerfile cannot conditionally copy
one. Delivered: `harnesses/pi.sh` 141 lines (est. ~140),
`harnesses/lib/agent-payload.sh` 44 (est. ~70), `bin/devbox` 378 (+80 against
+55), `compose/devbox.compose.yaml` 84 (+13 against +14),
`tests/agent-image.test.sh` 256 (est. ~110 — the stamp section, thirteen
per-tool assertions, the payload-content and full-browser assertions are the
difference), `README.md` 182 (+45), `AGENTS.md` 95 (+16), plus
`docs/decisions/0002-agent-payload-by-source-content.md` (49, A10).

**A2 (2026-11-13) — the payload installs with `npm install`, not `npm ci`.**
Measured: a workspace member added but not yet locked — `packages/pi-slr-script`,
present in the tree during this work, exactly the dirty state D2 exists to ship —
makes `npm ci` abort with `EUSAGE … Missing: @joozik/pi-slr-script from lock
file`. `npm install --omit=dev --legacy-peer-deps` installs it. Reproducibility
here comes from the stamp (commit + content digest), not from the lock. skillset
remains `npm ci` (single package, coherent lock).

**A3 (2026-11-13) — the permission config nests under `permission`.**
D4's shorthand was `{"*":"allow"}`; the extension's schema is
`{"permission": {"*": "allow", "bash": {"*": "allow"}, "external_directory":
"allow"}}` (`pi-permission-system/README.md`, Quick Start). Written in the
documented shape and verified behaviourally: an RPC `bash` call running
`rm -rf /tmp/devbox-probe` plus a write to `/root/probe` returns
`"success":true` with no attached client to answer a prompt.

**A4 (2026-11-13) — `sync` takes no target filter; criterion 3's reference is the
declarations.** `node dist/cli.js sync --help` offers only `--dry-run` and
`--prune`, so the claude-code and opencode writes land in the box's `/root` as
noise (D6's tolerated branch, recorded here rather than restricted). There is no
`dist/prompts`: pi's prompt templates are generated from `dist/skills`
frontmatter, so the test derives all three expected sets from
`skillset.config.json` — skill *name* for `mode: auto`, frontmatter *slug* for
`mode: slash`, and `dist/agents` — and asserts set equality for each.

**A5 (2026-11-13) — the payload declares eleven pi packages, not five.**
`pi` starts with the five and reports `flow: 6 sibling extensions missing`
(flow-advisor, flow-args, flow-ask-user-question, flow-i18n, flow-todo,
flow-web-tools), because flow's own startup check reads the declarations, not
resolution. All six are added to `settings.json`; `pi list` resolves eleven
entries, every one under `/opt/devbox/agent/`.

**A6 (2026-11-13) — the credential guard runs at materialisation, and its SSH
patterns are named.** The guard runs where the context is written, before an image
exists, so a credential-shaped name never enters a build context at all. `id_*`
is narrowed to `id_rsa*`, `id_dsa*`, `id_ecdsa*`, `id_ed25519*`: the literal glob
matches typebox's `id_ID` locale files (measured inside the built image), so it
would refuse a clean tree.

**A7 (2026-11-13) — measurements for criterion 9, and the reset procedure.**
Lean image **2.03 GB** (`devbox/dev-sbcl:local`, `docker images`: 1.91 GB base
layer), cold build **1 m 49 s** (`docker compose … build --no-cache devbox`,
base+sbcl, 2026-11-13). Pinned at build: node 22.19.0, pi 1.5.2, playwright
1.63.0, chromium-headless-shell 1243. Cutting the dev-cruft measurement to the
target came from `--omit=dev` on the peer install (which had brought
`@biomejs`/`@typescript` back in, 84 MB), pruning skillset to production
dependencies (110 MB → 5 MB), the headless-only browser, the node headers (56 MB)
and playwright's leftover `apt` lists (57 MB).

**A8 (2026-11-13) — `doctor` names the harness and `up` gains `--rebuild`.**
Criterion 7 asks for the harness hierarchy to be visible in doctor's output, so
the ok line carries `harness <name>`. `--rebuild` exists because the stamp covers
the two sources and not this repo: without it, editing a Dockerfile or a harness
script would never reach a rebuilt image.

**A9 (2026-11-13) — criterion 6 is verified in two halves.** The test drives the
stamp through clones of both sources in scratch state (same content twice, dirty
edit, new untracked file, delete, ignored file) and asserts that a second `up`
reuses the image and that the label equals doctor's stamp. The rebuild-on-move
half was also observed on the real sources: a file another session added to
`pi-extensions` moved the stamp and the next `up` rebuilt.

**A10 (2026-11-13) — the ADR is filed.** Appendix A is now
`docs/decisions/0002-agent-payload-by-source-content.md`, recording the stamp, the
harness gate and the allow-all permission posture as durable decisions rather than
plan history.

**A11 (2026-11-13) — three defects found by the pre-sign-off review pass.**
(a) `doctor`'s "agent sources unavailable" branch was unreachable: the missing
checkout called `die`, which exits the shell, so doctor exited 1 silently — it now
returns from `prepare_agent_payload`, and `up` is what refuses
(`agent source pi-extensions not found at /nonexistent — clone it, or point
PIEXT_REPO at it`, exit 1) while `doctor` reports and stays green, which is
correct: a missing checkout breaks a build, not an invariant. (b) A quoted
`HARNESS: "pi"` was read as `none`, so an agent profile would have built the
sentinel payload and failed inside the harness — the profile reader now tolerates
quotes. (c) `DEVBOX_BROWSER=full` handed playwright
`"chromium-headless-shell chromium"` as one argument and the build died with
`Invalid installation targets`; the two targets are now separate arguments.
Measured after the fix: `full` carries `chromium-1243` **and**
`chromium_headless_shell-1243` (2.52 GB), the default build carries only the
shell (2.03 GB). The suite also drops the profile tag first, so it exercises the
"no image yet" branch and picks up a harness change the stamp cannot see (A8).

**A12 (2026-11-14) — the code review's findings are fixed.** Two 🔴, six 🟡 and
fourteen 🔵, all addressed in the change itself rather than deferred:

(a) **Payload installs pass `--ignore-scripts`** (both sources), so a working tree
that gained a lifecycle script cannot execute at build time; nothing in either
source needs the scripts (`skillset`'s `prepare` only ran `npm run build`, which
the harness runs explicitly).
(b) **The stamp now covers the build inputs the sources do not describe** — the
harness name and the browser mode — so `DEVBOX_BROWSER=full` rebuilds instead of
silently reusing a headless image; the mode is validated (`headless` / `full`) in
one place and `BROWSER` in the harness is no longer an exact-match fallback. The
`devbox` build block now declares the same four args as `devbox-base`, so a
profile that selects its harness there is stamped too.
(c) **The guard's deny-list gained the credential classes I4 already names**
(`.npmrc`, `.netrc`, `credentials.json`, `*.pfx`, `*.jks`, `*.keystore`,
`*.token`) and a secret-shaped *content* match now refuses the build instead of
reporting it.
(d) **`doctor` materialises into a throwaway root**: validating a config no longer
writes the machine's payload store, and the invariant suite no longer writes there
by accident.
(e) **A harness name with no `harnesses/<name>.sh` is refused up front**, and the
reader also accepts the flow-map form.
(f) The four floating peers are pinned (`typebox` 1.4.7, `@sinclair/typebox`
0.34.52, `yaml` 2.9.1, `@standard-schema/spec` 1.1.0), both payloads are checked
before either is moved, the help text prints one line per verb, the payload
contexts are named by their own digest (a concurrent `up` cannot rewrite one a
build is reading, and no lock is needed), the pre-digest layout is pruned, the
internal context variables no longer read the ambient environment, and
`PI_PLAYWRIGHT_EXECUTABLE` moved from `~/.zshenv` to the container's environment so
a tmux- or exec-launched pi sees it.

Coverage closed with it: the credential refusal, the moved-stamp rebuild and
`DEVBOX_BROWSER=full` are now asserted through `up` in
`tests/agent-image.test.sh` (69 → 70 assertions), and AGENTS.md's "prune the
context dir and the box rebuilds" — false, the digest is content — is gone.
Re-measured after the change: lean image **2.03 GB**, cold build **1 m 48 s**,
suites **26 / 46 / 70** twice with no leftovers.

Delivered size after the review fixes, against A1's figures: `bin/devbox` 439
(+74: the digest-named contexts, the scratch doctor root, the harness check and
the stamp's extra inputs), `harnesses/pi.sh` 146, `harnesses/lib/agent-payload.sh`
50, `compose/devbox.compose.yaml` 94, `images/base/Dockerfile` 67,
`tests/agent-image.test.sh` 265, `README.md` 188, `AGENTS.md` 101, this plan 440.
The delta is the review's, not new scope.

## Confidence

**97%.** Every load-bearing mechanism is now measured (F9–F13): the workspace
installs and its missing peers are known by name, `pi list` resolves five
local-path packages and pi starts clean, chromium installs and screenshots
headless, and skillset builds and syncs outside its own host state. The remaining
3%: the exact lean image size after pruning (target ≤ 2.2 GB against a 2.7 GB
dev-cruft measurement), whether `sync` can be restricted to the pi target, and a
cold build time measured as a whole rather than summed from its parts.

## Review log

**Round 1 — 2026-11-14** (`/skill:code-review`, scope `modified`, 8 tracked files;
the five untracked deliverables were outside the chosen scope and are named as
such in that review, not cleared by it). Two 🔴, six 🟡, fourteen 🔵; 21 findings
verified, 2 weakened, 0 falsified; adjudicated by the session's advisor.

Verdict: the delta met its spec but was not committable as reviewed — the payload
lib, the suite, the ADR and this plan were untracked.

Every finding is fixed in the change rather than deferred; the fixes, the three
measurements that decided them (the silent `DEVBOX_BROWSER` reuse, doctor's
15 MB state write, the cold build) and the line counts are recorded in **A12**.
The two coverage gaps the review named became assertions: the credential refusal,
the moved-stamp rebuild and `DEVBOX_BROWSER=full` now run through `up`.
Re-verified after the fixes: **26 / 46 / 70 ok, 0 failed**, twice, no leftovers;
lean image 2.03 GB, cold build 1 m 48 s.

## Appendix A — ADR draft: the box's tools are identified by source content

**Context.** The workstation must carry the current state of our own projects,
including unreleased work, while remaining reproducible and auditable. Registry
pins cannot carry unreleased code; floating `@latest` installs make two boxes built
a day apart incomparable and put the network in the path of every `up`.

**Decision.** The agent payload is built from local checkouts of `pi-extensions`
and `skillset`, identified by a content stamp (commit plus dirty-tree digest),
stamped into the image and printed by `doctor`; `up` rebuilds exactly when the
stamp moves. The payload is harness-gated: a profile with no harness carries no
agent. Permissions inside the box are explicit allow-all, because an unattended
session cannot answer an ask.

**Consequences.** A box is reproducible together with its stamp, and current by
construction; the cost is image size, build time, and the discipline of keeping the
two source caches present. A future restricted box narrows the same canonical
config instead of inventing a second mechanism.
