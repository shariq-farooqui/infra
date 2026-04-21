{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ./disko.nix
  ];

  networking.hostName = "homelab";
  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";
  # TTY keymap for local console access (Hetzner rescue, QEMU VM). SSH
  # sessions use the client's keyboard layout, so this only matters
  # when the console is used directly.
  console.keyMap = "uk";

  # systemd-boot on the ESP. configurationLimit caps the number of old
  # generations kept in the boot menu, so /boot doesn't slowly fill.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Declarative-only users: no `passwd` drift between the flake and reality.
  users.mutableUsers = false;
  users.users.shariq = {
    isNormalUser = true;
    description = "Shariq Farooqui";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOInT3AgWAoQ8RX8KDy26bVCJoHrrAIyvUMjrgRtU7Fb shariq.farooqui+dev@proton.me"
    ];
  };
  # "!" in /etc/shadow means "no valid password hash"; root cannot log in
  # by password and (combined with PermitRootLogin=no) not by SSH either.
  users.users.root.hashedPassword = "!";

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  services.openssh = {
    enable = true;
    # openFirewall defaults to true, which adds port 22 to the firewall's
    # allowedTCPPorts and therefore makes SSH reachable on the public
    # interface regardless of trustedInterfaces. Disable it; SSH arrives
    # via the tailscale0 interface and is covered by the trustedInterfaces
    # rule in networking.firewall below.
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
    };
  };

  # Tailscale enrols non-interactively on first boot via a pre-auth key
  # decrypted from sops. That means openssh.openFirewall can stay false
  # from the start: the host reaches the tailnet before anyone tries to
  # SSH to it. From then on it's `ssh shariq@homelab` over Tailscale, no
  # client-side keys needed.
  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets.tailscale_auth_key.path;
    extraUpFlags = [ "--ssh" ];
  };

  # nftables is the kernel-native firewall backend. NixOS speaks both,
  # prefer the modern one.
  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    # Trusted interfaces bypass the per-port rules of this firewall.
    # - tailscale0: SSH, nixos-rebuild pushes, tailnet-only services.
    # - cni0: k3s's CNI bridge. Pod-to-service traffic DNATs to the node
    #   IP and then hits the INPUT chain with iifname=cni0, so the chain
    #   must accept it or core cluster services (coredns, metrics-server,
    #   local-path-provisioner) can't reach the kube-apiserver and fail
    #   to start. This is a known k3s-on-NixOS gotcha.
    # Tailscale's WireGuard UDP on the public interface is opened by
    # services.tailscale (openFirewall defaults to true).
    trustedInterfaces = [ "tailscale0" "cni0" ];
    # Public 443 is the only port that reaches this host from the
    # internet. Cloudflare proxies *.farooqui.ai A records here; the
    # Traefik ingress inside the cluster terminates TLS with mTLS via
    # Authenticated Origin Pulls so that a direct hit on the Hetzner IP
    # can't impersonate Cloudflare.
    allowedTCPPorts = [ 443 ];
  };

  # DHCP on all wired interfaces via systemd-networkd.
  networking.useNetworkd = true;
  systemd.network.enable = true;

  # Operator shell baseline plus kubectl and fluxcd for cluster-side work
  # from the host itself.
  environment.systemPackages = with pkgs; [
    git
    vim
    tmux
    htop
    dua
    just
    fzf
    kubectl
    fluxcd
  ];

  # k3s, single-node. --write-kubeconfig-mode=0644 lets shariq read
  # /etc/rancher/k3s/k3s.yaml without sudo (needed to scp it off the
  # box for a local kubectl). The API server binds :6443 on all
  # interfaces; the firewall still drops public inbound because 6443
  # isn't in allowedTCPPorts, and tailscale0 is trusted, so the tailnet
  # can reach the API. Default CNI is flannel, default service CIDR is
  # 10.43.0.0/16 (doesn't clash with tailscale's 100.64.0.0/10).
  # --disable traefik turns off the k3s-bundled Traefik so a Flux-managed
  # HelmRelease can be the only ingress controller on the cluster.
  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = [
      "--write-kubeconfig-mode=0644"
      "--disable=traefik"
    ];
  };

  # Operator shell ergonomics.
  #
  # zsh with syntax highlighting, ghost-text history suggestions, and a
  # deduplicated shared history large enough to span a month of
  # interactive work. fzf wires Ctrl-R for fuzzy history search, Ctrl-T
  # for a fuzzy file picker, and Alt-C for directory jumping.
  #
  # starship renders a compact prompt that always shows host and user
  # so SSH sessions on multiple boxes are obvious at a glance.
  #
  # EDITOR / VISUAL point tools like git at vim by default; LESS is
  # tuned to preserve colours, match search case-insensitively, and
  # exit on single-screen output.
  users.users.shariq.shell = pkgs.zsh;

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    histSize = 100000;
    setOptions = [
      # History is shared live across concurrent shells and saved as
      # each command is issued, not at shell exit. Deduplicated both
      # at write time and across the whole file so the buffer stays
      # dense with real commands.
      "SHARE_HISTORY"
      "INC_APPEND_HISTORY"
      "EXTENDED_HISTORY"
      "HIST_IGNORE_DUPS"
      "HIST_IGNORE_ALL_DUPS"
      "HIST_SAVE_NO_DUPS"
      # Commands starting with a leading space are skipped, handy
      # when pasting anything sensitive that shouldn't land on disk.
      "HIST_IGNORE_SPACE"
      # Navigation conveniences: bare directory names cd into them,
      # cd maintains a stack, duplicate entries on the stack collapse.
      "AUTO_CD"
      "AUTO_PUSHD"
      "PUSHD_IGNORE_DUPS"
      # `#` comments are allowed on the interactive line so blocks
      # pasted from scripts or PRs don't blow up.
      "INTERACTIVE_COMMENTS"
    ];
    interactiveShellInit = ''
      source ${pkgs.fzf}/share/fzf/key-bindings.zsh
      source ${pkgs.fzf}/share/fzf/completion.zsh
    '';
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      # Single-line prompt: user@host path git-state > on one row.
      format = lib.concatStrings [
        "$username" "$hostname" "$directory"
        "$git_branch" "$git_status"
        "$cmd_duration"
        "$character"
      ];
      # Hex values are the standard gruvbox-dark bright variants; they
      # render as gruvbox in any truecolor terminal regardless of the
      # terminal's configured palette.
      username = {
        show_always = true;
        format = "[$user]($style)@";
        style_user = "#8ec07c bold"; # bright aqua
        style_root = "#fb4934 bold"; # bright red — visual alarm for root
      };
      hostname = {
        ssh_only = false;
        format = "[$hostname]($style) ";
        style = "#83a598 bold"; # bright blue
      };
      directory = {
        truncation_length = 3;
        truncation_symbol = ".../";
        format = "[$path]($style) ";
        style = "#fabd2f bold"; # bright yellow
      };
      git_branch = {
        symbol = "";
        format = "on [$branch]($style) ";
        style = "#d3869b bold"; # bright purple
      };
      git_status = {
        format = "[$all_status$ahead_behind]($style) ";
        style = "#fb4934 bold"; # bright red
      };
      cmd_duration = {
        min_time = 2000;
        format = "took [$duration]($style) ";
        style = "#fabd2f"; # bright yellow (not bold, softer weight)
      };
      character = {
        success_symbol = "[>](#b8bb26 bold)"; # bright green
        error_symbol = "[>](#fb4934 bold)";   # bright red
      };
    };
  };

  environment.variables = {
    EDITOR = "vim";
    VISUAL = "vim";
    PAGER = "less";
    LESS = "-R -i -M -F";
    # kubectl without KUBECONFIG falls back to http://localhost:8080, the
    # pre-kubeconfig default that no modern cluster uses. k3s writes its
    # kubeconfig to /etc/rancher/k3s/k3s.yaml (readable because services.k3s
    # sets --write-kubeconfig-mode=0644); point kubectl at it system-wide
    # so `kubectl get nodes` works without flags.
    KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
  };

  environment.shellAliases = {
    ll = "ls -la --color=auto";
    la = "ls -a --color=auto";
    l = "ls -CF --color=auto";
    ".." = "cd ..";
    "..." = "cd ../..";
    "...." = "cd ../../..";
    sctl = "systemctl";
    jctl = "journalctl";
  };

  # Suppress zsh's first-run "newuser install" wizard. The wizard triggers
  # when a user has no ~/.zshrc, ~/.zshenv, ~/.zprofile, or ~/.zlogin
  # and blocks the interactive prompt until dismissed. All real zsh
  # config already lives system-wide in /etc/zshrc via programs.zsh;
  # the wizard's job is redundant here. An empty ~/.zshrc satisfies the
  # check without overriding anything. tmpfiles only creates the file
  # if it doesn't exist, so operator edits survive.
  systemd.tmpfiles.rules = [
    "f /home/shariq/.zshrc 0644 shariq users -"
  ];

  # Secrets. sops-nix decrypts SOPS-encrypted YAML at activation time and
  # writes plaintext to /run/secrets/<name>. The decryption key is the
  # host's SSH ed25519 host key at /etc/ssh/ssh_host_ed25519_key, converted
  # to age internally by sops-nix. The key itself is pre-generated on the
  # laptop and injected via nixos-anywhere's --extra-files so the operator
  # knows the host's age recipient before the box exists and can encrypt
  # secrets.yaml to it. The operator's own age recipient is listed in
  # .sops.yaml too, so sops edits from the laptop work.
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets = {
    tailscale_auth_key = { };
    r2_repository_url = { };
    r2_access_key_id = { };
    r2_secret_access_key = { };
    restic_repo_password = { };
  };
  # Template file that restic's systemd unit loads as an EnvironmentFile.
  # sops placeholders resolve at runtime when restic starts.
  sops.templates.restic_env = {
    content = ''
      AWS_ACCESS_KEY_ID=${config.sops.placeholder.r2_access_key_id}
      AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.r2_secret_access_key}
    '';
    mode = "0400";
    owner = "root";
    group = "root";
  };

  # Restic backup to Cloudflare R2. `services.restic.backups.<name>`
  # generates a systemd timer + service. The repo URL, password and R2
  # access credentials all come from sops; restic encrypts everything
  # client-side, so R2 only sees opaque blobs.
  services.restic.backups.homelab = {
    initialize = true;
    repositoryFile = config.sops.secrets.r2_repository_url.path;
    passwordFile = config.sops.secrets.restic_repo_password.path;
    environmentFile = config.sops.templates.restic_env.path;
    paths = [
      "/var/lib/rancher/k3s/server/db"
      "/var/lib/rancher/k3s/storage"
    ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];
  };

  # Cap journald retention so the btrfs pool can't fill from logs alone.
  # 2 GiB is generous for a single host; MaxRetentionSec drops anything
  # older than a month regardless; MaxFileSec rotates weekly so each
  # journal file stays readable by `journalctl --file`.
  services.journald.extraConfig = ''
    SystemMaxUse=2G
    MaxRetentionSec=1month
    MaxFileSec=1week
  '';

  # Weekly auto-upgrade against the flake. The upgrade service pulls the
  # latest nixpkgs-25.11 tip, rebuilds, and activates. Failed rebuilds
  # leave the previous generation running; no operator action is needed
  # unless a build error appears in the logs. persistent = true means a
  # missed timer (host was off) runs on next boot.
  system.autoUpgrade = {
    enable = true;
    flake = "github:shariq-farooqui/infra?dir=nixos";
    flags = [
      "--update-input" "nixpkgs"
      "-L" # stream build logs to journald
    ];
    dates = "weekly";
    randomizedDelaySec = "45min";
    operation = "switch";
    persistent = true;
  };

  # Pins the NixOS release this host targets. Never change after first
  # install without a documented migration: some modules (Postgres, etc.)
  # use this to decide upgrade paths.
  system.stateVersion = "25.11";

  # Applies ONLY when building the .vm derivation
  # (nix run .#nixosConfigurations.homelab.config.system.build.vm). The
  # real toplevel system is unaffected, so production shariq stays
  # SSH-key-only with no password. Inside the VM, an empty password plus
  # PAM's null-password allowance plus getty autologin boots straight to
  # a shell, letting the operator verify services come up cleanly before
  # any nixos-anywhere run.
  virtualisation.vmVariant = {
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;

    users.users.shariq.hashedPassword = lib.mkForce "";
    security.pam.services.login.allowNullPassword = true;
    services.getty.autologinUser = "shariq";
  };
}
