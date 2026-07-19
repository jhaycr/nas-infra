The kit GUI layout lives in ../inventory.yml.j2 — every kit file in this
directory must also have a `type: "kit: <name>"` slot there, or /kit shows
error items (the plugin does not auto-place file-authored kits).
