"""
Configuration management for Claude Code Session Manager (Linux).
Handles reading/writing config from ~/.config/claude-menu/config.yaml
"""

import os
import sys
import json
import logging
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict, Any
from dataclasses import dataclass, field, asdict


# Global logger
_logger: Optional[logging.Logger] = None


def get_logger() -> logging.Logger:
    """Get or create the debug logger."""
    global _logger
    if _logger is None:
        _logger = logging.getLogger('claude-menu')
        _logger.setLevel(logging.DEBUG)

        # Don't add handlers yet - will be configured when config is loaded
        _logger.addHandler(logging.NullHandler())

    return _logger


def setup_logging(debug: bool = False):
    """Configure logging based on debug setting."""
    logger = get_logger()

    # Remove existing handlers
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)

    if debug:
        # Create log directory
        log_dir = Path.home() / '.config' / 'claude-menu' / 'logs'
        log_dir.mkdir(parents=True, exist_ok=True)

        # File handler with timestamp
        log_file = log_dir / 'debug.log'
        file_handler = logging.FileHandler(log_file, mode='a', encoding='utf-8')
        file_handler.setLevel(logging.DEBUG)
        file_handler.setFormatter(logging.Formatter(
            '%(asctime)s [%(levelname)s] %(name)s: %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        ))
        logger.addHandler(file_handler)

        # Also add console handler for immediate feedback
        console_handler = logging.StreamHandler(sys.stderr)
        console_handler.setLevel(logging.DEBUG)
        console_handler.setFormatter(logging.Formatter('[DEBUG] %(message)s'))
        logger.addHandler(console_handler)

        logger.info("="*60)
        logger.info(f"Debug logging started at {datetime.now()}")
        logger.info("="*60)
    else:
        logger.addHandler(logging.NullHandler())


def log_debug(message: str):
    """Log a debug message."""
    get_logger().debug(message)


def log_info(message: str):
    """Log an info message."""
    get_logger().info(message)


def log_error(message: str):
    """Log an error message."""
    get_logger().error(message)

# Use JSON instead of YAML to avoid extra dependency
# YAML would require PyYAML which isn't always installed

@dataclass
class Config:
    """Application configuration."""
    terminal: str = 'kitty'  # 'kitty' or 'konsole'
    shell: str = 'bash'  # User's preferred shell
    claude_path: str = field(default_factory=lambda: str(Path.home() / '.claude'))
    menu_path: str = field(default_factory=lambda: str(Path.home() / '.config' / 'claude-menu'))
    debug: bool = False
    sort_column: int = 0
    sort_descending: bool = True

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Config':
        """Create Config from dictionary, ignoring unknown keys."""
        valid_keys = {f.name for f in cls.__dataclass_fields__.values()}
        filtered = {k: v for k, v in data.items() if k in valid_keys}
        return cls(**filtered)


class ConfigManager:
    """Manages application configuration."""

    VERSION = 1

    def __init__(self):
        self.config_dir = Path.home() / '.config' / 'claude-menu'
        self.config_file = self.config_dir / 'config.json'
        self.config: Config = Config()

    def ensure_directories(self):
        """Create necessary directories if they don't exist."""
        self.config_dir.mkdir(parents=True, exist_ok=True)

        # Data directories
        (self.config_dir / 'backgrounds').mkdir(exist_ok=True)
        (self.config_dir / 'logs').mkdir(exist_ok=True)

    def load(self) -> Config:
        """Load configuration from file."""
        self.ensure_directories()

        if self.config_file.exists():
            try:
                with open(self.config_file, 'r') as f:
                    data = json.load(f)
                    self.config = Config.from_dict(data.get('config', {}))
            except (json.JSONDecodeError, KeyError) as e:
                print(f"Warning: Could not load config, using defaults: {e}")
                self.config = Config()
        else:
            self.config = Config()
            self.save()  # Create default config file

        return self.config

    def save(self):
        """Save configuration to file."""
        self.ensure_directories()

        data = {
            'version': self.VERSION,
            'config': asdict(self.config)
        }

        with open(self.config_file, 'w') as f:
            json.dump(data, f, indent=2)

    def get(self, key: str, default: Any = None) -> Any:
        """Get a configuration value."""
        return getattr(self.config, key, default)

    def set(self, key: str, value: Any):
        """Set a configuration value."""
        if hasattr(self.config, key):
            setattr(self.config, key, value)
            self.save()
        else:
            raise KeyError(f"Unknown config key: {key}")


# Path helpers
def _is_wsl() -> bool:
    """Check if running in Windows Subsystem for Linux."""
    try:
        with open('/proc/version', 'r') as f:
            return 'microsoft' in f.read().lower()
    except:
        return False


def _get_windows_home() -> Optional[Path]:
    """Get the Windows home directory when running in WSL."""
    if not _is_wsl():
        return None

    # Try to find Windows username
    # Method 1: Check /mnt/c/Users/ for directories
    users_path = Path('/mnt/c/Users')
    if users_path.exists():
        # Skip system directories
        skip_dirs = {'Public', 'Default', 'Default User', 'All Users'}
        for user_dir in users_path.iterdir():
            if user_dir.is_dir() and user_dir.name not in skip_dirs:
                claude_dir = user_dir / '.claude'
                if claude_dir.exists():
                    log_debug(f"Found Windows Claude dir: {claude_dir}")
                    return user_dir

    # Method 2: Try USERPROFILE or USERNAME from Windows env
    try:
        import subprocess
        result = subprocess.run(
            ['cmd.exe', '/c', 'echo', '%USERPROFILE%'],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            win_path = result.stdout.strip()
            if win_path and not win_path.startswith('%'):
                # Convert Windows path to WSL path
                # C:\Users\Name -> /mnt/c/Users/Name
                if win_path[1] == ':':
                    drive = win_path[0].lower()
                    wsl_path = Path(f'/mnt/{drive}' + win_path[2:].replace('\\', '/'))
                    if wsl_path.exists():
                        return wsl_path
    except:
        pass

    return None


def get_claude_projects_path() -> Path:
    """
    Get the Claude projects directory path.

    Checks multiple locations in order:
    1. Linux home: ~/.claude/projects
    2. WSL Windows home: /mnt/c/Users/<user>/.claude/projects
    3. XDG config: ~/.config/claude/projects
    """
    # List of possible locations to check
    candidates = []

    # Primary: Linux home directory
    linux_path = Path.home() / '.claude' / 'projects'
    candidates.append(linux_path)

    # WSL: Check Windows home directory
    if _is_wsl():
        win_home = _get_windows_home()
        if win_home:
            win_claude_path = win_home / '.claude' / 'projects'
            candidates.append(win_claude_path)

    # Alternative: XDG config location
    xdg_path = Path.home() / '.config' / 'claude' / 'projects'
    candidates.append(xdg_path)

    # Return first existing path
    for path in candidates:
        if path.exists():
            log_debug(f"Found Claude projects at: {path}")
            return path

    # Default to Linux path even if it doesn't exist
    log_debug(f"No Claude projects found, defaulting to: {linux_path}")
    return linux_path


def get_all_claude_paths() -> list:
    """
    Get all possible Claude projects paths for debugging.
    Returns list of (path, exists) tuples.
    """
    candidates = []

    # Linux home
    linux_path = Path.home() / '.claude' / 'projects'
    candidates.append((str(linux_path), linux_path.exists()))

    # WSL Windows paths
    if _is_wsl():
        users_path = Path('/mnt/c/Users')
        if users_path.exists():
            skip_dirs = {'Public', 'Default', 'Default User', 'All Users'}
            for user_dir in users_path.iterdir():
                if user_dir.is_dir() and user_dir.name not in skip_dirs:
                    claude_path = user_dir / '.claude' / 'projects'
                    candidates.append((str(claude_path), claude_path.exists()))

    # XDG config
    xdg_path = Path.home() / '.config' / 'claude' / 'projects'
    candidates.append((str(xdg_path), xdg_path.exists()))

    return candidates

def get_menu_path() -> Path:
    """Get the menu data directory path."""
    return Path.home() / '.config' / 'claude-menu'

def get_backgrounds_path() -> Path:
    """Get the backgrounds directory path."""
    return get_menu_path() / 'backgrounds'

def get_session_background_dir(session_name: str) -> Path:
    """Get the background directory for a specific session."""
    return get_backgrounds_path() / session_name

def get_profile_registry_path() -> Path:
    """Get the profile registry JSON file path."""
    return get_menu_path() / 'profile-registry.json'

def get_session_mapping_path() -> Path:
    """Get the session mapping JSON file path."""
    return get_menu_path() / 'session-mapping.json'

def get_background_tracking_path() -> Path:
    """Get the background tracking JSON file path."""
    return get_menu_path() / 'background-tracking.json'

def get_debug_log_path() -> Path:
    """Get the debug log file path."""
    return get_menu_path() / 'logs' / 'debug.log'


# Singleton instance
_config_manager: Optional[ConfigManager] = None

def get_config_manager() -> ConfigManager:
    """Get the singleton ConfigManager instance."""
    global _config_manager
    if _config_manager is None:
        _config_manager = ConfigManager()
        _config_manager.load()
    return _config_manager

def get_config() -> Config:
    """Get the current configuration."""
    return get_config_manager().config
