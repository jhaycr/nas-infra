#!/bin/bash

# wt.sh — add a git worktree for this repo, working around two nas-infra quirks:
#
#   1. git-crypt (.claude/** is filtered). git-crypt's smudge filter fails in
#      linked worktrees ("Unable to open key file"), which HARD-FAILS a normal
#      `git worktree add`. We create with --no-checkout, override the git-crypt
#      filter to a no-op at WORKTREE scope only (so the main checkout keeps real
#      git-crypt), then check out. Result: everything is proper plaintext in the
#      worktree EXCEPT .claude/**, which sits there as harmless ciphertext.
#      >>> Do .claude/ work (skills, hooks, agents) on the MAIN checkout only. <<<
#
#   2. Vault key path. ansible.cfg has `vault_password_file = ../.ansible-vault.key`,
#      so `make` only decrypts when the checkout's parent dir contains the key.
#      The key lives at /home/josh/Code/ansible/.ansible-vault.key, so worktrees
#      MUST be siblings of the main repo under /home/josh/Code/ansible/. This
#      script enforces that by always creating them there.
#
# Usage:
#   bin/wt.sh <existing-branch>            # worktree for an existing branch
#   bin/wt.sh -b <new-branch> [base]       # new branch (from base, default: current HEAD)
#   bin/wt.sh -r <branch-or-path>          # remove a worktree
#   bin/wt.sh -l                           # list worktrees
#
# Worktree dir is always: <repo-parent>/nas-infra-<branch>  (slashes -> dashes)

set -euo pipefail

# Resolve the MAIN worktree root (this script may be invoked from anywhere).
MAIN="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
PARENT="$(dirname "$MAIN")"

wt_path() { # branch -> worktree dir
  echo "$PARENT/nas-infra-$(echo "$1" | tr '/' '-')"
}

list() { git -C "$MAIN" worktree list; }

remove() {
  local target="$1" path
  if [ -d "$target" ]; then path="$target"; else path="$(wt_path "$target")"; fi
  git -C "$MAIN" worktree remove "$path"
  echo "Removed worktree: $path"
  list
}

add() {
  local branch="$1" newbranch="${2:-}" base="${3:-}"
  local path; path="$(wt_path "$branch")"

  if [ -e "$path" ]; then
    echo "Error: $path already exists" >&2; exit 1
  fi

  # Per-worktree config must be enabled for the scoped git-crypt override to
  # stay out of the shared config (and thus off the main checkout). Idempotent.
  git -C "$MAIN" config extensions.worktreeConfig true

  if [ -n "$newbranch" ]; then
    git -C "$MAIN" worktree add --no-checkout -b "$branch" "$path" "${base:-HEAD}"
  else
    git -C "$MAIN" worktree add --no-checkout "$path" "$branch"
  fi

  # No-op the git-crypt filter for THIS worktree only. cat on both smudge and
  # clean means .claude/** round-trips as identical ciphertext -> no spurious
  # diffs, no accidental plaintext leak on commit.
  git -C "$path" config --worktree filter.git-crypt.smudge cat
  git -C "$path" config --worktree filter.git-crypt.clean cat
  git -C "$path" config --worktree filter.git-crypt.required false

  git -C "$path" checkout

  link_shared "$path"

  echo
  echo "Worktree ready: $path"
  echo "  branch:    $(git -C "$path" branch --show-current)"
  echo "  vault key: $([ -f "$path/../.ansible-vault.key" ] && echo 'resolves (make works)' || echo 'MISSING')"
  echo "  NOTE: .claude/** is ciphertext here by design — edit it on the main checkout."
}

# The gitignored, host-agnostic resources a fresh worktree lacks are linked from
# MAIN so `make <host>-...` works without re-downloading anything:
#   1. every gitignored vault.yml — the group_vars/*/vault.yml secret symlinks
#      into ~/Secrets AND the infra_bootstrap role's tasks/vault.yml (an
#      untracked real file caught by the broad `*/**/vault.yml` ignore rule)
#   2. ansible_collections/ — galaxy collections (collections_path = ./)
#   3. roles/<galaxy>       — gitignored galaxy roles (tracked jhaycr* stay real)
link_shared() {
  local path="$1" rel d name
  while IFS= read -r rel; do
    mkdir -p "$path/$(dirname "$rel")"
    if [ -L "$MAIN/$rel" ]; then
      ln -sfn "$(readlink "$MAIN/$rel")" "$path/$rel"   # preserve absolute symlink target
    else
      ln -sfn "$MAIN/$rel" "$path/$rel"                 # point back to main's untracked copy
    fi
  done < <(cd "$MAIN" && find . -name vault.yml -not -path './.git/*' -printf '%P\n' \
             | while read -r f; do git ls-files --error-unmatch "$f" >/dev/null 2>&1 || echo "$f"; done)

  [ -d "$MAIN/ansible_collections" ] && ln -sfn "$MAIN/ansible_collections" "$path/ansible_collections"
  for d in "$MAIN"/roles/*/; do
    name="$(basename "${d%/}")"
    if git -C "$MAIN" check-ignore -q "roles/$name"; then
      ln -sfn "${d%/}" "$path/roles/$name"
    fi
  done
}

case "${1:-}" in
  -l|--list) list ;;
  -r|--remove) shift; remove "${1:?branch or path required}" ;;
  -b) shift; add "${1:?new branch name required}" "new" "${2:-}" ;;
  "" | -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
  *) add "$1" ;;
esac
