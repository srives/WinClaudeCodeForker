"""
Kitty terminal emulator adapter.
Uses session files in ~/.config/kitty/sessions/ for profiles.
"""

import os
import shutil
import subprocess
from pathlib import Path
from typing import List, Optional

from .base import TerminalAdapter


class KittyAdapter(TerminalAdapter):
    """
    Adapter for Kitty terminal emulator.

    Kitty uses session files for profile-like functionality.
    Each session is a config file in ~/.config/kitty/sessions/
    """

    PROFILE_PREFIX = 'Claude-'

    @property
    def name(self) -> str:
        return 'Kitty'

    @property
    def config_path(self) -> Path:
        return Path.home() / '.config' / 'kitty'

    @property
    def sessions_path(self) -> Path:
        """Path to Kitty session files."""
        return self.config_path / 'sessions'

    def is_available(self) -> bool:
        """Check if Kitty is installed."""
        return shutil.which('kitty') is not None

    def create_profile(
        self,
        name: str,
        working_dir: str,
        background_path: Optional[str] = None,
        command: Optional[str] = None
    ) -> bool:
        """
        Create a Kitty session file.

        Session file format:
        ```
        # Claude session: {name}
        cd /path/to/project
        launch --title "Claude: {name}" {command}
        ```
        """
        try:
            # Ensure sessions directory exists
            self.sessions_path.mkdir(parents=True, exist_ok=True)

            profile_name = self.get_profile_name(name)
            session_file = self.sessions_path / f"{profile_name}.conf"

            # Build session file content
            lines = [
                f"# Claude Code session: {name}",
                f"# Created by claude-menu",
                "",
            ]

            # Add background image if provided
            if background_path and Path(background_path).exists():
                lines.append(f"background_image {background_path}")
                lines.append("background_opacity 0.7")
                lines.append("")

            # Change to working directory
            lines.append(f"cd {working_dir}")
            lines.append("")

            # Launch command
            shell_cmd = command or os.environ.get('SHELL', '/bin/bash')
            lines.append(f'launch --title "Claude: {name}" {shell_cmd}')

            # Write session file
            session_file.write_text('\n'.join(lines))
            return True

        except IOError as e:
            print(f"Error creating Kitty session: {e}")
            return False

    def remove_profile(self, name: str) -> bool:
        """Remove a Kitty session file."""
        try:
            profile_name = self.get_profile_name(name)
            session_file = self.sessions_path / f"{profile_name}.conf"

            if session_file.exists():
                session_file.unlink()
                return True
            return False

        except IOError as e:
            print(f"Error removing Kitty session: {e}")
            return False

    def list_profiles(self) -> List[str]:
        """List all Claude session files."""
        profiles = []

        if not self.sessions_path.exists():
            return profiles

        for session_file in self.sessions_path.glob(f"{self.PROFILE_PREFIX}*.conf"):
            # Extract name without prefix and extension
            name = session_file.stem
            if name.startswith(self.PROFILE_PREFIX):
                profiles.append(name[len(self.PROFILE_PREFIX):])

        return profiles

    def set_background(self, profile_name: str, image_path: str) -> bool:
        """
        Update the background image in a Kitty session file.
        """
        try:
            full_name = self.get_profile_name(profile_name)
            session_file = self.sessions_path / f"{full_name}.conf"

            if not session_file.exists():
                return False

            # Read current content
            content = session_file.read_text()
            lines = content.split('\n')

            # Update or add background_image line
            new_lines = []
            bg_updated = False
            opacity_updated = False

            for line in lines:
                if line.startswith('background_image '):
                    new_lines.append(f"background_image {image_path}")
                    bg_updated = True
                elif line.startswith('background_opacity '):
                    new_lines.append("background_opacity 0.7")
                    opacity_updated = True
                else:
                    new_lines.append(line)

            # Add background lines if not present
            if not bg_updated:
                # Insert after comments
                insert_pos = 0
                for i, line in enumerate(new_lines):
                    if not line.startswith('#') and line.strip():
                        insert_pos = i
                        break
                new_lines.insert(insert_pos, f"background_image {image_path}")
                if not opacity_updated:
                    new_lines.insert(insert_pos + 1, "background_opacity 0.7")

            session_file.write_text('\n'.join(new_lines))
            return True

        except IOError as e:
            print(f"Error updating Kitty background: {e}")
            return False

    def launch_session(
        self,
        profile_name: str,
        command: Optional[str] = None,
        working_dir: Optional[str] = None
    ) -> bool:
        """
        Launch a new Kitty window with the specified session.
        """
        try:
            full_name = self.get_profile_name(profile_name)
            session_file = self.sessions_path / f"{full_name}.conf"

            if not session_file.exists():
                print(f"Session file not found: {session_file}")
                return False

            # Build kitty command
            cmd = ['kitty', '--session', str(session_file)]

            if working_dir:
                cmd.extend(['--directory', working_dir])

            if command:
                cmd.extend(['-e', command])

            # Launch in background
            subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True
            )

            return True

        except (subprocess.SubprocessError, FileNotFoundError) as e:
            print(f"Error launching Kitty: {e}")
            return False

    def launch_with_claude(
        self,
        profile_name: str,
        session_id: str,
        project_path: str
    ) -> bool:
        """
        Launch Kitty with Claude CLI resuming a session.
        """
        # Build claude command
        claude_cmd = f"claude --resume {session_id}"

        # Create a temporary session file or modify existing
        return self.launch_session(
            profile_name,
            command=claude_cmd,
            working_dir=project_path
        )
