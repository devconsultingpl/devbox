# 0001 — Sandbox trust posture: isolate by container, control by capability

**Status:** accepted (2026-09-26). Filed from `docs/plans/completed/0001-devbox-runtime.md`
(Appendix A); the plan is the specification, this file is the durable *why*.

## Context

Two incidents on this machine drove the design: an agent **deleted a production
AWS stack**, and an agent **damaged host global state** — shell config,
application config, the Homebrew prefix — badly enough that the environment had to
be rebuilt.

The mitigation in place at the time was a permission extension on the host
(`pi-permission-system`: `bash: {"*": "ask"}`, `rm -rf *: deny`,
`external_directory: ask`). It produced continuous prompts and prevented neither
incident, because pattern-matching bash *text* gates neither remote effects nor
files the host later executes. A prompt is a question, and both incidents were
answered "yes" — by inattention, not by intent.

## Decision

Isolate by container; control by capability, not by prompt.

1. **The container's filesystem is the host-filesystem boundary.** Global host
   paths are unreachable by construction, not by policy: `~/.zshrc` is not a
   writable file in the box, it is not a file at all.
2. **Inside the box, permissions are fully permissive** — the permission extension
   is deliberately *not* installed. The boundary replaces the prompt, and unlike
   the prompt it does not depend on a human being awake, present or right.
3. **Mounts: the project read-write, `.git/hooks` read-only.** Hooks are the one
   file class in a workspace that escapes into automatic host execution, and
   `.git diff` does not show them. Installing software inside the box is free;
   *reshaping* the box is a host-side edit.
4. **Remote blast radius is controlled by credential absence**, later by an egress
   allowlist — never by the runtime, never by a prompt. A project that genuinely
   needs cloud access gets a scoped identity: one approval on a destructive call is
   permanent, which is exactly how the AWS incident class works.
5. **Every host-trusted config file resolves from this repo**, never from a mounted
   workspace. The workspace is where an agent writes; the repo is what the host
   trusts.

## Consequences

Autonomy becomes genuinely unattended for local work: the failure modes that matter
are absent rather than gated. Two costs are accepted deliberately.

- **Cloud work is unavailable here** until an egress layer exists — see the
  Gondolin entry in `docs/plans/backlog.md`.
- **Enforcement lives in invariants that must be checked** (`devbox doctor`, I1–I6
  in `AGENTS.md`) rather than in a dialog a human reads.

Named residuals, not hidden ones:

- `.git/config` stays writable (ordinary commit work needs it), so a determined
  agent could repoint `core.hooksPath` into the workspace; a hooks-path check
  belongs in `doctor`.
- A project handed a prod-capable credential has the same blast radius as before,
  regardless of this runtime.
- Damage to *local project files* (T2) is accepted by explicit decision, and
  nothing inside the box stops an agent from being wrong within the project.

Neither accepted cost is mitigated by tightening the container. Revisit this ADR
when the egress layer lands, or if either residual is assumed solved by the sandbox
alone.

## Amendment (2026-11-12) — I1 restated: the worktree and its gitdir

**Context.** Worktree support was scoped in plan `0001`'s A9.2 as a location
decision (`<project>/.devbox/…`) and never as a mount mechanism. Measurement
(plan `0003`, facts F1–F5) shows a worktree cannot be mounted alone: its `.git`
is a file naming an absolute gitdir outside the worktree, the gitdir's backlink
points back absolutely, and git rejects a tree whose gitdir is unreachable.
Relative worktrees would avoid the second mount but are unreadable to the image's
git (`unknown repository extension found: relativeworktrees`) and place the
gitdir inside the single writable mount, which ends review-only enforcement.

**Decision.** The only host paths mounted into a container are: the worktree
(read-write), its gitdir (read-write, or read-only under the review-only
policy), and the gitdir's `hooks` directory (read-only always). Each is mounted
at its own absolute host path, so git metadata needs no rewriting and host and
box resolve identical names; the working directory is the worktree root and
`/workspace` no longer exists. I2, I3 and I4 are unchanged: no Docker socket, no
added capabilities or host namespaces, no host credential or config directory.

**Consequences.** A box can read the gitdir's `config` and the metadata of
*sibling* worktrees on the same project — a wider boundary than one folder, but
still the project family, and nothing outside it. Two boxes on one project share
one gitdir; git's own locking arbitrates (per-worktree `index.lock`, shared refs
and objects). A repository carrying a git extension the image's git cannot read is
unusable, so `doctor` and `up` refuse it loudly rather than half-starting. The
hooks-path residual above is unchanged: `.git/config` stays writable, and `doctor`
checks that the hooks *mount* is read-only, not that `core.hooksPath` points at it.

## Amendment (2026-11-16) — I5 restated: the model credential is proxy-scoped, never box-resident

**Context.** I5 reads "No cloud-reachable credential in this runtime (no egress layer
yet)". An unattended agent cannot work without a model, and a model needs a credential —
read literally, I5 forbids the one credential the runtime exists to use. Measurement
(plan `0002`, slice 1) shows exactly where it bites: under a detached tmux a `/wf` run
starts, completes stage 1, writes its audit trail, and stops at "No API key found for the
selected model".

**Decision.** I5 is restated, not weakened: **no credential that reaches cloud
infrastructure is present in a box.** A model credential is permitted only when all three
hold — it lives on the host (macOS Keychain), it is read by a host-resident process (a
loopback proxy), and what the box carries is a single-purpose token the provider itself
rejects. Everything else stays forbidden: AWS, GitHub, SSH, npm credentials, a mounted
`~/.aws`, a key in an image layer.

**Consequences.**
- The box can think without holding anything worth stealing; a leaked box token costs at
  most that box's model budget.
- The proxy joins `up`'s critical path and the host's trust surface: it holds the key in
  memory and must never log it. A host session the policy does not constrain can still
  read the Keychain item — the developer's machine-level boundary, named rather than
  papered over.
- A future egress layer (backlog: Gondolin) can replace the proxy without touching the
  rule, because the rule is about reachability, not mechanism.
- I4 is unchanged: `~/.pi`, `~/.aws`, `~/.ssh`, `~/.config/gh`, `~/.docker` remain
  unmountable.
