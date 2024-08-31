#!/bin/bash

# Path to the local hooks directory
LOCAL_HOOKS_DIR="git_hooks"

# Path to the git hooks directory in the repo
GIT_HOOKS_DIR=".git/hooks"

# Check if the local hooks directory exists
if [ ! -d "$LOCAL_HOOKS_DIR" ]; then
    echo "Error: Local hooks directory not found at $LOCAL_HOOKS_DIR"
    exit 1
fi

# Create the git hooks directory if it doesn't exist
if [ ! -d "$GIT_HOOKS_DIR" ]; then
    mkdir -p "$GIT_HOOKS_DIR"
fi

# Loop through all files in the local hooks directory
for hook in "$LOCAL_HOOKS_DIR"/*; do
    # Get the filename (basename)
    hook_name=$(basename "$hook")

    # Define the target hook path
    target_hook="$GIT_HOOKS_DIR/$hook_name"

    # Remove the existing hook if it exists (whether it's a symlink or a file)
    if [ -L "$target_hook" ] || [ -f "$target_hook" ]; then
        rm -f "$target_hook"
    fi

    # Create the symlink
    ln -s "../../$hook" "$target_hook"

    echo "Symlink created: $target_hook -> $hook"
done

echo "All hooks have been symlinked."
