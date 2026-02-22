# .zshenv - loaded for ALL zsh sessions (before .zshrc)
# Keep this minimal — only PATH and essential env vars.

# Nix
if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

# Ensure common paths
typeset -U path
path=(
  $HOME/.local/bin
  $HOME/.claude/bin
  $HOME/.nix-profile/bin
  $HOME/.cargo/bin
  $path
)

export EDITOR="vim"
export VISUAL="code --wait"
export LANG="ja_JP.UTF-8"
export LC_ALL="en_US.UTF-8"
