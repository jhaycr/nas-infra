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

  # --- Secrets (sops-nix) ---
  # Encrypted file: ./secrets.yaml (created during bring-up, see README.md).
  # Decrypted via the host's own SSH host key (auto-converted to age) plus an
  # admin age key, so secrets can be edited from trinity too.
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets.hermes_anthropic_api_key = { };
  sops.secrets.hermes_openai_api_key = { };
  sops.secrets.hermes_api_server_key = { };
  # OpenRouter key: Hermes natively reads OPENROUTER_API_KEY. Used to route
  # MiniMax/Qwen models through OpenRouter - no direct MiniMax/DashScope
  # secrets are held here.
  sops.secrets.hermes_openrouter_api_key = { };

  # Rendered env file matching the old hermes-josh/.env.j2 shape, plus
  # OPENROUTER_API_KEY (new).
  sops.templates."hermes-josh.env".content = ''
    ANTHROPIC_API_KEY=${config.sops.placeholder.hermes_anthropic_api_key}
    OPENAI_API_KEY=${config.sops.placeholder.hermes_openai_api_key}
    OPENROUTER_API_KEY=${config.sops.placeholder.hermes_openrouter_api_key}
    API_SERVER_KEY=${config.sops.placeholder.hermes_api_server_key}
    API_SERVER_ENABLED=true
    API_SERVER_HOST=0.0.0.0
  '';

  # Shared env file for interactive use (e.g. OpenCode at the shell), reusing
  # the same underlying secrets - not tied to the hermes-josh container.
  # owner/mode restrict it to the ansible user only.
  sops.templates."llm.env" = {
    owner = "ansible";
    mode = "0400";
    content = ''
      OPENROUTER_API_KEY=${config.sops.placeholder.hermes_openrouter_api_key}
      ANTHROPIC_API_KEY=${config.sops.placeholder.hermes_anthropic_api_key}
      OPENAI_API_KEY=${config.sops.placeholder.hermes_openai_api_key}
    '';
  };

  # Auto-source llm.env in interactive shells (e.g. for OpenCode). Guarded
  # with `-r` so shells that can't read the 0400 file (anything not root or
  # ansible) don't error.
  environment.interactiveShellInit = ''
    if [ -r ${config.sops.templates."llm.env".path} ]; then
      set -a
      . ${config.sops.templates."llm.env".path}
      set +a
    fi
  '';

  # Persistent profile data dir (was {{ docker_appdata_path }}/hermes/profiles/josh on neo).
  systemd.tmpfiles.rules = [ "d /var/lib/hermes-josh 0750 root root -" ];

  virtualisation.oci-containers.containers.hermes-josh = {
    image = "nousresearch/hermes-agent:latest";
    cmd = [ "gateway" "run" ];
    environmentFiles = [ config.sops.templates."hermes-josh.env".path ];
    environment = {
      HERMES_DASHBOARD = "1";
    };
    volumes = [
      "/var/lib/hermes-josh:/opt/data"
    ];
    ports = [
      "127.0.0.1:8642:8642"
      "127.0.0.1:9119:9119"
    ];
    # Mirrors the hardening + resource limits from the archived docker-compose.yml.j2
    # (init, shm_size, mem_limit, cpus, pids_limit, cap_drop, security_opt).
    extraOptions = [
      "--init"
      "--shm-size=1g"
      "--memory=2g"
      "--cpus=1.5"
      "--pids-limit=512"
      "--cap-drop=ALL"
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
  ];

  system.stateVersion = "26.05";   # matches the installed NixOS release (confirmed during bring-up)
}
