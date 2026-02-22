# =============================================================================
#  Zsh Configuration — てんこ盛り Edition 🍜 !
# =============================================================================

# --- Zinit (plugin manager) bootstrap ---
ZINIT_HOME="$HOME/.local/share/zinit/zinit.git"
if [ ! -d "$ZINIT_HOME" ]; then
  mkdir -p "$(dirname $ZINIT_HOME)"
  git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "$ZINIT_HOME/zinit.zsh"

# =============================================================================
#  Plugins (load order matters!)
# =============================================================================

# Additional completions (must be before compinit)
zinit light zsh-users/zsh-completions

# Autosuggestions (fish-like)
zinit light zsh-users/zsh-autosuggestions

# Autopair brackets/quotes
zinit light hlissner/zsh-autopair

# You-should-use: reminds you of existing aliases
zinit light MichaelAquilina/zsh-you-should-use

# =============================================================================
#  Completion System
# =============================================================================

autoload -Uz compinit
_zcompdump="${ZDOTDIR:-$HOME}/.zcompdump"
if [[ -n $_zcompdump(#qN.mh+24) ]]; then
  compinit -d "$_zcompdump"
else
  compinit -C -d "$_zcompdump"
fi
unset _zcompdump

# Replay zinit cached completions
zinit cdreplay -q

# Case-insensitive matching
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'

# Menu selection with arrow keys
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# Group completions by category
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}── %d ──%f'
zstyle ':completion:*:messages' format '%F{purple}── %d ──%f'
zstyle ':completion:*:warnings' format '%F{red}── no matches found ──%f'

# fzf-tab (only if fzf is available)
if command -v fzf &> /dev/null; then
  zinit light Aloxaf/fzf-tab
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath 2>/dev/null || ls -1 --color=always $realpath'
  zstyle ':fzf-tab:*' fzf-min-height 5
fi

# Syntax highlighting (must be last plugin)
zinit light zsh-users/zsh-syntax-highlighting

# =============================================================================
#  History
# =============================================================================

HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000

setopt HIST_IGNORE_ALL_DUPS   # Remove older duplicate entries
setopt HIST_FIND_NO_DUPS      # Don't display duplicates when searching
setopt HIST_REDUCE_BLANKS     # Remove superfluous blanks
setopt HIST_VERIFY             # Show before executing history expansion
setopt SHARE_HISTORY           # Share history between sessions
setopt APPEND_HISTORY          # Append instead of overwrite
setopt INC_APPEND_HISTORY      # Write immediately, not on exit
setopt EXTENDED_HISTORY        # Record timestamp of command

# =============================================================================
#  Zsh Options
# =============================================================================

setopt AUTO_CD                 # cd by typing directory name
setopt AUTO_PUSHD              # Push dir to stack on cd
setopt PUSHD_IGNORE_DUPS       # No duplicate dirs in stack
setopt PUSHD_SILENT            # Don't print stack after pushd
setopt CORRECT                 # Command correction
setopt INTERACTIVE_COMMENTS    # Allow comments in interactive shell
setopt NO_BEEP                 # No beep
setopt GLOB_DOTS               # Include dotfiles in glob
setopt EXTENDED_GLOB           # Extended globbing

# =============================================================================
#  Key Bindings
# =============================================================================

bindkey -e                             # Emacs key bindings
bindkey '^[[A' history-search-backward  # Up arrow: search history backward
bindkey '^[[B' history-search-forward   # Down arrow: search history forward
bindkey '^[[3~' delete-char             # Delete key
bindkey '^[[H' beginning-of-line        # Home key
bindkey '^[[F' end-of-line              # End key
bindkey '^[b' backward-word             # Alt+Left
bindkey '^[f' forward-word              # Alt+Right

# =============================================================================
#  Integrations
# =============================================================================

# direnv
if command -v direnv &> /dev/null; then
  eval "$(direnv hook zsh)"
fi

# fzf key bindings & completion
if command -v fzf &> /dev/null; then
  # fzf settings
  export FZF_DEFAULT_OPTS="
    --height 40% --layout=reverse --border
    --color=fg:#c0caf5,bg:#1a1b26,hl:#ff9e64
    --color=fg+:#c0caf5,bg+:#292e42,hl+:#ff9e64
    --color=info:#7aa2f7,prompt:#7dcfff,pointer:#ff007c
    --color=marker:#9ece6a,spinner:#9ece6a,header:#9ece6a
  "
  # Use fd if available
  if command -v fd &> /dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
  fi

  # Source fzf zsh integration
  [ -f "$HOME/.fzf.zsh" ] && source "$HOME/.fzf.zsh"
  # Or if installed via package manager
  [ -f "/usr/share/doc/fzf/examples/key-bindings.zsh" ] && source "/usr/share/doc/fzf/examples/key-bindings.zsh"
  [ -f "/usr/share/doc/fzf/examples/completion.zsh" ] && source "/usr/share/doc/fzf/examples/completion.zsh"
  # Or via Nix
  if [ -d "$HOME/.nix-profile/share/fzf" ]; then
    source "$HOME/.nix-profile/share/fzf/key-bindings.zsh" 2>/dev/null
    source "$HOME/.nix-profile/share/fzf/completion.zsh" 2>/dev/null
  fi
fi

# zoxide (smart cd)
if command -v zoxide &> /dev/null; then
  eval "$(zoxide init zsh --cmd cd)"
fi

# =============================================================================
#  Load external config
# =============================================================================

[ -f "$HOME/.aliases" ] && source "$HOME/.aliases"
[ -f "$HOME/.functions" ] && source "$HOME/.functions"
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"

# =============================================================================
#  Prompt (Starship)
# =============================================================================

if command -v starship &> /dev/null; then
  eval "$(starship init zsh)"
fi
