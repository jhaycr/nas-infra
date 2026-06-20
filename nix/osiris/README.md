# nix/osiris

NixOS configuration for **osiris** (NixOS + ZFS, photos/documents).

**Status: scaffold.** The box is not online yet. These files are stubs to be
completed once hardware is provisioned:

1. Install NixOS on the box (enable ZFS, create the data pool).
2. Copy the generated `/etc/nixos/hardware-configuration.nix` into this dir.
3. Set `networking.hostId`, the ZFS pool name, and the deploy SSH key.
4. Deploy with `make osiris`, which copies this dir to the host and runs
   `nixos-rebuild switch --flake /etc/nixos#osiris` (see
   `roles/jhaycr-local.nixos_deploy`).
