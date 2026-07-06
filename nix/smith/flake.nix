{
  # smith - dedicated NixOS VM running the Hermes agent (nousresearch/hermes-agent).
  # Bring-up complete (2026-07): installed at 192.168.1.61. Build via:
  #   nixos-rebuild switch --flake /etc/nixos#smith
  description = "smith NixOS configuration - runs the Hermes agent";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, sops-nix, ... }:
    {
      nixosConfigurations.smith = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          sops-nix.nixosModules.sops
          ./hardware-configuration.nix
        ];
      };
    };
}
