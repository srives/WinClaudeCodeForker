"""
Abstract base class for terminal emulator adapters.
Each supported terminal (Kitty, Konsole) implements this interface.
"""

from abc import ABC, abstractmethod
from pathlib import Path
from typing import List, Optional, Dict, Any


class TerminalAdapter(ABC):
    """
    Abstract base class for terminal emulator adapters.

    Each adapter handles terminal-specific operations:
    - Creating/removing profiles
    - Setting background images
    - Launching new terminal windows
    """

    @property
    @abstractmethod
    def name(self) -> str:
        """Human-readable name of the terminal emulator."""
        pass

    @property
    @abstractmethod
    def config_path(self) -> Path:
        """Path to the terminal's configuration directory."""
        pass

    @abstractmethod
    def is_available(self) -> bool:
        """Check if this terminal emulator is installed and available."""
        pass

    @abstractmethod
    def create_profile(
        self,
        name: str,
        working_dir: str,
        background_path: Optional[str] = None,
        command: Optional[str] = None
    ) -> bool:
        """
        Create a new terminal profile.

        Args:
            name: Profile name (will be prefixed with 'Claude-')
            working_dir: Starting directory for the profile
            background_path: Optional path to background image
            command: Optional command to run (default: user's shell)

        Returns:
            True if profile was created successfully
        """
        pass

    @abstractmethod
    def remove_profile(self, name: str) -> bool:
        """
        Remove a terminal profile.

        Args:
            name: Profile name to remove

        Returns:
            True if profile was removed successfully
        """
        pass

    @abstractmethod
    def list_profiles(self) -> List[str]:
        """
        List all Claude-related profiles.

        Returns:
            List of profile names (without 'Claude-' prefix)
        """
        pass

    @abstractmethod
    def set_background(self, profile_name: str, image_path: str) -> bool:
        """
        Set the background image for a profile.

        Args:
            profile_name: Name of the profile
            image_path: Path to the background image

        Returns:
            True if background was set successfully
        """
        pass

    @abstractmethod
    def launch_session(
        self,
        profile_name: str,
        command: Optional[str] = None,
        working_dir: Optional[str] = None
    ) -> bool:
        """
        Launch a new terminal window with the specified profile.

        Args:
            profile_name: Name of the profile to use
            command: Optional command to run in the terminal
            working_dir: Optional working directory override

        Returns:
            True if terminal was launched successfully
        """
        pass

    def get_profile_name(self, session_name: str) -> str:
        """
        Generate a profile name from a session name.
        Prefixes with 'Claude-' for easy identification.
        """
        return f"Claude-{session_name}"

    def profile_exists(self, name: str) -> bool:
        """Check if a profile already exists."""
        return name in self.list_profiles()

    def get_unique_profile_name(self, base_name: str) -> str:
        """
        Get a unique profile name, appending numbers if needed.

        Args:
            base_name: Base name for the profile

        Returns:
            Unique profile name
        """
        name = self.get_profile_name(base_name)
        if not self.profile_exists(name):
            return name

        # Append numbers until we find a unique name
        counter = 1
        while True:
            candidate = f"{name}{counter}"
            if not self.profile_exists(candidate):
                return candidate
            counter += 1
            if counter > 100:  # Safety limit
                raise RuntimeError(f"Could not find unique name for {base_name}")
