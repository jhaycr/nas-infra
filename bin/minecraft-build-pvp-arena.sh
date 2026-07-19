#!/usr/bin/env bash
# Build (or rebuild) the PVP arena in the minecraft-pvp "arena" world on neo.
#
# Run from trinity after deploying the compose change that sets LEVEL=arena
# (superflat surface: grass at y=-61, players stand at y=-60). Idempotent —
# every fill overwrites the same coordinates. Wakes the container if lazymc
# has it asleep; lazymc re-sleeps it on its normal idle timeout afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."

neo() {
  ansible neo --become -m shell -a "$1"
}

rcon() {
  echo ">> $1"
  neo "docker exec minecraft-pvp rcon-cli '$1'" | tail -1
}

neo "docker start minecraft-pvp" >/dev/null
echo "waiting for minecraft-pvp rcon..."
for _ in $(seq 1 60); do
  if neo "docker exec minecraft-pvp rcon-cli list" >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

# Keep the build area loaded while we edit it
rcon "forceload add -35 -35 35 35"

# Floor: 61x61 stone brick pad replacing the grass surface
rcon "fill -30 -61 -30 30 -61 30 stone_bricks"

# Perimeter walls, 5 high
rcon "fill -30 -60 -30 30 -56 -30 stone_bricks"
rcon "fill -30 -60 30 30 -56 30 stone_bricks"
rcon "fill -30 -60 -30 -30 -56 30 stone_bricks"
rcon "fill 30 -60 -30 30 -56 30 stone_bricks"

# Four 3x3 cover pillars
rcon "fill 11 -60 11 13 -58 13 oak_planks"
rcon "fill -13 -60 11 -11 -58 13 oak_planks"
rcon "fill 11 -60 -13 13 -58 -11 oak_planks"
rcon "fill -13 -60 -13 -11 -58 -11 oak_planks"

# Spawn in the middle, spread joins a little.
# Gamerule ids are the 26.x snake_case registry names; several were renamed
# outright in 25w44a (doDaylightCycle -> advance_time, doMobSpawning ->
# spawn_mobs, spawnRadius -> respawn_radius, ...).
rcon "setworldspawn 0 -60 0"
rcon "gamerule respawn_radius 8"

# Arena rules: instant respawn, always day, no weather, no mobs
rcon "gamerule immediate_respawn true"
rcon "gamerule advance_time false"
rcon "gamerule advance_weather false"
rcon "gamerule spawn_mobs false"
rcon "gamerule keep_inventory false"
rcon "time set day"
rcon "weather clear"

rcon "forceload remove all"
echo "arena build complete"
