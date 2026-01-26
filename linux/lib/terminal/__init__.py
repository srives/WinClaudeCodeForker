# Terminal adapters for different Linux terminal emulators
import os
import shutil

from .base import TerminalAdapter
from .kitty import KittyAdapter
from .konsole import KonsoleAdapter
from .direct import DirectAdapter


def is_wsl() -> bool:
    """Check if running in Windows Subsystem for Linux."""
    try:
        with open('/proc/version', 'r') as f:
            return 'microsoft' in f.read().lower()
    except:
        return False


def get_adapter(terminal_type: str) -> TerminalAdapter:
    """Factory function to get the appropriate terminal adapter."""
    adapters = {
        'kitty': KittyAdapter,
        'konsole': KonsoleAdapter,
        'direct': DirectAdapter,
        'wsl': DirectAdapter,  # Alias for WSL
    }

    if terminal_type not in adapters:
        # Fall back to direct mode instead of raising error
        print(f"Warning: Unknown terminal '{terminal_type}', using direct mode")
        return DirectAdapter()

    return adapters[terminal_type]()


def detect_terminal() -> str:
    """
    Auto-detect which terminal emulator is available.

    Returns:
        'kitty', 'konsole', or 'direct' (for WSL/headless)
    """
    # Check for WSL first
    if is_wsl():
        # In WSL, prefer direct mode unless GUI terminals are available
        if not os.environ.get('DISPLAY') and not os.environ.get('WAYLAND_DISPLAY'):
            return 'direct'

    # Check for GUI terminals
    if shutil.which('kitty'):
        return 'kitty'
    if shutil.which('konsole'):
        return 'konsole'

    # Fall back to direct mode
    return 'direct'


__all__ = [
    'TerminalAdapter',
    'KittyAdapter',
    'KonsoleAdapter',
    'DirectAdapter',
    'get_adapter',
    'detect_terminal',
    'is_wsl',
]
