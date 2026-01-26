"""
Konsole terminal emulator adapter.
Uses .profile files in ~/.local/share/konsole/ for profiles.
"""

import os
import shutil
import subprocess
import configparser
from pathlib import Path
from typing import List, Optional

from .base import TerminalAdapter


class KonsoleAdapter(TerminalAdapter):
    """
    Adapter for KDE Konsole terminal emulator.

    Konsole uses .profile files in ~/.local/share/konsole/
    These are INI-format files with [General] and [Appearance] sections.
    """

    PROFILE_PREFIX = 'Claude-'

    @property
    def name(self) -> str:
        return 'Konsole'

    @property
    def config_path(self) -> Path:
        return Path.home() / '.local' / 'share' / 'konsole'

    def is_available(self) -> bool:
        """Check if Konsole is installed."""
        return shutil.which('konsole') is not None

    def create_profile(
        self,
        name: str,
        working_dir: str,
        background_path: Optional[str] = None,
        command: Optional[str] = None
    ) -> bool:
        """
        Create a Konsole profile file.

        Profile file format (INI):
        ```
        [General]
        Name=Claude-{name}
        Command=/bin/bash
        Directory=/path/to/project

        [Appearance]
        Wallpaper=/path/to/background.png
        WallpaperOpacity=0.3
        ```
        """
        try:
            # Ensure config directory exists
            self.config_path.mkdir(parents=True, exist_ok=True)

            profile_name = self.get_profile_name(name)
            profile_file = self.config_path / f"{profile_name}.profile"

            # Create profile config
            config = configparser.ConfigParser()
            # Preserve case sensitivity
            config.optionxform = str

            # General section
            config['General'] = {
                'Name': profile_name,
                'Command': command or os.environ.get('SHELL', '/bin/bash'),
                'Directory': working_dir,
                'Parent': 'FALLBACK/',  # Inherit from default profile
            }

            # Appearance section
            config['Appearance'] = {}

            if background_path and Path(background_path).exists():
                config['Appearance']['Wallpaper'] = background_path
                config['Appearance']['WallpaperOpacity'] = '0.3'
                config['Appearance']['WallpaperFlipType'] = 'NoFlip'
                config['Appearance']['WallpaperAnchor'] = 'Center'

            # Write profile file
            with open(profile_file, 'w') as f:
                config.write(f)

            return True

        except (IOError, configparser.Error) as e:
            print(f"Error creating Konsole profile: {e}")
            return False

    def remove_profile(self, name: str) -> bool:
        """Remove a Konsole profile file."""
        try:
            profile_name = self.get_profile_name(name)
            profile_file = self.config_path / f"{profile_name}.profile"

            if profile_file.exists():
                profile_file.unlink()
                return True
            return False

        except IOError as e:
            print(f"Error removing Konsole profile: {e}")
            return False

    def list_profiles(self) -> List[str]:
        """List all Claude profile files."""
        profiles = []

        if not self.config_path.exists():
            return profiles

        for profile_file in self.config_path.glob(f"{self.PROFILE_PREFIX}*.profile"):
            # Extract name without prefix and extension
            name = profile_file.stem
            if name.startswith(self.PROFILE_PREFIX):
                profiles.append(name[len(self.PROFILE_PREFIX):])

        return profiles

    def set_background(self, profile_name: str, image_path: str) -> bool:
        """
        Update the background image in a Konsole profile.
        """
        try:
            full_name = self.get_profile_name(profile_name)
            profile_file = self.config_path / f"{full_name}.profile"

            if not profile_file.exists():
                return False

            # Read current config
            config = configparser.ConfigParser()
            config.optionxform = str
            config.read(profile_file)

            # Ensure Appearance section exists
            if 'Appearance' not in config:
                config['Appearance'] = {}

            # Update background settings
            config['Appearance']['Wallpaper'] = image_path
            config['Appearance']['WallpaperOpacity'] = '0.3'
            config['Appearance']['WallpaperFlipType'] = 'NoFlip'
            config['Appearance']['WallpaperAnchor'] = 'Center'

            # Write updated config
            with open(profile_file, 'w') as f:
                config.write(f)

            return True

        except (IOError, configparser.Error) as e:
            print(f"Error updating Konsole background: {e}")
            return False

    def launch_session(
        self,
        profile_name: str,
        command: Optional[str] = None,
        working_dir: Optional[str] = None
    ) -> bool:
        """
        Launch a new Konsole window with the specified profile.
        """
        try:
            full_name = self.get_profile_name(profile_name)

            # Build konsole command
            cmd = ['konsole', '--profile', full_name]

            if working_dir:
                cmd.extend(['--workdir', working_dir])

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
            print(f"Error launching Konsole: {e}")
            return False

    def launch_with_claude(
        self,
        profile_name: str,
        session_id: str,
        project_path: str
    ) -> bool:
        """
        Launch Konsole with Claude CLI resuming a session.
        """
        claude_cmd = f"claude --resume {session_id}"

        return self.launch_session(
            profile_name,
            command=claude_cmd,
            working_dir=project_path
        )

    def get_profile_info(self, profile_name: str) -> Optional[dict]:
        """
        Read profile information from a Konsole profile file.
        """
        try:
            full_name = self.get_profile_name(profile_name)
            profile_file = self.config_path / f"{full_name}.profile"

            if not profile_file.exists():
                return None

            config = configparser.ConfigParser()
            config.optionxform = str
            config.read(profile_file)

            info = {
                'name': config.get('General', 'Name', fallback=''),
                'command': config.get('General', 'Command', fallback=''),
                'directory': config.get('General', 'Directory', fallback=''),
                'wallpaper': config.get('Appearance', 'Wallpaper', fallback=''),
            }

            return info

        except (IOError, configparser.Error):
            return None
