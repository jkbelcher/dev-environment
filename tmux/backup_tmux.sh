#!/bin/bash

#######################################################################
# Description:
#   Backs up the user's .tmux.conf file from the home directory to the
#   directory where this script is located. The backup is saved with a
#   .bak extension to distinguish it from the original.
#
# Usage:
#   ./backup_tmux.sh
#
# Example:
#   $ cd /tmp
#   $ /opt/scripts/backup_tmux.sh
#   # Backup is saved to /opt/scripts/tmux.conf.bak
#
# Exit codes:
#   0 - Backup completed successfully
#   1 - Source file (~/.tmux.conf) not found
#######################################################################

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source and destination
SOURCE="$HOME/.tmux.conf"
BACKUP="$SCRIPT_DIR/tmux.conf.bak"

if [ -f "$SOURCE" ]; then
    cp "$SOURCE" "$BACKUP"
    echo "Backed up $SOURCE to $BACKUP"
    # Avoid race condition between finder exit and ghostty launch
    sleep 0.5
else
    echo "Error: $SOURCE not found"
    # Avoid race condition between finder exit and ghostty launch
    sleep 0.5
    exit 1
fi