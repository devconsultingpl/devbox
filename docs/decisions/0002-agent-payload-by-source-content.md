# 0002 — The box's agent tools are identified by source content

**Status:** accepted (2026-11-13). Filed from
`docs/plans/completed/0004-agent-workstation.md`
(Appendix A); the plan is the specification, this file is the durable *why*.

## Context

The agent workstation has to carry **the current state of our own projects** —
`pi-extensions` and `skillset` as they are on this machine, including work that is
uncommitted — while staying reproducible and auditable. Two obvious answers each
fail: an npm pin cannot carry unreleased code, and floating `@latest` installs
make two boxes built a day apart incomparable while putting the network in the
path of every `up`. The alternative to both is to build from the checkouts, which
raises the question this record answers: *what identifies what got baked in?*

## Decision

1. The payload is built from the two local checkouts, overridable through
   `PIEXT_REPO` and `SKILLSET_REPO`.
2. `up` materialises each into a build context by git's own include rule —
   `git ls-files --cached --others --exclude-standard`, working-tree content — so
   a dirty tree ships and an ignored file never enters an image.
3. A **content stamp** identifies the result: per source, its commit plus a digest
   of the materialised file set, written into the image
   (`/opt/devbox/agent/SOURCES`, label `devbox.agent.stamp`) and printed by
   `devbox doctor`.
4. `up` rebuilds exactly when the stamp moves, and only then. A change to this
   repo's own Dockerfiles or harnesses is outside the stamp and needs `--rebuild`.
5. The payload is **harness-gated**: a profile whose harness is `none` carries no
   agent, no browser and no `/root/.pi`.
6. Inside the box, permissions are explicit allow-all — an `ask` in an unattended
   session is a stall — for the same reason ADR `0001` gives: the boundary, not a
   dialog, is what isolates the work.

## Consequences

- A box is reproducible together with its stamp and current by construction. Two
  builds of the same content produce the same stamp; a dirty edit, an added or a
  deleted file moves it; an ignored file does not.
- The stamp says *what content* was installed, not *which registry versions*
  resolved. `pi-extensions` therefore installs with `npm install`, not `npm ci`:
  a workspace member added but not locked — the ordinary dirty tree this decision
  exists to ship — makes `npm ci` refuse. Reproducibility rests on the stamp.
- Cost accepted: image size and build time (2.03 GB, ~2 min cold at the time of
  writing), and the discipline of keeping the two checkouts present on any machine
  that builds an agent profile. A `none` profile builds without them.
- A future restricted box narrows the same canonical permission file instead of
  inventing a second mechanism, and a future harness is one more script consuming
  the same payload directory.
