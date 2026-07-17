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

  # Hermes API (bearer-auth) + dashboard (basic-auth) + dev HA instance
  # (owner-auth, throwaway) exposed to the LAN.
  networking.firewall.allowedTCPPorts = [ 8642 9119 8124 ];

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
  systemd.tmpfiles.rules = [
    # Mounted as /opt/data = $HOME/$HERMES_HOME of the in-container hermes
    # user (uid 10000). Must be owned by 10000: the supervised gateway runs
    # as it, and the image's /opt/hermes/bin/hermes shim drops root->hermes
    # for CLI calls too, which EACCES on a root-owned dir (0750 root root
    # here broke `hermes` via podman exec).
    "d /var/lib/hermes-josh 0750 10000 10000 -"
    "Z /var/lib/hermes-josh - 10000 10000 -"
    # Agent workspace: git clones Hermes authors in (home-assistant-config,
    # nas-infra - seeded by hermes-workspace-seed below). Bind-mounted into the
    # container as /workspace. The agent process in the container runs as uid
    # 10000 (s6 drops privileges from root; rootful podman without userns remap
    # = same uid on the host), so the workspace must be owned by 10000 or the
    # agent can't write anywhere in it. The Z line re-asserts ownership
    # recursively on every activation. Hermes pushes branches only; deployment
    # to live systems stays human-gated (see WORKFLOW.md in the dir).
    "d /var/lib/hermes-workspace 0755 10000 10000 -"
    "Z /var/lib/hermes-workspace - 10000 10000 -"
    # ...except the agent-rules file, which stays root-owned so the agent
    # can't rewrite its own guardrails (lines apply in order; this one runs
    # after the Z above and wins).
    "z /var/lib/hermes-workspace/WORKFLOW.md 0644 root root -"
    # Command reference for the agent (pull/push/GitHub/deploys), sourced from
    # this repo. C+ = copy unconditionally, so edits to workspace-README.md
    # land on the next rebuild; root-owned for the same reason as WORKFLOW.md
    # (the trailing z is needed - the C+ ownership fields lose to the Z above).
    "C+ /var/lib/hermes-workspace/README.md 0644 root root - ${./workspace-README.md}"
    "z /var/lib/hermes-workspace/README.md 0644 root root -"
    # Config dir of the dev/proving-ground HA instance (ha-dev container).
    # Disposable: wipe it and re-run the provisioning steps in BRINGUP.md to
    # reset the dev instance to a blank slate.
    "d /var/lib/ha-dev 0755 root root -"
  ];

  # Seed the agent workspace with a nas-infra clone so Hermes has the IaC to
  # work against. https remote to the public GitHub repo = pull-only; push
  # access (hermes/<topic> branches, like the HA pipeline) needs a write
  # deploy key wired the same way as ha-config-deploy.key - not set up yet.
  # Idempotent oneshot: skips if the clone already exists, so local work in
  # the clone is never touched. The home-assistant-config clone predates this
  # and was made by hand; the files/home_assistant submodule is left
  # uninitialized (private repo, and that clone already exists separately).
  systemd.services.hermes-workspace-seed = {
    description = "Seed git clones in the Hermes agent workspace";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "systemd-tmpfiles-setup.service" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.git ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ws=/var/lib/hermes-workspace
      if [ ! -d "$ws/nas-infra/.git" ]; then
        git clone https://github.com/jhaycr/nas-infra.git "$ws/nas-infra"
        git -C "$ws/nas-infra" config user.name  "Hermes (smith)"
        git -C "$ws/nas-infra" config user.email "hermes@smith.homelab"
        chown -R 10000:10000 "$ws/nas-infra"
      fi
    '';
  };

  virtualisation.oci-containers.containers.hermes-josh = {
    image = "nousresearch/hermes-agent:latest";
    cmd = [ "gateway" "run" ];
    environmentFiles = [
      "/etc/hermes/hermes-josh.env"
      "/etc/hermes/ha-dev.env"   # dev HA instance login (HA_DEV_URL/USERNAME/PASSWORD)
    ];
    environment = {
      HERMES_DASHBOARD = "1";
      # LAN-exposed on 0.0.0.0 (image default): the mandatory auth gate is
      # satisfied by the basic-auth provider configured via
      # HERMES_DASHBOARD_BASIC_AUTH_* in /etc/hermes/hermes-josh.env.
    };
    volumes = [
      "/var/lib/hermes-josh:/opt/data"
      # Git-first authoring workspace (see tmpfiles rule above).
      "/var/lib/hermes-workspace:/workspace"
      # Deploy key mounted at the SAME path as on the host so the repo-local
      # core.sshCommand works from both the VM shell and inside the container.
      "/etc/hermes/ha-config-deploy.key:/etc/hermes/ha-config-deploy.key:ro"
      # Live config dir of the dev HA instance: Hermes copies YAML from its
      # branch worktree here, then check_config + restart via the dev API.
      "/var/lib/ha-dev:/workspace/ha-dev-config"
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

  # --- Dev/proving-ground Home Assistant (integration-test target) ---
  # Throwaway HA Core instance, SAME version as oracle (the HA Green), that
  # Hermes deploys branch config to BEFORE opening a PR: check_config via API,
  # restart, seed entity states via POST /api/states (fires real state_changed
  # events, so automations under test actually trigger), then verify via
  # traces/logbook and attach evidence to the PR. No radios/hardware here -
  # entities are seeded fakes; live deployment to oracle stays human-gated.
  # Provisioned offline (owner user + onboarding skip) - see BRINGUP.md.
  virtualisation.oci-containers.containers.ha-dev = {
    image = "ghcr.io/home-assistant/home-assistant:2026.7.1";   # = oracle Core version; bump together
    volumes = [ "/var/lib/ha-dev:/config" ];
    ports = [ "8124:8123" ];   # LAN-exposed so Josh can eyeball dashboards under test
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

    # `hermes-in <workspace> [hermes args...]`: same as `hermes`, but started
    # inside a workspace clone so the CLI auto-injects that repo's context
    # files (AGENTS.md / CLAUDE.md / .cursorrules resolve from cwd). A bare
    # name is relative to /workspace, e.g.:
    #   hermes-in home-assistant-config chat
    #   hermes-in nas-infra -z "one-shot task"
    (writeShellScriptBin "hermes-in" ''
      if [ $# -eq 0 ]; then
        echo "usage: hermes-in <workspace-dir> [hermes args...]" >&2
        exit 2
      fi
      dir="$1"; shift
      case "$dir" in /*) ;; *) dir="/workspace/$dir" ;; esac
      tty_flag=""
      [ -t 0 ] && tty_flag="-t"
      exec sudo podman exec -i $tty_flag -w "$dir" hermes-josh hermes "$@"
    '')
  ];

  system.stateVersion = "26.05";   # matches the installed NixOS release (confirmed during bring-up)
}
