{
  # smith - dedicated NixOS VM running the Hermes agent (nousresearch/hermes-agent).
  # Bring-up complete (2026-07): installed at 192.168.1.61. Build via:
  #   nixos-rebuild switch --flake /etc/nixos#smith
  # Secrets are delivered out-of-band by Ansible (group_vars/smith/vault.yml
  # -> jhaycr-local.nixos_deploy's nixos_secret_files -> /etc/hermes/*.env),
  # not sops-nix - nothing secret-related in this flake.
  description = "smith NixOS configuration - runs the Hermes agent";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    {
      nixosConfigurations.smith = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          ./hardware-configuration.nix
        ];
      };
    };
}
