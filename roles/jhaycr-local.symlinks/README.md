# jhaycr-local.symlinks

Create symlinks from a set of configurable source/destination pairs. Supports per-item `state` (default: `link`; use `absent` to remove a link).

## Variables
- `symlink_mappings`: list of maps with `dest` (required) and `src` (required unless `state: absent`). Optional per-item `force`, `owner`, `group`, `state`, `follow`.
- `symlink_create_parents`: whether to create parent directories for destinations (default: `true`).
- `symlink_parent_mode`: mode to apply to parent directories when created (default: `"0755"`).
- `symlink_force`: default `force` value for symlinks (default: `true`).
- `symlink_become`: whether tasks should use privilege escalation (default: `true`).
- `symlink_owner` / `symlink_group`: default ownership applied when set (defaults to `main_username` when defined).
- `symlink_default_state`: default desired state (`link`), override per item with `state` (e.g., `absent`).
- `symlink_follow`: whether to follow links when setting attributes (default: `false`).

## Example
```yaml
- hosts: neo
  roles:
    - role: jhaycr-local.symlinks
      vars:
        symlink_mappings:
          - src: /mnt/storage/media/Movies
            dest: /mnt/media/Movies
          - src: /mnt/storage/media/TV
            dest: /mnt/media/TV
            force: false
          - dest: /mnt/media/OldLink
            state: absent
        symlink_create_parents: true
```
