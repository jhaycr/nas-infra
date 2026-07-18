#!/bin/sh
# compose-check — deterministic validity check for docker compose .j2 files
# in the nas-infra clone (which has no CI). Renders the Jinja2 with stub
# values for any undefined variable, then YAML-parses the result.
# Root-owned ro mount at /workspace/bin/compose-check (see configuration.nix).
#
# Usage: compose-check <file.yml.j2> [more files...]
# Exit 0 = every file renders and parses; nonzero = first failure, with
# the error on stderr.
set -eu
[ $# -gt 0 ] || { echo "usage: compose-check <file.yml.j2>..." >&2; exit 2; }

exec python3 - "$@" <<'EOF'
import sys, yaml, jinja2

class Stub(jinja2.Undefined):
    # Render any undefined {{ var }} (and attribute/key lookups on it) as a
    # harmless path-ish placeholder instead of failing: we validate STRUCTURE,
    # not variable spelling (host vars aren't available here).
    def __str__(self):  return f"/stub/{self._undefined_name}"
    __getattr__ = __getitem__ = lambda self, name: self

env = jinja2.Environment(undefined=Stub)
failed = False
for path in sys.argv[1:]:
    try:
        rendered = env.from_string(open(path).read()).render()
        yaml.safe_load(rendered)
        print(f"OK   {path}")
    except Exception as e:
        print(f"FAIL {path}: {type(e).__name__}: {e}", file=sys.stderr)
        failed = True
sys.exit(1 if failed else 0)
EOF
