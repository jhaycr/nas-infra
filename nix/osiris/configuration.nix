{ config, pkgs, ... }:

# osiris - NixOS + ZFS box (photos/documents).
# SCAFFOLD ONLY. Fill in the TODOs when the hardware is online.
{
  # --- Boot / ZFS ---
  # ZFS requires a unique 8-hex-digit hostId. Generate with:
  #   head -c4 /dev/urandom | od -A none -t x4
  boot.supportedFilesystems = [ "zfs" ];
  # networking.hostId = "deadbeef";        # TODO: set a real hostId
  # boot.zfs.extraPools = [ "tank" ];      # TODO: import the data pool at boot

  # --- Networking ---
  networking.hostName = "osiris";

  # --- Users ---
  # 'ansible' deploy user so this repo's nixos_deploy role can connect.
  users.users.ansible = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    # openssh.authorizedKeys.keyFiles = [ ./ansible.pub ];   # TODO: add deploy key
  };
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
  };

  environment.systemPackages = with pkgs; [
    git
    python3            # required for Ansible modules
  ];

  # TODO: ZFS datasets / Samba / photo+document services.

  system.stateVersion = "24.11";   # TODO: match the installed NixOS release
}
