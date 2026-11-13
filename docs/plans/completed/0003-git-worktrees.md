# 0003 — worktree-capable runtime: mirrored worktree + gitdir

## Status: completed — signed off 2026-11-12

Depends on `0001` (delivered). Prerequisite for `0002` (the autonomy loop): the
loop's completion artifacts and its per-feature boxes live in worktrees.

## Goal

One feature, one box, one worktree — several boxes on the same repository at
once, each reviewing and committing from the host as today:

```console
$ git -C ~/source/priv/myapp worktree add .devbox/wt/feat-a -b feat-a
$ devbox up base ~/source/priv/myapp/.devbox/wt/feat-a
$ devbox up base ~/source/priv/myapp/.devbox/wt/feat-b    # simultaneously, same repo
$ devbox shell base ~/source/priv/myapp/.devbox/wt/feat-a
```

`devbox up` on a worktree currently **fails** (`mkdir: <worktree>/.git: Not a
directory`) and `doctor` **passes it wrongly** — both measured (see Facts).

## Facts this plan is built on (measured, 2026-11-12, this machine)

| # | Claim | Evidence |
|---|---|---|
| F1 | A worktree's `.git` is a file naming an absolute host gitdir; `<gitdir>/gitdir` points back, also absolute | probe repo, `cat` of both files |
| F2 | Mounting only the worktree (any target path) is rejected: `fatal: not a git repository` | `docker run` with the worktree at `/workspace` |
| F3 | Mounting worktree **and** gitdir at their host-absolute paths works for `status`, `commit`, and host visibility | same probe, container git 2.43, commit `19ab203` |
| F4 | Same shape with the gitdir read-only blocks commits at the filesystem level: `Unable to create '…/index.lock': Read-only file system` | same probe, `-v …/.git:…/.git:ro` |
| F5 | `git worktree add --relative-paths` (host git 2.56) makes the image's git 2.43 refuse the repo: `unknown repository extension found: relativeworktrees` | same probe |
| F6 | A detached tmux pane has `stdin=YES stdout=YES` on `/dev/pts/0` with zero clients; pi's mode gate is `stdin.isTTY && stdout.isTTY` | probe in `devbox/dev-sbcl:local`; `dist/cli/auth-terminal.js`, `dist/main.js` |
| F7 | compose accepts a bind whose source equals its target outside the project dir, and `read_only: ${RO:-false}` coerces to a real boolean | `docker compose config --format json`, both values |

Hypotheses that the build must turn into facts (each has a step and a test):
H1 `docker compose up` behaves like `docker run` for those binds; H2 a container
can mkdir host-absolute mount targets as parents; H3 git 2.43 reads metadata
written by host git 2.56 for a repo with no unknown extension (F3 already
suggests yes); H4 two compose projects from one repo's `.git` do not deadlock.

## Decisions

**D1 — mirrors, not translations.** Mount the worktree and its gitdir at the
host's own absolute paths; working directory is the worktree root. The `.git`
file and its backlink already contain those strings, so nothing rewrites git
metadata. *Rejected:* mounting the worktree at `/workspace` (F2), relative
worktrees (F5, and it puts the gitdir inside the one RW mount so D2 dies),
`git worktree repair` per box (mutates metadata the host also reads; races).

**D2 — review-only is a read-only gitdir mount**, per `0001`'s A10. Worktree RW,
gitdir RO, hooks RO, `GIT_OPTIONAL_LOCKS=0`. The agent can read history and
`git status`, cannot stage or commit; it writes `COMMIT_PROPOSAL.md` (A12) and
the host commits. *Rejected:* a prompt-level "do not commit" (the incident class
this repo exists for), and mounting only `.git/objects` RO (refs would still be
writable).

**D3 — the policy lives outside the project and outside this repo**, machine
local: `~/.local/state/devbox/policy/<absolute-path-sha256>.policy`, two lines —
mode, then the absolute path. Absent file means commits-allowed; a present but
unreadable file fails closed (refuse to start). *Rejected as an implementation
detail:* `0001`'s A11 named a single `policy.yaml` — parsing YAML in `sh` either
requires a helper or a hand-rolled subset, and a misparse here fails **open**.
The record is amended, not renamed.

**D4 — `.devbox/` is excluded via `<gitdir>/info/exclude`**, written by `up`,
idempotently. The worktree home must not show up as untracked in the main
checkout (an agent could otherwise commit a sibling worktree), and
`info/exclude` is shared by every worktree of the repo and is not a tracked file
the CLI would be silently rewriting. *Rejected:* editing `.gitignore` (mutates a
tracked file), and leaving it to the developer (a footgun inside the box).

**D5 — a repo carrying an extension the image's git does not know is refused at
`up` and `doctor`**, naming the extension. Today it half-starts and the agent
discovers F5 mid-run. Known-incompatible today: `extensions.relativeworktrees`;
the guard is a list, so `refstorage`, `objectformat` etc. join it when measured.

**D6 — no worktree-management verbs.** `git worktree add` is the native tool and
the developer runs it; devbox only *uses* the result. *Rejected:* `devbox
worktree add` — no behaviour beyond a one-line git call, plus naming and
bookkeeping to own, and no test that git does not already cover.

→ worth an ADR amendment: restated **I1** with its residual (the gitdir of
*sibling* worktrees and `.git/config` become reachable inside a box). Draft in
Appendix A.

## Acceptance criteria

1. `devbox up base <repo>/.devbox/wt/feat-a` succeeds; inside the box `git
   status` reports branch `feat-a`; a commit made inside is visible on the host
   immediately; `devbox down` removes the box and leaves worktree and gitdir
   intact.
2. `devbox up base <repo>` (ordinary checkout) still works with the same three
   mounts; no `/workspace`, and no bind source outside `{worktree, its gitdir,
   its hooks}` appears in the resolved config.
3. `doctor` exits non-zero for a bind outside that set and for a hooks mount
   that is not read-only, and exits zero for a worktree, an ordinary repo, and
   each canonical profile.
4. `doctor` and `up` refuse, with the extension named, a repo carrying
   `extensions.relativeworktrees`; nothing is started and nothing on the host is
   written except the refusal.
5. Two worktrees of one repo run simultaneously: distinct compose project names
   and `.slr` volumes, both containers alive, `down` of one leaves the other.
6. With `devbox policy review-only <worktree>`, `up` yields a box where `git
   commit` fails at the filesystem level, the worktree stays writable, and
   `COMMIT_PROPOSAL.md` is writable; `COMMIT_PROPOSAL.md` written inside is
   visible on the host and the host can stage and commit it.
7. `devbox policy commits-allowed <worktree>` restores committing without
   recreating the image; `devbox policy --list` prints every recorded path and
   mode; an unreadable policy file makes `up` refuse rather than commit.
8. `bin/devbox` creates nothing under a project other than a missing repository
   root or `<gitdir>/info/exclude` (the current `mkdir <project>/.git/hooks` path
   is gone), and `up` on a worktree is re-runnable.
9. Every test in `tests/` passes from a clean tree, and a second consecutive run
   of the same suite passes identically (no leftover containers or volumes:
   asserted by compose-project label, never by global counts).
10. `README.md`, `AGENTS.md` I1 and ADR `0001` state the worktree+gitdir
    boundary; I4's list is unchanged and no `~/.gitconfig` or credential path is
    mounted.

## Budget

**New dependencies:** none. `jq` and `git` were already listed; the host's git must
provide `rev-parse --git-common-dir` (git ≥ 2.5).

| File | Estimated | Delivered (amended, A6) |
|---|---|---|
| `docs/plans/completed/0003-git-worktrees.md` (this file) | ~245 | 327 |
| `bin/devbox` (edit: worktree/gitdir resolution, extension guard, `policy` verb, env) | +75 | +122 (298) |
| `compose/devbox.compose.yaml` (edit: mirrored mounts, `working_dir`, `GIT_OPTIONAL_LOCKS`, RO flag) | +8 / −6 | +11 / −6 (71) |
| `tests/worktree.test.sh` (new: criteria 1, 2, 5, 6, 7, 8) | ~150 | 179 |
| `tests/doctor.test.sh` (edit: gitdir whitelist + extension refusal, criterion 3, 4) | +25 | +23 (123) |
| `README.md` (edit: worktrees, mirrored paths, `policy`) | +40 | +45 (137) |
| `AGENTS.md` (edit: I1 restatement, the measured facts) | +14 | +8 (79) |
| `docs/decisions/0001-sandbox-trust-posture.md` (edit: I1 amendment) | +35 | +35 (92) |
| `profiles/sbcl.yaml` (edit: `.slr` volume under the worktree's own path) | +1 / −1 | +1 / −1 (28) |
| `images/base/Dockerfile` (edit: drop the `/workspace` WORKDIR) | +1 / −1 | +1 / −1 (55) |
| **Total** | **~525–575** | **1,395** |

Application logic ≈ 290 lines (CLI 279, compose 71, profile and image wiring 83,
minus the pre-existing part of each). The estimate under-counted the CLI by 28
lines — the extension guard, the policy reader/writer and the extra refusal
messages — and the growth is recorded rather than absorbed (A6).

## Approach

Small on purpose: one resolution helper, one compose shape, one policy verb,
tests that run the real thing. Ordered so the unverified hypothesis (H1/H2, compose
vs `docker run`) dies first, before anything is built on it.

## Steps

1. **Prove the mount shape through compose** (H1, H2): a throwaway compose file
   with source == target outside the compose dir, `up`, `git status` inside,
   `down`. If it fails, fall back to a per-box generated override file before
   writing any CLI code.
2. Add `resolve_paths()` to `bin/devbox`: `top`, `gitdir`, `common` via
   `rev-parse --show-toplevel` / `--absolute-git-dir` / `--path-format=absolute
   --git-common-dir`; refuse a subdirectory of a worktree (hint: the worktree
   root); refuse unknown `extensions.*` (D5).
3. Replace `ensure_repository`'s hooks `mkdir` with `<gitdir>/hooks`, and add the
   idempotent `<gitdir>/info/exclude` line (D4).
4. Compose: three binds with source == target, `working_dir: ${DEVBOX_WORKTREE}`,
   `read_only: ${DEVBOX_GITDIR_RO:-false}` for the gitdir, hooks RO, and
   `GIT_OPTIONAL_LOCKS=0` in `environment` (F7).
5. `doctor`: whitelist the resolved `{worktree, gitdir, gitdir/hooks}` instead of
   `{project, project/.git/hooks}`; keep every other check and message shape;
   report which paths were allowed in the ok line (so a false pass is visible).
6. `devbox policy <commits-allowed|review-only> <path>` and `--list` (D3);
   `up` resolves the mode and exports `DEVBOX_GITDIR_RO`.
7. Write `tests/worktree.test.sh`; extend `tests/doctor.test.sh`; make both
   suites assert by compose-project label and clean up with `down` + `find
   -delete` under `$HOME`.
8. Exercise criterion 5 by hand with two real worktrees of one scratch repo
   (H4), then fold it into the test.
9. Update `README.md`, `AGENTS.md` I1, and append Appendix A to ADR `0001`.
10. Run the acceptance checklist; report each line pass/fail with the command.

## Verification invariants

- After `down`, no container or volume carrying that compose project's label
  remains (not "N containers exist").
- Re-running `up` on the same worktree yields a working box (idempotence), and
  re-running the whole suite yields the same pass count.
- `git -C <worktree> log` on the host shows the container's commit after `up` +
  commit + `down`; the same assertion holds for a second worktree of the same
  repo.
- The refusal for an unknown git extension happens before any `docker compose
  up` is invoked (assert the message and that no container was created).

## Amendments

**A1 (2026-11-12) — mount shape verified through compose, as designed.** Step 1's
throwaway compose file with source == target outside the compose directory brought
the box up, `git status` reported the branch, a commit in the box appeared on the
host, and the hooks bind refused writes (`Read-only file system`). H1, H2 and H4
are facts; no fallback file was needed.

**A2 (2026-11-12) — two budget rows added that the plan missed.** The `/workspace`
removal reached two files the budget did not list: `profiles/sbcl.yaml` (the `.slr`
volume now targets `${DEVBOX_WORKTREE}/.slr`) and `images/base/Dockerfile`
(`WORKDIR /workspace` → `/root`). Both rows are in the table above.

**A3 (2026-11-12) — the extension guard is a deny-list, and it fires repo-wide.**
Implemented for `extensions.relativeworktrees`, `extensions.refstorage` and
`extensions.compatobjectformat`. Measured consequence: creating one relative
worktree sets the extension on the shared repository config, so `doctor` then
refuses **every** worktree of that repository (`doctor-exit=1` on an unrelated
worktree was observed). Remedy in the message: recreate without relative paths.
A forward fix is a newer git in the image, which would remove the guard for that
extension; not taken in this plan — it is a new image dependency, not a bug fix.

**A4 (2026-11-12) — policy storage as approved, keys are 16 hex digits** of the
worktree's absolute path, file content is mode then path, and an unparsable file
makes `up` and `doctor` refuse (asserted in the suite).

**A5 (2026-11-12) — one bug found by the new suite before sign-off:** `up` exited
1 on a commits-allowed box because its last statement was `[ "$gitdir_ro" = true ]
&& echo …`. Replaced with `if … then … fi`; the suite caught it on the second
worktree and on the post-policy re-up, and both pass now.

**A6 (2026-11-12) — budget amended against delivery, not absorbed:** 1,314 physical
lines against the estimated 525–575, with the CLI 28 lines over its row and the plan
file 37 over. The rows above carry both numbers; the total is the delivered one.

**A7 (2026-11-12) — post-review remediation (findings Q1–Q6).** `git` now runs under
`env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR` (Q1: a stray variable diverted
`--git-common-dir` and `doctor` agreed with the diverted path). The suite's volume
assertion now creates a label-matching probe volume before `down` instead of relying
on a profile that owns none (Q2), and `container()` slugs the name the way the CLI
does, with a dotted-name case covering it (Q5). A `.git` file that git cannot resolve
is refused with `git worktree repair` instead of being initialised over (Q4), and the
exclude entry is written only for trees that host the worktree home (Q6). The git
floor is restated against `--git-common-dir`; step 2's `--path-format=absolute` was
not used — resolution is `--show-toplevel` plus `--git-common-dir` (Q3).

**Verification (2026-11-12).** `tests/doctor.test.sh` → 26 ok, 0 failed.
`tests/worktree.test.sh` → 46 ok, 0 failed after A7 (42 before it), run twice with
the same count and no leftover containers or volumes. Criteria 1, 2, 5, 6, 7, 8 are asserted there;
criterion 3 by the doctor suite (worktree allow-list, sibling bind, hooks RW, missing
hooks); criterion 4 by both suites; criterion 9 by the second run; criterion 10 by
this repository's README, `AGENTS.md` and ADR amendment.

## Open questions

| Question | Recipe |
|---|---|
| Does compose accept source == target with the parents absent in-container? | Step 1 (H1, H2) |
| Does `read_only: ${VAR:-false}` stay boolean through compose *and* the engine? | F7 covers config; step 4 covers runtime |
| Do two compose projects sharing one gitdir interfere? | Step 8 (H4) |
| Does review-only still allow `git status` without index writes? | Step 7 asserts `status` ok and `status` twice is identical |
| Is the git-extension guard list right, or does host 2.56 write other extensions silently? | Inspect `extensions.*` on the scratch repos; extend the list from evidence only |

**Resolved (2026-11-12).** compose accepts source == target outside its own
directory, the parents are created in-container, and the nested hooks bind stays
read-only (A1). Two compose projects sharing one gitdir do not interfere — each box
reported its own branch and `down` of one left the other running (A1, suite "two
boxes on one repository"). Review-only `git status` is clean and repeatable, and
`git add` fails at `index.lock` exactly as designed (suite). The guard list is
evidence-based: `extensions.relativeworktrees` is the only extension host git 2.56
wrote in these fixtures; `refstorage` and `compatobjectformat` are listed because
they are the other post-2.43 extensions, and the plan records that they are
unmeasured here.

## Needs the developer

- **Done:** approval of the restated I1 ("A"), and of the per-project policy-file
  storage change in D3.
- **Remaining:** sign off the plan after `/skill:code-review`, then `0002` may
  start.
- Nothing else: no deploy, no credential, no host file edit.

## Confidence

**98%.** Original 93% rested on two unmeasured mechanisms; both are now measured
rather than argued: compose accepted the mirrored binds and the nested read-only
hooks mount (A1), and two compose projects on one gitdir ran side by side without
interference (suite). The remaining 2%: the guard list is only evidence-backed for
`relativeworktrees` (A3, resolved note), and both suites ran on this machine only —
no CI, no second host.

Step 1 and step 8 ran first, not last, and their results are recorded in the
Amendments rather than assumed.

## Review log

**Review 1 (2026-11-12) — scope: the uncommitted 0003 delta against `f0d0285`.**
Six findings, no critical: a stray `GIT_DIR`/`GIT_WORK_TREE`/`GIT_COMMON_DIR`
diverted `--git-common-dir`, and because `doctor` resolves the same way the
allow-list could not catch the widened mount set; a vacuous volume assertion in the
new suite (base profile owns no volumes) — the `af28d6a` class again; a documented
git floor for a flag the code does not use; a dangling worktree pointer read as
"no repository" (`up` exit 128 at `git init`, doctor naming an impossible
`.git/hooks`); a container lookup that bypassed the CLI's slug; and an
`info/exclude` write for every repository. All six were fixed and re-verified
(A7), and the probes that produced them are now checks: the suite went 42 → 46
assertions, doctor stayed at 26. Independent probes during review also confirmed
hooks stay read-only under a read-only gitdir.

**Sign-off (2026-11-12).** The developer signed the plan off after review and
remediation; it moves to `docs/plans/completed/`.

## Appendix A — ADR `0001` amendment draft (I1 restated)

**Amendment — the container's host boundary is the worktree and its gitdir.**

Context. Support for `git worktree` was scoped in A9.2 as a location decision
(`<project>/.devbox/…`) and never as a mount mechanism. Measurement (0003, Facts
F1–F5) shows a worktree cannot be mounted alone: its `.git` is a file naming an
absolute gitdir outside the worktree, and git rejects a tree whose gitdir is not
reachable. Relative worktrees would avoid the second mount but are unreadable to
the image's git and put the gitdir inside the single writable mount, which ends
review-only enforcement.

Decision. The only host paths mounted into a container are: the worktree (RW), its
gitdir (RW, or RO in review-only mode), and the gitdir's `hooks` directory (RO
always). Each is mounted at its own absolute host path, so git metadata needs no
rewriting and host and box see identical names. The working directory is the
worktree root; `/workspace` no longer exists. I2, I3 and I4 are unchanged: no
Docker socket, no host namespaces or capabilities, no credential or config
directory of the host.

Consequences. A box can read the gitdir's `config` and the metadata of *sibling*
worktrees on the same project — a wider boundary than one folder, but still the
project family, and nothing outside it. Two boxes on one project share one gitdir;
git's own locking arbitrates (per-worktree `index.lock`, shared refs). A repo
carrying a git extension the image's git does not know is unusable, so `doctor`
and `up` refuse it loudly rather than half-starting.
