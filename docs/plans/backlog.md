# Deferred work

Entries here are decisions already made or options already assessed, parked
deliberately. Promote an entry to a numbered plan (`NNNN-<slug>.md`) before
working it.

## Gondolin as a second runtime (deferred by explicit decision)

**What.** `earendil-works/gondolin` — "Local Linux micro-VMs with programmable
network and filesystem control". Apache-2.0, by the pi authors, and the pi repo
ships a Gondolin extension that routes pi's built-in tools into a micro-VM with
the project mounted at `/workspace`.

**Why it is wanted.**

- **Native egress allowlists with request hooks.** This is the control that plan
  `0001`'s threat-model row **T3** explicitly leaves unaddressed, and the reason
  `D6` forbids cloud-reachable credentials in the Docker runtime. An egress
  allowlist makes a remote action *impossible* even if a credential leaks.
- **Host-side secret injection via placeholders** — the real credential never
  enters the guest, so a prompt-injected agent cannot read it out of a config
  file.
- **Per-task microVMs** with snapshot/rollback, attach, ingress, and SSH.
- Programmable VFS mounts, so the "one folder, nothing outside" contract could be
  expressed as policy rather than as a mount list.

**Why it is deferred, not first.**

- The image it needs is the **same** Dockerfile `0001` produces: Gondolin's
  `oci.image` build option takes an OCI image as the rootfs base, so the
  toolchain work is shared and nothing is re-done. Sequencing Docker first costs
  nothing.
- It is self-described experimental, and the pi integration is an **example**
  extension (a local ~16 KB file) rather than a supported package — adopting it
  means owning a fork of that file.
- Custom image builds add real steps and their own troubleshooting surface
  (`gondolin build`, `lz4`/`e2fsprogs` host tools, image size limits).

**Entry conditions.** Promote this when either becomes true:

1. A project needs cloud/remote access — that requires an egress allowlist, which
   the Docker runtime has no way to provide.
2. `0001` and `0002` have landed and the local-only constraint has become the
   limiting factor rather than a safety feature.

**Starting points for that plan.** `gondolin build --init-config` → set
`oci.image` to the `0001` image → `gondolin build --config … --output` →
`GONDOLIN_GUEST_DIR`, or `sandbox: { imagePath }` in the extension's `VM.create`
options. See Docker's docs for the SBX comparison this decision rejected, and
pi's `docs/containerization.md` for the routing-extension pattern.

## Not planned

- **Docker Sandboxes (`sbx`).** Free for commercial use, but proprietary with a
  mandatory Docker OAuth account, and its kit format is explicitly experimental.
  Rejected against the "no external commercial tools" constraint — not on price.
- **OpenShell.** Requires a gateway; assessed and set aside as heavier than the
  problem.
- **Outbound push notification (ntfy/email/Slack).** Optional add-on to `0002`'s
  host-side watcher. Kept out of the default path so a purely local operation
  does not acquire a third-party dependency in its critical path.

## slr as our codemode (research, deferred)

**What.** pi's `codemode` is a QuickJS sandbox where the model writes JavaScript
that calls `tools.<name>(...)` and non-LLM models, and only the script's output
reaches the model (`pi-coding-agent/docs/codemode.md`). Our counterpart is
`smart-lisp-repl` (present in the checkout as `packages/pi-slr-service`, not yet
registered in the box), which is a
Lisp evaluation service rather than a scripted orchestration surface.

**Assessment.** Not equivalent today: slr gives the agent a REPL to evaluate in,
but no `tools.*` / `models` bridge and no sandbox contract that says what reaches
the model. The equivalence would be a pi extension exposing tools and non-LLM
models as Lisp forms inside the REPL, plus a result-shaping rule.

**Promotion condition.** Promote to a plan when a task actually needs scripted tool
orchestration with large intermediate results filtered outside the model context,
or when `pi-slr-service` grows a tool bridge. Until then the workstation image
(`0004`) ships slr as a tool, not as codemode.
