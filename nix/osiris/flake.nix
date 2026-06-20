{
  # osiris - NixOS + ZFS box for photos/documents.
  # SCAFFOLD: complete on real hardware (generate hardware-configuration.nix,
  # set the ZFS pool, etc.). Build via: nixos-rebuild switch --flake /etc/nixos#osiris
  description = "osiris NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    {
      nixosConfigurations.osiris = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          # ./hardware-configuration.nix   # TODO: generate on real hardware
        ];
      };
    };
}
