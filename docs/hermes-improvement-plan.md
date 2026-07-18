# Hermes improvement plan

Goal: make the Hermes delegate on smith complete real infra tasks with
minimal wasted turns/tokens, without weakening the "no live-system access"
security model. Grounded in the 2026-07-17 clear-alerts pilot: three runs,
where #1 and #2 burned most of their budget on environment discovery and
permission walls, and #3 — after the fixes below — finished end-to-end for
**$0.29 / 78 API calls** with a merged, deploy-ready PR.

## Baseline (what's already in place, 2026-07-17)

| Layer | Mechanism |
|---|---|
| Context injection | `AGENTS.md` per repo (auto-loaded from cwd), `hermes-in`/`run.sh -w` guarantee cwd |
| Rules | `workspace-WORKFLOW.md` in git → ro-mounted at `/workspace/WORKFLOW.md`; turn-discipline section (no archaeology, two-strikes blocker rule, behavioral test bar) |
| Deterministic tools | `/workspace/bin/ha-dev` (ro mount): auth+cache, check/reload/restart/deploy/seed/state/logbook/errors |
| Write boundary | `HERMES_WRITE_SAFE_ROOT=/opt/data:/workspace`; everything else denied in-tool |
| Ownership | uid-10000 alignment via tmpfiles (`Z` workspace, ACLs on ha-dev config, deploy key 0400) |
| Cost visibility | `run.sh` passes `--usage-file`, echoes per-run usage JSON to stderr |
| Access model | HA repo: branch push via deploy key; nas-infra: pull-only; live systems: read-only or nothing |

## P0 — do soon (prevent regressions, close real gaps)

1. **Pin the hermes-agent image.** `:latest` moved under us mid-week and
   silently broke all workspace writes (`HERMES_WRITE_SAFE_ROOT` default
   change). Pin a digest in `configuration.nix`; let Renovate propose bumps
   (it already watches compose `.j2` files — add a regex manager for the nix
   file). Test each bump with a canary one-shot before merging.
2. **Branch-protect `home-assistant-config` main.** The deploy key can push
   to main; only convention stops Hermes. A GitHub ruleset (block direct
   pushes to `main`, allow `hermes/*`) turns the rule into a guarantee.
   **BLOCKED 2026-07-17: rulesets/branch protection on private repos
   require GitHub Pro** (attempted via API, 403). Options: upgrade, make
   the repo's protection moot by rotating to a read-only deploy key +
   trinity-side pushes, or accept convention + review as the control.
3. **Keep dev HA pinned to oracle's Core version.** Oracle auto-updated to
   2026.7.2; dev is pinned 2026.7.1. Add a checklist line to the
   HA-upgrade routine (or a Renovate-style reminder) to bump
   `ha-dev` image + `make smith` together with Green updates.
4. **Canary task in the loop.** A tiny scripted one-shot ("read AGENTS.md,
   run ha-dev check, git fetch, report OK") run after every `make smith` /
   image bump — catches the next uid/env/mount regression in one minute
   instead of mid-task. Wire as `scripts/canary.sh` in the hermes-agent
   skill.

## P1 — efficiency (turns and tokens)

5. **Hermes-oriented `AGENTS.md` for nas-infra.** The repo's AGENTS.md is
   written for trinity agents. Add a short "For Hermes on smith" section:
   what it can't do here (no ansible, no make targets, no deploys), the
   local-branch handoff flow, and a pointer to `docs/ports.md` for port
   picks. Keeps sessions from re-testing capabilities.
6. **`compose-check` tool.** Attempt-independent risk: compose `.j2` edits
   have no CI. A `/workspace/bin/compose-check` (ro mount) that renders a
   service's Jinja2 with stub vars and runs `python -c yaml.safe_load`
   gives Hermes a deterministic validity check — same shape as `ha-dev`.
7. **Trim context spend.** Session cache reads were 3.9M tokens (97% of
   total) for one task. Biggest lever: shorter injected context. Audit what
   gets injected (SOUL.md, memory, skills snapshot — `/opt/data/
   .skills_prompt_snapshot.json` is 43KB) and disable preloaded skills that
   never fire on infra tasks (`--skills` allowlist or profile config).
8. **Per-task model routing.** minimax-m3 handled authoring+testing well.
   Route mechanical tasks (renames, tag bumps) to a cheaper model and keep
   m3 for authoring, via `--model` in `run.sh` presets; revisit after a few
   usage-file datapoints.
9. **Turn-budget telemetry.** Extend `run.sh` to log usage JSON per run to
   `~/.local/state/hermes-runs.jsonl` on trinity (task text hash, cost,
   api_calls, duration) so efficiency claims are measured, not vibes.

## P2 — capability (bigger wins, more design)

10. **nas-infra push via deploy key** (mirroring the HA repo pattern) once
    the local-branch handoff gets annoying. Requires the same branch
    protection first (nas-infra main is the deployable trunk).
11. **PR creation from trinity, not smith.** Hermes hands back PR text;
    a small trinity-side script (`gh pr create` with its body) closes the
    loop without giving smith any GitHub token.
12. **Phase-3 gated deploys** (from HERMES-WORKFLOW.md): Semaphore template
    wrapping oracle-push that Hermes may *trigger*, with a pre_task
    verifying the deployed commit is PR-approved by Josh. Agent controls
    when, never what.
13. **Sandbox the API server path.** Gateway log warns: API server on
    0.0.0.0 with unsandboxed local terminal backend. LAN-only today, but
    consider `terminal.backend: docker` or firewalling 8642 to trinity's IP.
14. **Dashboard session stability.** Set
    `HERMES_DASHBOARD_BASIC_AUTH_SECRET` (vault) so sessions survive
    restarts — minor UX, one vault var.

## Implementation status (2026-07-17)

Done: P0.1 digest pin + Renovate regex manager; P0.3 dev HA → 2026.7.2;
P0.4 `canary.sh`; P1.5 nas-infra AGENTS.md Hermes section (+ AGENTS.md/
CLAUDE.md now committed so clones actually receive them); P1.6
`compose-check` ro-mounted; P1.8 `run.sh -m`; P1.9 telemetry →
`~/.local/state/hermes-runs.jsonl`; P2.11 `pr-create.sh`.
Blocked: P0.2 (needs GitHub Pro). Open: P1.7 context trim, P2.10/12/13/14.

## Non-goals

- No vault key, no live-system writes, no sudo for Hermes — the VM boundary
  and human-gated deploys are the product, not friction to optimize away.
- No always-on autonomy (cron/kanban) until the canary + pinning layers
  have soaked.

## Success metrics

- Cost/turns per completed task trending down (from usage-file telemetry;
  baseline: $0.29, 78 calls for clear-alerts).
- Zero runs lost to environment/permission walls (attempt #1 and #2 class).
- Every guardrail change validated by the canary before a real task hits it.
