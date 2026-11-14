# 0002 — `devbox` orchestrator: brief in, review-ready artifact out

## Status: proposed — depends on `0001` (runtime)

## Goal

One command that takes a free-text brief and works autonomously until the result
is ready for review, then tells you — so that "I'll review it when I get back"
replaces "I have to watch and approve every minute".

```console
$ devbox work myapp        # starts the session, hands it the brief
$ devbox watch myapp &     # host-side; notifies on completion or escalation
# …walk away…
# attach whenever:  devbox attach myapp
```

The brief carries what you already provide: what to build, what it should look
like, references to draw inspiration from, and the acceptance criteria.

For an unattended local project, `0001` makes this safe: the agent cannot reach
host global state, and cannot reach remote infrastructure because it has no
credential for it. This plan supplies the autonomy.

## What already exists — do not rebuild

The orchestrator is an **assembly** task. Most of the machinery is installed and
already exercised in the `flow` / `flow-workflow` / `pi-subagents` packages.

| Requirement | Existing mechanism |
|---|---|
| judge whether it is done, and learn from the judge | `assess({ judge, done, feedForward })` — producer→judge rounds until `done(verdict)`, with the verdict's feedback folded into the next round |
| acceptance criteria as the bar | the brief stage **produces** a criteria artifact; the judge's `verdictOutcome` parses a verdict that reads against it |
| several reviewers disagreing | `panel()` — N adversarial judges composed into one verdict that the same `done` reads |
| "manages other agents and their sessions and findings" | `pi-subagents`: `subagent`, `get_subagent_result`, `steer_subagent`, `resume`, per-stage child sessions under `runs/<run-id>/sessions/`; findings travel as artifacts and `state.named` channels |
| "tried several times, just doesn't know how" | `max` + `onCap` (`"halt"` = terminal failure, `"advance"` = soft-stop with a `{type:"loop-cap"}` row and `onLoopCap`); run backstops `maxIterations` 32, backward-jump budget 3 per stage |
| resumability / audit | append-only JSONL per run; `/wf @<run-id>` |
| the stages themselves | the existing FLOW skills (`plan`, `implement`, `validate`, `code-review`) with their declared contracts — wired, not rewritten |

## The constraint that shapes the design

**`/wf` refuses to run non-interactively** (`Non-interactive session → /wf requires
interactive mode`). Every mechanism in that table is behind `/wf`. Pi's own README
endorses the workaround for exactly this situation: *"Spawn pi instances via
tmux, or build your own with extensions, or install a package that does it your
way."*

So: **an interactive pi runs inside a detached tmux session in the container.**
Nothing about the run requires input, so "unattended" is a property of the
workflow, not of the terminal. `devbox attach` reconnects; `--mode rpc` and the
SDK remain available later if a session-shaped orchestrator becomes the
limitation.

## Completion and escalation

The container's network is outbound-only, but the project directory is a bind
mount — so a file written inside the container is visible on the host instantly,
with no network, no account, and no third-party service.

- **Success** → the terminal stage writes `READY-FOR-REVIEW.md` (what was built,
  how to review it, which criteria were verified, and the run id).
- **Exhaustion** → the cap fires and the same terminal stage writes `BLOCKED.md`
  (attempts made, the judge's last feedback, what it could not satisfy). This is
  the rare path you described, and it is a first-class outcome rather than a
  silent stop.
- **`devbox watch <project>`** watches for either file and raises a host
  notification (`osascript`). Optional outbound push (ntfy/email) is a later
  add-on for when you are away from the machine.

## Acceptance criteria

1. `devbox work <project> "<brief>"` starts a detached tmux session in the
   `0001` container with an interactive pi, and proceeds without any further
   input; `devbox attach <project>` reconnects to it.
2. A run of the `deliver` workflow with a brief containing acceptance criteria
   reaches a terminal artifact without any human input.
3. Exactly one terminal artifact lands in the project directory:
   `READY-FOR-REVIEW.md` on success, `BLOCKED.md` on exhaustion — never both,
   never neither.
4. `devbox watch <project>` raises a host notification when a terminal artifact
   appears and raises none for intermediate artifacts.
5. The exhaustion path is exercised by a deliberately unsatisfiable brief: the
   run stops within the configured caps, `BLOCKED.md` records the attempt count
   and the judge's last feedback, and no unbounded retry occurs.
6. Judge verification reads the **brief's criteria artifact**, not a generic
   quality bar: the verdict for a deliberately-failing criterion is negative
   while the same artifact passes every other criterion.
7. Run caps are explicit and documented: assess `max` and `onCap`, run-wide
   `maxIterations`, and the backward-jump budget.
8. Audit trail present: `.flow/workflows/runs/<run-id>.jsonl` plus child sessions
   under `runs/<run-id>/sessions/`, and the completion artifact cites the run id.
9. The workflow definition resolves from the container's user-level config, and
   the completion artifact records the workflow's name and a hash of the
   resolved definition — so a project-level override of the same workflow name
   is **visible**, not silent.
10. `README.md` documents attach, inspect, resume (`/wf @<run-id>`), and what to
    do with a `BLOCKED.md`.

## Budget

**New dependencies:** `tmux` (installed in the image), and the already-public
`@joozik/flow`, `@joozik/flow-workflow`, `@joozik/pi-subagents` npm packages (the
local package name; `@gotgenes/pi-subagents` was a stale reference).
No host-side dependency beyond a shell and `osascript`.

| File | Est. physical lines |
|---|---|
| `docs/plans/0002-devbox-orchestrator.md` (this file) | 233 |
| `workflows/deliver.ts` (the graph) | 120 |
| `workflows/outcomes.ts` (verdict + criteria outcomes) | 60 |
| `harnesses/pi.sh` (edit: tmux, flow packages, user-level workflow config) | +25 |
| `bin/devbox` (edit: `work`, `attach` subcommands) | +70 |
| `bin/devbox-watch` | 70 |
| `tests/orchestrator.test.sh` | 80 |
| `README.md` (edit: the walk-away loop) | +60 |
| **Total** | **~700–760** |

Application logic ≈ 340 lines (workflow graph, outcomes, watch, devbox edits).
Growth beyond ~760 without an updated budget is a spec violation.

## Decisions

**D1 — Driving mode: interactive pi in a detached tmux session inside the
container.** The only route that keeps `/wf` and therefore every mechanism in the
table above. *Rejected:* `--mode rpc` — the orchestrator becomes a program you
maintain, and the judge/loop/cap machinery would have to be rebuilt by hand.
*Rejected:* the SDK — most control, most work, and it largely bypasses
`flow-workflow`; the right answer only if this is ever productized.

**D2 — The workflow composes existing FLOW skills as stages**, with contracts
analyzed before wiring rather than new prompts written. The graph is small: a
stage that turns the brief into a criteria artifact, an implement stage, an
`assess` verify stage whose judge reads those criteria, and a terminal report
stage. *Rejected:* writing bespoke stage prompts — duplicating skills that
already declare what they consume and produce, and drifting from the pipeline
you already use interactively.

**D3 — Verification by `assess` + `panel` against the criteria artifact.**
Multiple criteria get multiple judges composed into one verdict that `done`
reads, so a partially-met brief reads as partial rather than as pass/fail.
*Rejected:* a single self-review pass — self-grading against one's own summary is
the weakest possible check and would make the whole "walk away" premise
unearned.

**D4 — Completion is a file on the bind mount, watched from the host.**
*Rejected:* an outbound push service as the default — it adds an account and a
third party to the critical path of a purely local operation. Kept as an opt-in
addition for off-machine notification.

**D5 — Escalation is bounded and first-class.** Caps produce `BLOCKED.md` with
the attempt count and the last feedback. *Rejected:* unbounded retry — burns
tokens, and a run that cannot succeed should surface as such rather than as
silence.

**D6 — The workflow graph is tamper-evident, not tamper-proof; human review is
the real gate.** The definition ships in the container's user-level config, and
the completion artifact records its name and hash. *Rejected as the primary
control:* read-only mounts on the project's `.flow/workflows/config.ts` and
`packs/` — brittle, because run state must stay writable in the same directory,
and it does not help if the definition is rewritten elsewhere. Note the honest
limit: a project-level file can override the workflow by name, so a rewritten
graph could make the judge lenient. That is acceptable *only* because you review
the result yourself — the judge is a convenience, not a security control, and an
artifact whose graph hash does not match the shipped one tells you the run is
not self-certifying.

→ worth an ADR: "the judge is advisory, the human is the gate" — to be drafted
during implementation if `D6`'s hash check proves load-bearing in practice.

## Approach

Four slices, ordered so the unverified mechanism is tested first.

**Slice 1 — prove the unattended loop by hand.** In the `0001` container:
`tmux new -d 'pi'`, submit a trivial `/wf` run, confirm it proceeds with no
input, and confirm the audit trail and child sessions land. **If `/wf` cannot
run under tmux without a TTY, stop and reconsider D1** — the fallback is
`--mode rpc`, which changes this plan's shape.

**Slice 2 — author the graph.** Analyze the contracts of the existing skills
before wiring (`flow-workflow`'s "analyzing skills before wiring" path), then
write `workflows/deliver.ts` + outcomes.

**Slice 3 — notification.** Terminal artifact + `devbox-watch`.

**Slice 4 — escalation.** Exercise the cap path with an unsatisfiable brief;
tune `max`/`onCap` so the failure arrives in minutes, not hours.

## Steps

1. **Unattended proof (slice 1).** tmux + `/wf` inside the container, no input,
   audit trail confirmed.
2. Analyze skill contracts for the stages to be wired; record the analysis.
3. Write `workflows/deliver.ts` + `workflows/outcomes.ts`; install the workflow
   into the container's user-level `flow-workflow` config.
4. Wire tmux + the flow packages into `harnesses/pi.sh`.
5. Add `work`/`attach` to `bin/devbox`; write `bin/devbox-watch`.
6. Exercise the success path end to end on a scratch project; confirm exactly one
   terminal artifact and one notification.
7. Exercise the exhaustion path (slice 4); confirm caps, `BLOCKED.md` content,
   and no runaway.
8. Add the graph-hash check for criterion 9.
9. Update `README.md`.
10. Run the acceptance checklist; report each line pass/fail.

## Open questions

| Question | Recipe |
|---|---|
| Does `/wf` run under tmux with no TTY attached? | slice 1 step 1. Fallback: `--mode rpc` redesign. |
| Does a detached tmux session survive `docker compose` restarts? | stop/start the container with a run in progress; check the trail. |
| Does the flow runtime resolve the user-level config inside the container? | confirm the container's `$XDG_CONFIG_HOME`/`~/.config/flow-workflow/` path. |
| Can a project-level `.flow/workflows/config.ts` override the shipped workflow by name? | Expected **yes** (later layers win by name) — that is exactly what criterion 9 makes visible. Verify and record. |
| Do the FLOW skills' declared contracts compose cleanly with the stages? | The contract adjudicator runs at load time; a `canCompose` failure is the signal. |
| How long does a realistic run take, and are the caps right? | Time the success and exhaustion paths on a scratch project; adjust `max` and `maxIterations`. |
| Does `osascript` notification work while the terminal is not focused? | Fire manually from the watcher; check Notification Center settings. |

## Amendment (2026-11-12) — the supervisor shape the developer described

Recorded, not yet designed. It changes the graph this plan assumed, so **step 2
("author the graph") does not start until the first question below is answered.**

The loop, as specified:

1. A supervisor runs inside the box and **decomposes the plan into tasks** by
   invoking a dedicated agent with its own instructions, prompt and skills.
2. Per task: a **builder** subagent implements it; a **reviewer** subagent judges
   whether the change is done well and fulfils that task completely; the builder
   applies the corrections; the next task follows. Only when the whole plan is
   done does the run leave the task loop.
3. Then **one more demanding review** at run scope — security, correctness,
   alignment with the plan, and a simplification pass: if the same behaviour is
   achievable with less code, and in a safer or more reliable way, prefer it
   (a lens, not a fetish for deletion).
4. That final review plus its corrections may run **at most twice**; then the run
   terminates with `READY-FOR-REVIEW.md` or `BLOCKED.md` as already specified.

What this supersedes, subject to the design pass:

- **D2** assumed the graph composes the FLOW stage skills verbatim; the described
  loop is task-level with a paired builder and reviewer, which is a different
  contract from a single implement stage.
- **D3** made `assess`/`panel` the verification engine over a criteria artifact.
  That may remain the reviewer's engine, but the *unit* becomes a task, and a task
  needs its own done-predicate and its own cap. The first design question is
  therefore: **is the per-task reviewer an `assess` round, or a separate stage
  with a task-scoped verdict?**
- The completion contract, escalation artifacts and the tmux driving mode (D1) are
  unaffected; `0004` (proposed, implemented, not yet signed off) would supply the
pi + flow + skillset payload they assume.

New constraints this amendment adds, to be designed rather than assumed:

- Tasks must be **persisted on the bind mount** (one file per task, with state), so
  the host can see progress and a resumed run can tell what was finished.
- Every loop needs a **per-task cap** as well as the run-wide one, or one
  unachievable task consumes the whole run.
- The final two-round cap must be **recorded in the artifact**, including which
  round produced the accepted state.
- The builder/reviewer pairing is where **subagent sessions multiply**; the
  sessions directory and the caps have to be counted per task, not per run, or the
  audit trail stops describing what happened.

Open questions this amendment creates (each needs a measurement before it is
designed in): does `pi-subagents` expose a per-child verdict cleanly enough to be a
task's done-predicate; does the skillset payload's builder/reviewer skills already
define that contract; how does a task file survive a container restart; and what
does a task-level `BLOCKED.md` look like when tasks 1–3 succeeded and task 4 did
not.

## Confidence

**94%.** The design rests on mechanisms that are documented and already in use
(`assess`/`panel`/caps, `pi-subagents` sessions), so the assembly risk is low.
The residual is concentrated in one place: **criterion 1's assumption that an
interactive `/wf` run proceeds under a detached tmux session with nobody
attached.** That is documented behaviour in the sense that processes need no TTY
to run, but it is not something the `flow-workflow` docs state explicitly, so
slice 1 tests it before anything is built on it, with `--mode rpc` named as the
fallback that would change this plan's shape.

I am deliberately not at 98% here, because the honest statement is that this
plan has one load-bearing mechanism I have not yet observed.

## Review log

_Empty — populated by `/skill:code-review` after implementation._
