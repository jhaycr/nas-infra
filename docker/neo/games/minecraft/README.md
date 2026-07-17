# Minecraft stack

Two stacks work together:

- `docker/neo/games/minecraft-proxy/` — Velocity proxy + Geyser (Bedrock/iPad support) + Floodgate, exposed over Tailscale.
- `docker/neo/games/minecraft/` (this dir) — three Paper backends behind the proxy: `minecraft-lobby`, `minecraft-survival`, `minecraft-pvp`.

## Version pins

All versions across both stacks are pinned in one place: `group_vars/neo/vars.yml` under `minecraft_versions`. Nothing in either compose template references `latest` — every Velocity build, Geyser/Floodgate build, Paper version, and ViaVersion/ViaBackwards/ViaRewind version is an explicit value read from this dict. This is deliberate: Velocity, Geyser, and Floodgate all bundle their own copy of the Adventure text library, and a stale/rolling combination of them silently breaks Geyser at startup with a `NoSuchMethodError` (no UDP 19132 listener, no error visible until someone tries to connect — this happened in July 2026 and took a while to diagnose).

## Bringing in a new version

Never hand-edit a version number directly in the compose templates or bump `minecraft_versions` in `group_vars/neo/vars.yml` without validating the combination first — Velocity/Geyser/Floodgate compatibility is not guaranteed just because each project shows a "latest" build.

1. Check current pins vs. what's available upstream:
   ```
   make minecraft-check-versions
   ```
2. Smoke-test the exact combination you're considering, in a disposable local container (no changes to `neo`, no repo edits):
   ```
   make minecraft-check-versions ARGS=--test-latest
   ```
   This spins up a throwaway `itzg/mc-proxy` container with the newest available Velocity/Geyser/Floodgate builds and a throwaway `itzg/minecraft-server` (Paper) container with the newest Via* jars, waits for a clean boot, and prints PASS/FAIL. It always tears its containers down when done, whether it passes or fails.
   - `PASS` for the proxy looks like `Started Geyser on UDP port 19132` in the logs.
   - `FAIL` means a `NoSuchMethodError` / `Couldn't pass ListenerBoundEvent` / plugin-disable error — do not apply these versions.
3. Only once `--test-latest` passes, apply the validated combination:
   ```
   bin/minecraft-check-versions.sh --apply <velocity_version> <velocity_build> <geyser_version> <geyser_build> <floodgate_version> <floodgate_build> <paper_version>
   ```
   (the exact command is printed by `--test-latest` on success). This writes straight into `group_vars/neo/vars.yml`.
4. Review the diff, then deploy:
   ```
   make neo-docker
   ```
   Back up `minecraft-lobby`, `minecraft-1` (survival), and `minecraft-2` (pvp) under `docker_appdata_path` first if you're also bumping the Paper/`VERSION` value — Minecraft world upgrades are one-way.
5. After deploying, check container logs via Dozzle (`http://192.168.1.3:8081`) to confirm Geyser bound the UDP port and the Paper backends came up clean, before assuming it worked.

## Bumping just one component

`bin/minecraft-check-versions.sh --test` re-validates the versions *currently* pinned (useful as a regression check, e.g. after an unrelated compose change). To test a specific hand-picked combination rather than "whatever is newest", edit the `smoke_test_proxy` / `smoke_test_paper` calls at the bottom of the script directly, or just run the underlying `docker run` commands yourself (see the script for the exact env vars/URLs it uses) — it's the same disposable-container pattern either way.

## Why not just pin an image tag?

The `itzg/minecraft-server` and `itzg/mc-proxy` image tags (Renovate-managed, see `.j2` `image:` lines) version the *wrapper tooling*, not Minecraft/Paper/Velocity/Geyser themselves — those are chosen independently via `VERSION`, `VELOCITY_VERSION`/`VELOCITY_BUILD_ID`, and the plugin download URLs. Renovate bumping the image tag will never fix or cause a version-compatibility break between Velocity and Geyser; that's exactly what this guardrail is for.
