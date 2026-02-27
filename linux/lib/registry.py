"""
Platform Registry - single source of truth for platform identity.

Adding a new platform requires only:
1. A new entry in PLATFORM_REGISTRY
2. A session discovery function in session.py
"""

import shutil
from typing import Dict, Optional


PLATFORM_REGISTRY: Dict[str, dict] = {
    'claude': {
        'key': 'C',
        'display_name': 'Claude Code',
        'rgb': (30, 144, 255),
        'imagemagick_color': 'rgb(30,144,255)',
        'pil_color': (30, 144, 255, 255),
        'cli_name': 'claude',
        'resume_cmd': 'claude --resume {session_id}',
        'fork_cmd': None,  # Claude fork is complex (--resume + --fork-session + --session-id + --model)
        'new_cmd': 'claude',
    },
    'codex': {
        'key': 'X',
        'display_name': 'Codex',
        'rgb': (255, 0, 255),
        'imagemagick_color': 'rgb(255,0,255)',
        'pil_color': (255, 0, 255, 255),
        'cli_name': 'codex',
        'resume_cmd': 'codex resume {session_id}',
        'fork_cmd': 'codex fork {session_id}',
        'new_cmd': 'codex',
    },
}


def get_platform(source: str) -> dict:
    """Get platform entry by source key. Defaults to claude for unknown sources."""
    return PLATFORM_REGISTRY.get(source, PLATFORM_REGISTRY['claude'])


def get_platform_by_key(key: str) -> Optional[dict]:
    """Reverse lookup: find platform by its Key letter (e.g. 'C' or 'X')."""
    for entry in PLATFORM_REGISTRY.values():
        if entry['key'] == key:
            return entry
    return PLATFORM_REGISTRY['claude']


def get_installed_platforms() -> Dict[str, dict]:
    """Return registry entries whose CLI is available in PATH."""
    return {k: v for k, v in PLATFORM_REGISTRY.items() if shutil.which(v['cli_name'])}
