terraform {
  required_providers {
    coder  = { source = "coder/coder" }
    docker = { source = "kreuzwerker/docker" }
  }
}

variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI"
  type        = string
}

provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  arch                    = data.coder_provisioner.me.arch
  os                      = "linux"
  startup_script_behavior = "non-blocking"
  startup_script          = <<-EOT
    set -e

    # Change apt mirror to a faster Japanese one (match docker-in-docker template)
    ARCH=$(dpkg --print-architecture)
    if [ "$ARCH" = "amd64" ]; then
      sudo sed -i.bak 's|http://archive.ubuntu.com/ubuntu/|http://ftp.udx.icscoe.jp/Linux/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources
    elif [ "$ARCH" = "arm64" ]; then
      sudo sed -i.bak 's|http://ports.ubuntu.com/ubuntu-ports/|http://ftp.udx.icscoe.jp/Linux/ubuntu-ports/|g' /etc/apt/sources.list.d/ubuntu.sources
    fi

    # --- git (image usually includes it, but ensure) ---
    if ! command -v git &> /dev/null; then
      sudo apt-get update && sudo apt-get install -y git
    fi

    # --- Tailscale ---
    if ! command -v tailscale &> /dev/null; then
      curl -fsSL https://tailscale.com/install.sh | sh
    fi
    sudo tailscaled --tun=userspace-networking \
      --socks5-server=localhost:1055 \
      --outbound-http-proxy-listen=localhost:1055 \
      > /tmp/tailscaled.log 2>&1 &

    # --- Nix (single-user) ---
    if ! command -v nix &> /dev/null; then
      sudo apt-get update && sudo apt-get install -y xz-utils
      rm -rf "$HOME/.local/state/nix" "$HOME/.nix-profile" "$HOME/.nix-defexpr" "$HOME/.nix-channels"
      sudo install -d -m 0755 -o coder -g coder /nix
      sh <(curl -fsSL https://nixos.org/nix/install) --no-daemon
    fi
    mkdir -p "$HOME/.config/nix"
    if ! grep -q 'experimental-features' "$HOME/.config/nix/nix.conf" 2>/dev/null; then
      echo 'experimental-features = nix-command flakes' >> "$HOME/.config/nix/nix.conf"
    fi
    sudo tee /etc/profile.d/nix.sh >/dev/null <<'PROFILE'
    if [ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
      . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi
    PROFILE
    sudo chmod 0644 /etc/profile.d/nix.sh

    mkdir -p "$HOME/code"
  EOT

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
    NIX_PATH            = "nixpkgs=channel:nixpkgs-unstable"
    NIX_CONFIG          = "experimental-features = nix-command flakes"
  }

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
    key          = "2_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
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

resource "docker_volume" "nix_volume" {
  name = "coder-${data.coder_workspace.me.id}-nix"
  lifecycle {
    ignore_changes = all
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}

resource "docker_container" "workspace" {
  count      = data.coder_workspace.me.start_count
  image      = "codercom/enterprise-base:ubuntu"
  name       = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname   = data.coder_workspace.me.name
  restart    = "unless-stopped"
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1|10\\.240\\.255\\.70/", "host.docker.internal")]

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "CODER_AGENT_DISABLE_DIRECT=true"
  ]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
  volumes {
    container_path = "/nix"
    volume_name    = docker_volume.nix_volume.name
    read_only      = false
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
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}
