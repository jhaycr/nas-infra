{ config, pkgs, ... }:

# smith - dedicated NixOS VM running the Hermes agent (josh profile).
# Replaces the archived Docker container on neo:
#   docker/neo/ai/.archive/hermes-josh/{docker-compose.yml.j2,.env.j2}
# Bring-up complete (2026-07): VM installed at 192.168.1.61, ens18, legacy
# BIOS/MBR (no UEFI on this VM - qm create defaults to seabios), GRUB on
# /dev/sda. This mirrors exactly what the manual bootstrap install used.
{
  # BIOS/legacy boot (no UEFI) - GRUB is required here, not systemd-boot.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";

  # --- Networking ---
  networking.hostName = "smith";
  networking.networkmanager.enable = false;
  networking.useDHCP = false;
  networking.interfaces.ens18.ipv4.addresses = [
    { address = "192.168.1.61"; prefixLength = 24; }
  ];
  networking.defaultGateway = "192.168.1.1";
  networking.nameservers = [ "192.168.1.1" ];

  # Hermes API (bearer-auth) + dashboard (basic-auth) exposed to the LAN.
  networking.firewall.allowedTCPPorts = [ 8642 9119 ];

  # --- Users ---
  # 'ansible' deploy user so this repo's nixos_deploy role can connect.
  users.users.ansible = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    # Same key used by playbooks/bootstrap-ssh.yml.
    openssh.authorizedKeys.keyFiles = [ ./ansible.pub ];
  };
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
  };

  # --- Hermes container runtime ---
  # podman backend for virtualisation.oci-containers: declarative, gets a
  # systemd unit (podman-hermes-josh.service) with journald logging for free,
  # no separate docker daemon needed for a single container.
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  # --- Secrets ---
  # Delivered out-of-band by Ansible (ansible-vault group_vars/smith/vault.yml
  # -> jhaycr-local.nixos_deploy's nixos_secret_files, defined in
  # group_vars/smith/vars.yml), NOT sops-nix. This Nix config just expects
  # both files to already exist on disk before the rebuild:
  #   /etc/hermes/hermes-josh.env (root:root 0600) - ANTHROPIC_API_KEY,
  #     OPENAI_API_KEY, OPENROUTER_API_KEY, API_SERVER_KEY,
  #     API_SERVER_ENABLED, API_SERVER_HOST
  #   /etc/hermes/llm.env (ansible:users 0400) - OPENROUTER_API_KEY,
  #     ANTHROPIC_API_KEY, OPENAI_API_KEY (interactive use, e.g. opencode)

  # Auto-source llm.env in interactive shells (e.g. for OpenCode). Guarded
  # with `-r` so shells that can't read the 0400 file (anything not root or
  # ansible), or a first boot before Ansible has written it yet, don't error.
  environment.interactiveShellInit = ''
    if [ -r /etc/hermes/llm.env ]; then
      set -a
      . /etc/hermes/llm.env
      set +a
    fi
  '';

  # Persistent profile data dir (was {{ docker_appdata_path }}/hermes/profiles/josh on neo).
  systemd.tmpfiles.rules = [ "d /var/lib/hermes-josh 0750 root root -" ];

  virtualisation.oci-containers.containers.hermes-josh = {
    image = "nousresearch/hermes-agent:latest";
    cmd = [ "gateway" "run" ];
    environmentFiles = [ "/etc/hermes/hermes-josh.env" ];
    environment = {
      HERMES_DASHBOARD = "1";
      # LAN-exposed on 0.0.0.0 (image default): the mandatory auth gate is
      # satisfied by the basic-auth provider configured via
      # HERMES_DASHBOARD_BASIC_AUTH_* in /etc/hermes/hermes-josh.env.
    };
    volumes = [
      "/var/lib/hermes-josh:/opt/data"
    ];
    # Host networking so the dashboard (9119) and API server (8642) can bind
    # 127.0.0.1 on the VM itself: the image's auth gate refuses unauthenticated
    # non-loopback binds, and with bridge networking a loopback bind would be
    # unreachable from the host. Local-only by design - access via SSH tunnel.
    # Mirrors the hardening + resource limits from the archived docker-compose.yml.j2
    # (init, shm_size, mem_limit, cpus, pids_limit, cap_drop, security_opt).
    # NB: no `--init` and no `--cap-drop=ALL` (both were in the old docker
    # compose): the current hermes-agent image uses s6-overlay, which must run
    # as PID 1 and needs SETUID/SETGID to drop privileges. Podman's default
    # capability set is already restricted; the VM itself is the isolation
    # boundary.
    extraOptions = [
      "--network=host"
      "--shm-size=1g"
      "--memory=2g"
      "--cpus=1.5"
      "--pids-limit=512"
      "--security-opt=no-new-privileges:true"
    ];
  };

  # --- Log shipping (Alloy -> neo's Loki) ---
  # services.alloy is a real nixpkgs module (nixos/modules/services/monitoring/alloy.nix):
  # options enable/configPath/extraFlags/environmentFile/package. Pointing configPath
  # directly at a Nix-store file works (costs live config-reload vs. the
  # environment.etc."alloy/config.alloy" pattern, which is fine for this single-file setup).
  services.alloy.enable = true;
  services.alloy.configPath = ./alloy-config.alloy;

  environment.systemPackages = with pkgs; [
    git
    python3            # required for Ansible modules
    opencode           # interactive use - picks up llm.env via interactiveShellInit

    # `hermes` from any shell: wraps `podman exec` into the hermes-josh
    # container. Rootful podman needs root, so this leans on the wheel group's
    # passwordless sudo rather than exposing the podman socket. -t only when
    # attached to a terminal so one-shot use (`hermes -z ...` over plain ssh)
    # works too.
    (writeShellScriptBin "hermes" ''
      tty_flag=""
      [ -t 0 ] && tty_flag="-t"
      exec sudo podman exec -i $tty_flag hermes-josh hermes "$@"
    '')
  ];

  system.stateVersion = "26.05";   # matches the installed NixOS release (confirmed during bring-up)
}
