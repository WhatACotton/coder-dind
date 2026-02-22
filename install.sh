#!/bin/bash
# Route to the actual dotfiles install script
exec "$(dirname "$0")/dotfiles/install.sh"
