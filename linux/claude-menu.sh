#!/bin/bash
#
# Claude Code Session Manager - Bash wrapper
# Calls the Python implementation
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/claude-menu.py" "$@"
