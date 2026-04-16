terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

locals {
  username = data.coder_workspace_owner.me.name
}

variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI"
  type        = string
}

provider "docker" {
  # Defaulting to null if the variable is an empty string lets us have an optional variable without having to set our own default
  host = var.docker_socket != "" ? var.docker_socket : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  arch                    = data.coder_provisioner.me.arch
  os                      = "linux"
  startup_script_behavior = "non-blocking"
  startup_script = <<-EOT
    set -e

    # --- ttyd (web shell, kept early so it's available even if later installs take time) ---
    if ! command -v ttyd &> /dev/null; then
      TTYD_ARCH=$(uname -m)
      curl -fsSL "https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.$${TTYD_ARCH}" -o /tmp/ttyd
      sudo install -m 0755 /tmp/ttyd /usr/local/bin/ttyd
      rm -f /tmp/ttyd
    fi
    mkdir -p /home/coder/logs
    if [ ! -f /home/coder/.ttyd-auth ]; then
      umask 077
      printf 'coder:%s\n' "$(openssl rand -base64 18 | tr -d '/+=' | head -c 24)" > /home/coder/.ttyd-auth
      echo "ttyd credentials generated at /home/coder/.ttyd-auth"
    fi
    pkill -x ttyd 2>/dev/null || true
    nohup ttyd \
      --port 7681 \
      --interface 0.0.0.0 \
      --credential "$(cat /home/coder/.ttyd-auth)" \
      --writable \
      bash > /home/coder/logs/ttyd.log 2>&1 &
    disown || true

    # Change apt mirror to Japanese mirror
    ARCH=$(dpkg --print-architecture)
    if [ "$ARCH" = "amd64" ]; then
      sudo sed -i.bak 's|http://archive.ubuntu.com/ubuntu/|http://ftp.udx.icscoe.jp/Linux/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources
    elif [ "$ARCH" = "arm64" ]; then
      sudo sed -i.bak 's|http://ports.ubuntu.com/ubuntu-ports/|http://ftp.udx.icscoe.jp/Linux/ubuntu-ports/|g' /etc/apt/sources.list.d/ubuntu.sources
    fi

    # Install zsh, screen and set zsh as default shell
    if ! command -v zsh &> /dev/null || ! command -v screen &> /dev/null; then
      sudo apt-get update && sudo apt-get install -y zsh screen
    fi
    if [ "$(getent passwd coder | cut -d: -f7)" != "$(which zsh)" ]; then
      sudo chsh -s $(which zsh) coder
    fi

    # Prepare user home with default files on first start.
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      touch ~/.init_done
    fi

    # Install the latest code-server.
    # Append "--version x.x.x" to install a specific version of code-server.
    mkdir -p $HOME/.cache
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=$HOME/.cache/code-server

    # Install Japanese language pack & configure locale
    $HOME/.cache/code-server/bin/code-server --install-extension MS-CEINTL.vscode-language-pack-ja
    OUTPUT_DIR="$HOME/.local/share/code-server"
    LANGUAGE_PACK_FOLDER=$(find "$OUTPUT_DIR/extensions" -maxdepth 1 -type d -name "ms-ceintl.vscode-language-pack-*" | head -1)
    if [ -n "$LANGUAGE_PACK_FOLDER" ] && [ -f "$LANGUAGE_PACK_FOLDER/package.json" ] && [ -f "$OUTPUT_DIR/extensions/extensions.json" ]; then
      mkdir -p "$OUTPUT_DIR/User"
      LANGUAGE_PACK_UUID=$(jq -r --arg id "ms-ceintl.$(jq -r .name "$LANGUAGE_PACK_FOLDER/package.json")" \
        '.[] | select(.identifier.id == $id) | .identifier.uuid' "$OUTPUT_DIR/extensions/extensions.json")
      LANGUAGE_PACK_VERSION=$(jq -r .version "$LANGUAGE_PACK_FOLDER/package.json")
      HASH=$(echo -n "$${LANGUAGE_PACK_UUID}$${LANGUAGE_PACK_VERSION}" | md5sum | awk '{print $1}')
      jq -n --arg lp "$LANGUAGE_PACK_FOLDER" --arg hash "$HASH" --arg uuid "$LANGUAGE_PACK_UUID" \
        --slurpfile pkg "$LANGUAGE_PACK_FOLDER/package.json" \
        '($pkg[0].contributes.localizations[0]) as $loc | ($pkg[0].name) as $name |
         (reduce $loc.translations[] as $t ({}; . + {($t.id): "\($lp)/\($t.path)"})) as $tr |
         {($loc.languageId): {hash: $hash, extensions: [{extensionIdentifier: {id: $name, uuid: $uuid}, version: $pkg[0].version}], translations: $tr, label: $loc.localizedLanguageName}}' \
        > "$OUTPUT_DIR/languagepacks.json"
      jq -n --slurpfile pkg "$LANGUAGE_PACK_FOLDER/package.json" \
        '{locale: $pkg[0].contributes.localizations[0].languageId}' > "$OUTPUT_DIR/User/argv.json"
    fi

    # Install code extention
    $HOME/.cache/code-server/bin/code-server \
      --install-extension anthropic.claude-code \
      --install-extension openai.chatgpt \
      --install-extension Google.geminicodeassist

    cat > "$HOME/.local/share/code-server/User/settings.json" <<'SETTINGS'
    {
        "window.autoDetectColorScheme": true,
        "workbench.preferredDarkColorTheme": "Default Dark Modern",
        "workbench.preferredLightColorTheme": "Default Light Modern"
    }
    SETTINGS

    # Start code-server in the background.
    $HOME/.cache/code-server/bin/code-server --auth none --port 13337 --app-name "code-server" > /tmp/code-server.log 2>&1 &

    # Add any commands that should be executed at workspace startup (e.g install requirements, start a program, etc) here

    # Install Node.js
    if ! command -v node &> /dev/null; then
      curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
      sudo apt-get install -y nodejs
    fi

    # Install GitHub CLI
    if ! command -v gh &> /dev/null; then
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
      sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
      sudo apt-get update && sudo apt-get install -y gh
    fi

    # Create default code directory
    mkdir -p $HOME/code

    # --- Claude Code ---
    if ! command -v claude &> /dev/null; then
      curl -fsSL https://claude.ai/install.sh | bash
    fi
    # Persist claude / user-local bin on PATH for every shell (login + non-login)
    sudo tee /etc/profile.d/claude.sh >/dev/null <<'PROFILE'
    export PATH="$HOME/.local/bin:$HOME/.claude/bin:$PATH"
    PROFILE
    sudo chmod 0644 /etc/profile.d/claude.sh
    export PATH="$HOME/.local/bin:$HOME/.claude/bin:$PATH"

    # --- Gemini CLI (npm) ---
    sudo npm install -g @google/gemini-cli

    # --- Copilot CLI (npm) ---
    sudo npm install -g @github/copilot

    # --- OpenClaw ---
    sudo npm install -g openclaw@latest

    # --- Cursor Agent ---
    curl -fsSL https://cursor.com/install | bash

    # --- Nix ---
    if ! command -v nix &> /dev/null; then
      # Install dependencies required by the Nix installer
      sudo apt-get update && sudo apt-get install -y xz-utils
      # Clean up incompatible profile state from previous installs
      rm -rf "$HOME/.local/state/nix" "$HOME/.nix-profile" "$HOME/.nix-defexpr" "$HOME/.nix-channels"
      # Install Nix in single-user mode (suitable for containers)
      sudo install -d -m 0755 -o coder -g coder /nix
      sh <(curl -fsSL https://nixos.org/nix/install) --no-daemon
    fi
    # Source Nix profile for remaining startup commands
    if [ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
      . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi
    # Enable experimental features (nix develop, nix flake, etc.)
    mkdir -p "$HOME/.config/nix"
    if [ ! -f "$HOME/.config/nix/nix.conf" ] || ! grep -q 'experimental-features' "$HOME/.config/nix/nix.conf" 2>/dev/null; then
      echo 'experimental-features = nix-command flakes' >> "$HOME/.config/nix/nix.conf"
    fi

    # --- direnv + nix-direnv (install only, shell config is in dotfiles) ---
    if ! command -v direnv &> /dev/null; then
      nix profile install nixpkgs#direnv nixpkgs#nix-direnv
    fi

    # --- Tailscale ---
    if ! command -v tailscale &> /dev/null; then
      curl -fsSL https://tailscale.com/install.sh | sh
    fi
    sudo tailscaled --tun=userspace-networking --socks5-server=localhost:1055 --outbound-http-proxy-listen=localhost:1055 > /tmp/tailscaled.log 2>&1 &

    # --- Codex CLI ---
    MACHINE_ARCH=$(uname -m)
    case "$MACHINE_ARCH" in
      aarch64) CODEX_ARCH="aarch64" ;;
      x86_64)  CODEX_ARCH="x86_64" ;;
      *)       echo "Unsupported architecture: $MACHINE_ARCH"; exit 1 ;;
    esac
    cd /tmp
    CODEX_URL=$(curl -s https://api.github.com/repos/openai/codex/releases/latest | \
      jq -r '.assets[] | select(.name | startswith("codex-'"$CODEX_ARCH"'") and endswith("unknown-linux-musl.tar.gz")) | .browser_download_url' | head -1)
    curl -fsSL "$CODEX_URL" -o codex-$${CODEX_ARCH}-unknown-linux-musl.tar.gz
    sudo tar -zxvf codex-$${CODEX_ARCH}-unknown-linux-musl.tar.gz -C /usr/local/bin
    sudo mv /usr/local/bin/codex-$${CODEX_ARCH}-unknown-linux-musl /usr/local/bin/codex
    rm codex-$${CODEX_ARCH}-unknown-linux-musl.tar.gz

    # --- Agent log collection (for Grafana) ---
    mkdir -p /home/coder/logs
    touch /home/coder/logs/agent.log

    mkdir -p /home/coder/bin
    cat > /home/coder/bin/claude-run <<'WRAPPER'
    #!/bin/bash
    mkdir -p /home/coder/logs
    PROJECT=$(basename "$PWD")
    TIMESTAMP=$(date +%H%M%S)
    INDIVIDUAL_LOG="/home/coder/logs/$${PROJECT}-$${TIMESTAMP}.log"
    exec claude "$@" 2>&1 | tee -a "$INDIVIDUAL_LOG" /home/coder/logs/agent.log
    WRAPPER
    chmod +x /home/coder/bin/claude-run

    # --- screen defaults + slog wrapper ---
    cat > /home/coder/.screenrc <<'SCRC'
    defscrollback 50000
    logfile /home/coder/logs/screen-%S-%n.log
    SCRC

    sudo tee /usr/local/bin/slog >/dev/null <<'SLOG'
    #!/bin/bash
    # slog — screen + logging wrapper (writes to /home/coder/logs/ so host promtail picks it up)
    #   slog new <name> <cmd...>    detached, logged
    #   slog run <name> <cmd...>    attached, logged
    #   slog ls                     sessions + log files
    #   slog tail <name>            tail -f
    #   slog cat  <name>            less
    #   slog peek <name>            hardcopy + scrollback dump (no attach)
    #   slog attach <name>          re-attach
    set -eu
    LOGDIR=/home/coder/logs
    mkdir -p "$LOGDIR"
    logfile() { echo "$LOGDIR/screen-$1.log"; }
    case "$${1:-}" in
      new)    shift; name=$1; shift; screen -dmS "$name" -L -Logfile "$(logfile "$name")" "$@"; echo "started: $name  log: $(logfile "$name")";;
      run)    shift; name=$1; shift; screen -S "$name" -L -Logfile "$(logfile "$name")" "$@";;
      ls)     screen -ls || true; echo '---'; ls -la "$LOGDIR"/screen-*.log 2>/dev/null || echo 'no log files';;
      tail)   shift; tail -n 200 -f "$(logfile "$1")";;
      cat)    shift; less "$(logfile "$1")";;
      peek)   shift; out=$(mktemp); screen -S "$1" -X hardcopy -h "$out"; less "$out"; rm -f "$out";;
      attach) shift; screen -r "$1";;
      *)      sed -n '2,11p' "$0" | sed 's/^# \?//'; exit 1;;
    esac
    SLOG
    sudo chmod 0755 /usr/local/bin/slog

  EOT

  # These environment variables allow you to make Git commits right away after creating a
  # workspace. Note that they take precedence over configuration defined in ~/.gitconfig!
  # You can remove this block if you'd prefer to configure Git manually or using
  # dotfiles. (see docs/dotfiles.md)
  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
    NIX_PATH            = "nixpkgs=channel:nixpkgs-unstable"
    NIX_CONFIG          = "experimental-features = nix-command flakes"
  }

  # The following metadata blocks are optional. They are used to display
  # information about your workspace in the dashboard. You can remove them
  # if you don't want to display any information.
  # For basic resources, you can use the `coder stat` command.
  # If you need more control, you can write your own script.
  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    # get load avg scaled by number of cores
    script   = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
  }

  metadata {
    display_name = "Swap Usage (Host)"
    key          = "7_swap_host"
    script       = <<EOT
      free -b | awk '/^Swap/ { printf("%.1f/%.1f", $3/1024.0/1024.0/1024.0, $2/1024.0/1024.0/1024.0) }'
    EOT
    interval     = 10
    timeout      = 1
  }
}

resource "coder_app" "code-server" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "code-server"
  url          = "http://localhost:13337/"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"
  order        = 1

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

resource "coder_app" "agent_log" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  slug         = "agent-log"
  display_name = "Agent Log"
  icon         = "/icon/terminal.svg"
  command      = "/bin/bash -c 'tail -n 200 -f /home/coder/logs/agent.log'"
  order        = 3
}

resource "coder_app" "web_shell" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  slug         = "web-shell"
  display_name = "Web Shell"
  url          = "http://localhost:7681"
  icon         = "/icon/terminal.svg"
  subdomain    = false
  share        = "public"
  order        = 4

  healthcheck {
    url       = "http://localhost:7681"
    interval  = 10
    threshold = 3
  }
}

# See https://registry.coder.com/modules/coder/jetbrains
module "jetbrains" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/jetbrains/coder"
  version    = "~> 1.1"
  agent_id   = coder_agent.main.id
  agent_name = "main"
  folder     = "/home/coder"
  tooltip    = "You need to [install JetBrains Toolbox](https://coder.com/docs/user-guides/workspace-access/jetbrains/toolbox) to use this app."
}

module "filebrowser" {
  source   = "registry.coder.com/modules/filebrowser/coder"
  version  = "~> 1.1.3"
  agent_id = coder_agent.main.id
  agent_name = "main"
  folder   = "/home/coder"
  subdomain  = false
  order      = 2
}

module "dotfiles" {
  source   = "registry.coder.com/modules/dotfiles/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  dotfiles_uri = "https://github.com/WhatACotton/coder-dind.git"
  coder_parameter_order = 1000
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "docker_volume" "nix_volume" {
  name = "coder-${data.coder_workspace.me.id}-nix"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "docker_volume" "vivado" {
  name = "vivado"
  driver = "local"
  driver_opts = {
    type   = "none"
    o      = "bind"
    device = "/mnt/sda1"
  }
  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }
}

resource "docker_volume" "dind_socket" {
  name = "coder-${data.coder_workspace.me.id}-dind-socket"
}

resource "docker_container" "dind" {
  count      = data.coder_workspace.me.start_count
  image      = "docker:dind"
  privileged = true
  name       = "dind-${data.coder_workspace.me.id}"
  entrypoint = ["sh", "-c"]
  # MTU 1400 to prevent "message too long" errors with WireGuard/tailnet in nested Docker
  command    = ["addgroup -g 1000 coder 2>/dev/null || true && rm -f /var/run/docker.pid /var/run/docker/containerd/containerd.pid && exec dockerd -H unix:///var/run/docker.sock --group coder --mtu=1400"]
  
  volumes {
    volume_name    = docker_volume.dind_socket.name
    container_path = "/var/run"
    read_only      = false
  }
  volumes {
    volume_name    = docker_volume.vivado.name
    container_path = "/mnt/vivado"
    read_only      = false
  }
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = "codercom/enterprise-base:ubuntu"
  # Uses lower() to avoid Docker restriction on container names.
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: coder@my-workspace:~$
  hostname = data.coder_workspace.me.name
  # Auto-restart on agent crash (workaround for Issue #20338)
  restart = "unless-stopped"
  # Use the docker gateway if the access URL is 127.0.0.1 or host IP to avoid hairpin NAT
  # Disable devcontainer detection (port 4) to prevent agent crashes - it can't reach Docker properly in nested dind
  entrypoint = ["sh", "-c", "export CODER_AGENT_DEVCONTAINERS_ENABLE=0; ${replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1|10\\.240\\.255\\.70/", "host.docker.internal")}"]

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "DOCKER_HOST=unix:///var/run/docker-host/docker.sock",
    "CODER_AGENT_DEVCONTAINERS_ENABLE=0",
    # Force DERP-only, disable direct P2P attempts (impossible in nested Docker, causes "message too long" errors)
    "CODER_AGENT_DISABLE_DIRECT=true"
  ]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  # Expose ttyd (web shell) to dind's network, which is forwarded to the
  # host tailnet via compose.yaml ports. Grafana embeds http://<host>:7681.
  ports {
    internal = 7681
    external = 7681
    ip       = "0.0.0.0"
  }
  volumes {
    volume_name    = docker_volume.dind_socket.name
    container_path = "/var/run/docker-host"
    read_only      = false
  }
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
  volumes {
    volume_name    = docker_volume.vivado.name
    container_path = "/mnt/vivado"
    read_only      = false
  }
  volumes {
    container_path = "/nix"
    volume_name    = docker_volume.nix_volume.name
    read_only      = false
  }
  # Vivado license manager needs udev for device enumeration (MAC address).
  # Without this, Vivado launch_runs crashes with realloc() in libudev
  # when udev_enumerate_scan_devices() finds no device database.
  volumes {
    host_path      = "/run/udev"
    container_path = "/run/udev"
    read_only      = true
  }
  # USB passthrough for FPGA JTAG programming (Xilinx/Digilent cables)
  volumes {
    host_path      = "/dev/bus/usb"
    container_path = "/dev/bus/usb"
  }

  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}