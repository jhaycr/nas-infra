#!/usr/bin/env bash
# READ-ONLY. Look up entities/devices/areas in HA's registries by pattern.
#   find.sh <pattern>            # case-insensitive regex, e.g. find.sh den
source "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"

PATTERN="${1:?Usage: find.sh <pattern>}"

section "Entities matching '$PATTERN'"
oracle_ssh "jq -r '.data.entities[] | select((.entity_id + \" \" + (.original_name//\"\") + \" \" + (.name//\"\")) | test(\"$PATTERN\"; \"i\")) | .entity_id + \"  [\" + (.disabled_by//\"enabled\") + \"]\"' /config/.storage/core.entity_registry" | head -60

section "Devices matching '$PATTERN'"
oracle_ssh "jq -r '.data.devices[] | select(((.name_by_user//\"\") + \" \" + (.name//\"\")) | test(\"$PATTERN\"; \"i\")) | (.name_by_user // .name) + \"  [area: \" + (.area_id//\"-\") + \"]\"' /config/.storage/core.device_registry" | head -30

section "Areas matching '$PATTERN'"
oracle_ssh "jq -r '.data.areas[] | select(.name | test(\"$PATTERN\"; \"i\")) | .id + \" | \" + .name' /config/.storage/core.area_registry"
