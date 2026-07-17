---
name: hermes-agent
description: Drive the Hermes agent on smith (192.168.1.61) as a delegate - send it one-shot research/authoring tasks and read its output. Use when Josh asks to run something "through Hermes", for HA config authoring that should go through the git-first pipeline, or for tasks that should burn Hermes's LLM budget instead of this session's. SSH-based; no API key needed on trinity.
---

# hermes-agent — puppet the Hermes agent on smith

Hermes is an autonomous agent (nousresearch/hermes-agent, josh profile) in a
podman container on the smith VM. It has its own LLM keys (OpenRouter/OpenAI,
spend-capped), its own workspace, and its own rules
(`/var/lib/hermes-workspace/WORKFLOW.md` on smith).

## One-shot task (preferred)

```bash
bash .claude/skills/hermes-agent/scripts/run.sh "task text here"
bash .claude/skills/hermes-agent/scripts/run.sh -w home-assistant-config "repo task"
```

Wraps `ssh ansible@192.168.1.61 hermes -z <task>` (or `hermes-in <workspace>
-z` with `-w`, which starts Hermes inside `/workspace/<name>` so that repo's
CLAUDE.md/AGENTS.md auto-load — always use `-w` for tasks on a clone).
Output comes back on stdout. Long agent loops can take minutes — run in the
background rather than guessing a timeout.

## What Hermes has that this session doesn't

- `HA_LIVE_URL`/`HA_LIVE_TOKEN` env: READ-ONLY token (non-admin `hermes-ro`)
  for the live HA box on oracle — entity states, areas, history.
- `HA_DEV_*` env + `/workspace/ha-dev-config`: full control of the dev HA
  instance on smith:8124 (its proving ground).
- `/workspace/home-assistant-config`: clone of the private HA config repo
  with a write deploy key — it pushes `hermes/*` branches for Josh to review.
- Its own spend-capped LLM budget (OpenRouter routes MiniMax/Qwen/etc.).

## Rules for the puppeteer

- Hermes executes arbitrary shell IN ITS CONTAINER. Its blast radius is the
  smith VM by design — do not hand it credentials, and do not ask it to
  target other hosts directly (it has no access; that's intentional).
- For HA changes, phrase tasks so it follows its WORKFLOW.md (branch → prove
  on dev → push with evidence). Never ask it to push to main or write to the
  live HA box.
- Remind it "read-only / GET only" when a task touches the live HA API.
- If a task 402s, Hermes's OpenRouter credit cap is exhausted — tell Josh;
  don't swap in other keys.
- Model/routing tweaks: `hermes chat --provider openrouter --model '<id>'`
  works too (interactive; the `-z` one-shot uses the profile default).

## Other access paths (humans)

- Dashboard/chat: http://192.168.1.61:9119 (basic auth `josh`).
- OpenAI-compatible API: http://192.168.1.61:8642/v1 (Bearer =
  `secret_hermes_josh_api_server_key`, model `hermes-agent`) — for
  programmatic use where SSH isn't available; key must come from Josh, never
  from the vault file.
- Trinity shell aliases: `hermes` (interactive chat), `hermes-run` (one-shot).
