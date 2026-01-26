#!/usr/bin/env fish
#
# Claude Code Session Manager - Fish wrapper
# Calls the Python implementation
#

set SCRIPT_DIR (dirname (status filename))
python3 "$SCRIPT_DIR/claude-menu.py" $argv
