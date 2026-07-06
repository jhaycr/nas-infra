#!/usr/bin/env python3
"""PreToolUse gate: block direct write commands against the HA box (oracle).

Reads the hook JSON on stdin. Exit 0 = allow, exit 2 = block (stderr is shown
to the agent). Writes to HA must go through .claude/skills/ha-control/scripts/
write/*, which take a Supervisor backup first. Read-only commands over ssh /
`ansible oracle -m raw` are allowed. This is a guardrail against ungated
mutations, not a security boundary.
"""

import json
import re
import shlex
import sys

ORACLE_HOSTS = re.compile(r"192\.168\.1\.152|homeassistant\.local")

# Commands allowed to start a pipeline segment of a remote read-only payload.
READ_CMDS = {
    "ha", "jq", "cat", "ls", "grep", "egrep", "head", "tail", "find", "df",
    "du", "ps", "date", "echo", "printf", "which", "hostname", "uptime", "wc",
    "sort", "uniq", "paste", "awk", "sed", "stat", "md5sum", "sha256sum",
    "mosquitto_sub", "test", "true", "xargs", "column", "tr", "cut", "diff",
}

# Mutating patterns anywhere in a remote payload (after stripping stderr-only
# redirects). `ha backups new` is deliberately allowed (creating backups is safe).
WRITE_RE = re.compile(
    r">|\btee\b|\brm\b|\bcp\b|\bmv\b|\bmkdir\b|\btouch\b|\bchmod\b|\bchown\b"
    r"|\bln\b|\bdd\b|\btruncate\b|\bapk\b|\breboot\b|\bpoweroff\b|\bhalt\b"
    r"|sed\s+[^|;]*-i"
    r"|ha\s+core\s+(restart|rebuild|stop|start|update|rollback|options)"
    r"|ha\s+(addons|apps)\s+(restart|stop|start|update|install|uninstall|set-options|options|rebuild)"
    r"|ha\s+backups\s+(remove|restore|reload)"
    r"|ha\s+(host|os|su|supervisor)\s+(reboot|shutdown|update|import|options|repair)"
)

BLOCK_MSG = (
    "BLOCKED by ha-write-gate: direct writes to the HA box (oracle) are gated.\n"
    "Use .claude/skills/ha-control/scripts/write/* (backup-first, dry-run by "
    "default, needs user approval for --confirm).\n"
    "Read-only access: scripts/inspect/*.sh or a plain read command "
    "(ha ... info/logs, jq, cat, grep, ...).\n"
    "Config pushes: write/push-config.sh (make oracle-push is also allowed; "
    "its site.yml pre_task takes the backup)."
)


def block(reason):
    print(f"{BLOCK_MSG}\n(Trigger: {reason})", file=sys.stderr)
    sys.exit(2)


def strip_safe_redirects(payload):
    return payload.replace("2>&1", "").replace("2>/dev/null", "").replace(">/dev/null", "")


def payload_is_readonly(payload):
    payload = strip_safe_redirects(payload)
    if WRITE_RE.search(payload):
        return False
    # Every pipeline/sequence segment must start with a whitelisted command.
    # Tokenize with shlex so pipes inside quoted strings (jq programs, grep
    # patterns) don't create phantom segments.
    try:
        tokens = shlex.split(payload)
    except ValueError:
        return False
    segments, current = [], []
    for tok in tokens:
        if tok in ("|", ";", "&&", "||", "&"):
            segments.append(current)
            current = []
        else:
            current.append(tok)
    segments.append(current)
    for seg in segments:
        if not seg:
            continue
        first = seg[0].split("/")[-1]  # tolerate absolute paths
        if first not in READ_CMDS:
            return False
    return True


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)
    if data.get("tool_name") != "Bash":
        sys.exit(0)
    cmd = data.get("tool_input", {}).get("command", "") or ""

    ad_hoc_ansible = re.search(r"\bansible\s+(?!-)[^|;&]*\boracle\b", cmd)
    if not ORACLE_HOSTS.search(cmd) and not ad_hoc_ansible:
        sys.exit(0)  # not aimed at oracle

    # Merely mentioning the host (grep in docs, editing this hook, echo) is
    # fine — only gate commands that invoke a transport that can reach it.
    if not re.search(r"\b(ssh|scp|rsync|sftp|ansible|ansible-playbook|curl|wget|nc|ncat|mosquitto_pub)\b", cmd):
        sys.exit(0)

    # Playbook runs are gated by the site.yml pre_task backup — allow.
    if "ansible-playbook" in cmd:
        sys.exit(0)

    # File-transfer tools pointed at oracle are always writes (or exfil) — gate them.
    if re.search(r"\b(scp|rsync|sftp)\b", cmd):
        block("scp/rsync/sftp targeting oracle")

    # curl: allow the REST API except core-lifecycle service calls.
    if re.search(r"\bcurl\b", cmd):
        if re.search(r"/api/services/homeassistant/(restart|stop)", cmd):
            block("HA core restart/stop via REST — use write/restart.sh")
        sys.exit(0)

    # Extract the remote payload: last argument of ssh / the -a arg of ansible.
    payload = None
    try:
        tokens = shlex.split(cmd)
    except ValueError:
        block("unparseable command targeting oracle")
    if ad_hoc_ansible:
        for i, tok in enumerate(tokens):
            if tok == "-a" and i + 1 < len(tokens):
                payload = tokens[i + 1]
    elif "ssh" in tokens:
        host_idx = next((i for i, t in enumerate(tokens) if "192.168.1.152" in t or "homeassistant.local" in t), None)
        if host_idx is not None and host_idx + 1 < len(tokens):
            payload = " ".join(tokens[host_idx + 1:])

    if payload is None:
        # Interactive ssh session or something we can't inspect — allow a bare
        # login (human use), block anything else odd.
        if re.fullmatch(r"ssh\s+[^|;&]*", cmd.strip()):
            sys.exit(0)
        block("could not extract remote payload")

    if payload_is_readonly(payload):
        sys.exit(0)
    block(f"write pattern or non-whitelisted command in remote payload: {payload[:120]}")


if __name__ == "__main__":
    main()
