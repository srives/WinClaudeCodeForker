"""
Direct terminal adapter for WSL and headless environments.
Runs commands in the current terminal instead of spawning new windows.
"""

import os
import subprocess
from pathlib import Path
from typing import List, Optional

from .base import TerminalAdapter


class DirectAdapter(TerminalAdapter):
    """
    Adapter for running directly in current terminal.

    Used for:
    - WSL (no GUI terminal available)
    - SSH sessions
    - Headless environments
    - Any situation where spawning a new terminal window isn't possible
    """

    @property
    def name(self) -> str:
        return 'Direct'

    @property
    def config_path(self) -> Path:
        return Path.home() / '.config' / 'claude-menu'

    def is_available(self) -> bool:
        """Always available as fallback."""
        return True

    def create_profile(
        self,
        name: str,
        working_dir: str,
        background_path: Optional[str] = None,
        command: Optional[str] = None
    ) -> bool:
        """
        No-op for direct mode - profiles not needed.
        """
        # In direct mode, we don't create terminal profiles
        # Just return success
        return True

    def remove_profile(self, name: str) -> bool:
        """No-op for direct mode."""
        return True

    def list_profiles(self) -> List[str]:
        """No profiles in direct mode."""
        return []

    def set_background(self, profile_name: str, image_path: str) -> bool:
        """No-op for direct mode - backgrounds not supported."""
        return True

    def launch_session(
        self,
        profile_name: str,
        command: Optional[str] = None,
        working_dir: Optional[str] = None
    ) -> bool:
        """
        Run command directly in current terminal.

        Note: This blocks until the command completes.
        """
        try:
            # Change to working directory if specified
            if working_dir:
                os.chdir(working_dir)

            # Run command directly
            if command:
                # Use os.system for interactive commands like claude
                return os.system(command) == 0
            else:
                # Just open a shell
                shell = os.environ.get('SHELL', '/bin/bash')
                return os.system(shell) == 0

        except Exception as e:
            print(f"Error running command: {e}")
            return False

    def launch_with_claude(
        self,
        profile_name: str,
        session_id: str,
        project_path: str
    ) -> bool:
        """
        Run Claude CLI directly in current terminal.
        """
        os.chdir(project_path)
        cmd = f"claude --resume {session_id}"
        return os.system(cmd) == 0
