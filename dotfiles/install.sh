#!/bin/bash
# Coder dotfiles install script
# This script is automatically executed by Coder on workspace start.
set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Symlink dotfiles ---
link_file() {
  local src="$1"
  local dst="$2"
  if [ -L "$dst" ]; then
    rm "$dst"
  elif [ -f "$dst" ]; then
    mv "$dst" "$dst.bak"
  fi
  ln -sf "$src" "$dst"
  echo "Linked: $dst -> $src"
}

link_file "$DOTFILES_DIR/.zshrc"       "$HOME/.zshrc"
link_file "$DOTFILES_DIR/.zshenv"      "$HOME/.zshenv"
link_file "$DOTFILES_DIR/.aliases"     "$HOME/.aliases"
link_file "$DOTFILES_DIR/.functions"   "$HOME/.functions"

# --- Starship ---
mkdir -p "$HOME/.config"
link_file "$DOTFILES_DIR/starship.toml" "$HOME/.config/starship.toml"

# --- direnv ---
mkdir -p "$HOME/.config/direnv"
link_file "$DOTFILES_DIR/direnvrc" "$HOME/.config/direnv/direnvrc"

# --- Install Starship prompt if not present ---
if ! command -v starship &> /dev/null; then
  curl -fsSL https://starship.rs/install.sh | sh -s -- --yes
fi

# --- Install fzf if not present ---
if ! command -v fzf &> /dev/null; then
  if command -v nix &> /dev/null; then
    nix profile install nixpkgs#fzf
  else
    sudo apt-get update && sudo apt-get install -y fzf
  fi
fi

# --- Install eza (modern ls) if not present ---
if ! command -v eza &> /dev/null; then
  if command -v nix &> /dev/null; then
    nix profile install nixpkgs#eza
  fi
fi

# --- Install bat (modern cat) if not present ---
if ! command -v bat &> /dev/null; then
  if command -v nix &> /dev/null; then
    nix profile install nixpkgs#bat
  fi
fi

# --- Install ripgrep if not present ---
if ! command -v rg &> /dev/null; then
  if command -v nix &> /dev/null; then
    nix profile install nixpkgs#ripgrep
  fi
fi

# --- Install fd if not present ---
if ! command -v fd &> /dev/null; then
  if command -v nix &> /dev/null; then
    nix profile install nixpkgs#fd
  fi
fi

# --- Install zoxide (smart cd) if not present ---
if ! command -v zoxide &> /dev/null; then
  if command -v nix &> /dev/null; then
    nix profile install nixpkgs#zoxide
  fi
fi

echo "✅ Dotfiles installed successfully!"
