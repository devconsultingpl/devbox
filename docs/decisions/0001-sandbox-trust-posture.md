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
