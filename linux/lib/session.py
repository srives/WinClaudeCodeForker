"""
Session discovery for Claude Code Session Manager (Linux).
Scans ~/.claude/projects/ to find all Claude sessions.
"""

import os
import json
from pathlib import Path
from datetime import datetime
from typing import List, Optional, Dict, Any
from dataclasses import dataclass, field

from .config import get_claude_projects_path, log_debug, log_error


@dataclass
class Session:
    """Represents a Claude Code session."""
    session_id: str
    project_path: str
    created: datetime
    modified: datetime
    custom_title: str = ''
    first_prompt: str = ''
    message_count: int = 0
    model: str = ''
    git_branch: str = ''
    is_unindexed: bool = False
    is_archived: bool = False
    notes: str = ''
    cost: float = 0.0

    @property
    def display_name(self) -> str:
        """Get the display name for the session."""
        if self.custom_title:
            return self.custom_title
        if self.first_prompt:
            # Truncate first prompt to reasonable length
            prompt = self.first_prompt[:50]
            if len(self.first_prompt) > 50:
                prompt += '...'
            return prompt
        return f"[{self.session_id[:8]}]"

    @property
    def short_id(self) -> str:
        """Get a shortened session ID for display."""
        return self.session_id[:8]


def get_all_sessions() -> List[Session]:
    """
    Discover all Claude Code sessions.
    Scans ~/.claude/projects/ for session files.
    """
    sessions = []
    projects_path = get_claude_projects_path()

    log_debug(f"Scanning for sessions in: {projects_path}")

    if not projects_path.exists():
        log_debug(f"Projects path does not exist: {projects_path}")
        return sessions

    # Scan each project directory
    project_dirs = list(projects_path.iterdir())
    log_debug(f"Found {len(project_dirs)} items in projects directory")

    for project_dir in project_dirs:
        if not project_dir.is_dir():
            log_debug(f"Skipping non-directory: {project_dir.name}")
            continue

        log_debug(f"Scanning project directory: {project_dir.name}")

        # Try to read sessions-index.json first (primary source)
        index_file = project_dir / 'sessions-index.json'
        if index_file.exists():
            log_debug(f"Found sessions-index.json in {project_dir.name}")
            found = _load_sessions_from_index(project_dir, index_file)
            log_debug(f"Loaded {len(found)} sessions from index")
            sessions.extend(found)
        else:
            # Fall back to scanning .jsonl files directly
            log_debug(f"No sessions-index.json, scanning for .jsonl files")
            found = _scan_for_sessions(project_dir)
            log_debug(f"Found {len(found)} sessions from .jsonl files")
            sessions.extend(found)

    # Sort by modified date, newest first
    sessions.sort(key=lambda s: s.modified, reverse=True)

    log_debug(f"Total sessions found: {len(sessions)}")
    return sessions


def _load_sessions_from_index(project_dir: Path, index_file: Path) -> List[Session]:
    """Load sessions from a sessions-index.json file."""
    sessions = []

    try:
        with open(index_file, 'r', encoding='utf-8') as f:
            data = json.load(f)

        log_debug(f"Index file keys: {list(data.keys())}")

        # Try 'entries' first (Claude's format), then 'sessions' as fallback
        entries = data.get('entries', data.get('sessions', []))
        log_debug(f"Found {len(entries)} entries in index")

        for i, entry in enumerate(entries):
            log_debug(f"Entry {i}: keys={list(entry.keys()) if isinstance(entry, dict) else type(entry)}")
            session = _parse_session_entry(entry, project_dir)
            if session:
                sessions.append(session)
            else:
                log_debug(f"Entry {i} rejected (no valid session)")

    except (json.JSONDecodeError, IOError) as e:
        log_error(f"Could not read {index_file}: {e}")
        print(f"Warning: Could not read {index_file}: {e}")

    return sessions


def _parse_session_entry(entry: Dict[str, Any], project_dir: Path) -> Optional[Session]:
    """Parse a session entry from sessions-index.json."""
    try:
        # Try multiple possible key names for session ID
        session_id = entry.get('sessionId') or entry.get('session_id') or entry.get('id', '')
        if not session_id:
            log_debug(f"No sessionId found in entry with keys: {list(entry.keys())}")
            return None

        log_debug(f"Parsing session: {session_id[:8]}...")

        # Parse timestamps - try multiple formats
        created_str = entry.get('created') or entry.get('createdAt') or entry.get('timestamp', '')
        modified_str = entry.get('modified') or entry.get('modifiedAt') or entry.get('lastModified', '')

        created = _parse_datetime(created_str)
        modified = _parse_datetime(modified_str) if modified_str else created

        # Get project path - decode from directory name if needed
        project_path = entry.get('projectPath') or entry.get('project_path') or entry.get('cwd', '')
        if not project_path:
            project_path = _decode_project_path(project_dir.name)

        return Session(
            session_id=session_id,
            project_path=project_path,
            created=created,
            modified=modified,
            custom_title=entry.get('summary') or entry.get('customTitle') or entry.get('title', ''),
            first_prompt=entry.get('firstPrompt') or entry.get('first_prompt', ''),
            message_count=entry.get('messageCount') or entry.get('message_count', 0),
            git_branch=entry.get('gitBranch') or entry.get('git_branch', ''),
        )

    except Exception as e:
        log_error(f"Could not parse session entry: {e}")
        print(f"Warning: Could not parse session entry: {e}")
        return None


def _scan_for_sessions(project_dir: Path) -> List[Session]:
    """Scan a project directory for .jsonl session files."""
    sessions = []

    for jsonl_file in project_dir.glob('*.jsonl'):
        session = _parse_session_file(jsonl_file, project_dir)
        if session:
            sessions.append(session)

    return sessions


def _parse_session_file(jsonl_file: Path, project_dir: Path) -> Optional[Session]:
    """Parse a session directly from a .jsonl file."""
    try:
        session_id = jsonl_file.stem  # Filename without extension
        stat = jsonl_file.stat()

        # Try to extract project path from first line
        project_path = _decode_project_path(project_dir.name)
        first_prompt = ''
        message_count = 0

        with open(jsonl_file, 'r', encoding='utf-8') as f:
            for line in f:
                try:
                    entry = json.loads(line)
                    # Look for cwd in summary entries
                    if entry.get('type') == 'summary' and 'cwd' in entry:
                        project_path = entry['cwd']
                    # Count user messages
                    if entry.get('type') == 'user':
                        message_count += 1
                        if not first_prompt and entry.get('message'):
                            msg = entry['message']
                            if isinstance(msg, list) and msg:
                                first_prompt = str(msg[0].get('text', ''))[:100]
                            elif isinstance(msg, str):
                                first_prompt = msg[:100]
                except json.JSONDecodeError:
                    continue

        return Session(
            session_id=session_id,
            project_path=project_path,
            created=datetime.fromtimestamp(stat.st_ctime),
            modified=datetime.fromtimestamp(stat.st_mtime),
            first_prompt=first_prompt,
            message_count=message_count,
            is_unindexed=True,
        )

    except Exception as e:
        print(f"Warning: Could not parse {jsonl_file}: {e}")
        return None


def _decode_project_path(encoded_name: str) -> str:
    """
    Decode a project path from Claude's encoded directory name.

    Claude encodes paths by:
    - Adding a leading hyphen
    - Replacing '/' with '-'

    Examples:
        '-home-user-project' -> '/home/user/project'
        'home-user-project'  -> '/home/user/project' (fallback without leading hyphen)
    """
    log_debug(f"Decoding project path from: {encoded_name}")

    # Remove leading hyphen if present (Claude's format)
    if encoded_name.startswith('-'):
        encoded_name = encoded_name[1:]

    # Replace hyphens with slashes
    decoded = '/' + encoded_name.replace('-', '/')

    log_debug(f"Decoded project path: {decoded}")
    return decoded


def _encode_project_path(path: str) -> str:
    """
    Encode a project path to Claude's directory name format.

    Claude encodes paths by:
    - Adding a leading hyphen
    - Replacing '/' with '-'

    Examples:
        '/home/user/project' -> '-home-user-project'
    """
    # Remove leading slash and replace path separators, then add leading hyphen
    encoded = '-' + path.lstrip('/').replace('/', '-')
    log_debug(f"Encoded '{path}' -> '{encoded}'")
    return encoded


def _parse_datetime(value: str) -> datetime:
    """Parse an ISO datetime string."""
    if not value:
        return datetime.now()
    try:
        # Handle ISO format with timezone
        if value.endswith('Z'):
            value = value[:-1] + '+00:00'
        return datetime.fromisoformat(value.replace('Z', '+00:00'))
    except ValueError:
        return datetime.now()


def get_session_by_id(session_id: str) -> Optional[Session]:
    """Find a specific session by ID."""
    for session in get_all_sessions():
        if session.session_id == session_id:
            return session
    return None


def get_session_file_path(session: Session) -> Path:
    """Get the full path to a session's .jsonl file."""
    encoded_path = _encode_project_path(session.project_path)
    return get_claude_projects_path() / encoded_path / f"{session.session_id}.jsonl"


def get_git_branch(project_path: str) -> str:
    """Get the current git branch for a project directory."""
    import subprocess
    try:
        result = subprocess.run(
            ['git', 'rev-parse', '--abbrev-ref', 'HEAD'],
            cwd=project_path,
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass
    return ''


def get_session_model(session: Session) -> str:
    """
    Extract the model from a session by reading the last assistant message.
    """
    session_file = get_session_file_path(session)
    if not session_file.exists():
        return ''

    model = ''
    try:
        with open(session_file, 'r', encoding='utf-8') as f:
            for line in f:
                try:
                    entry = json.loads(line)
                    if entry.get('type') == 'assistant':
                        msg = entry.get('message', {})
                        if isinstance(msg, dict) and 'model' in msg:
                            model = msg['model']
                except json.JSONDecodeError:
                    continue
    except IOError:
        pass

    # Simplify model name
    if 'opus' in model.lower():
        return 'opus'
    if 'sonnet' in model.lower():
        return 'sonnet'
    if 'haiku' in model.lower():
        return 'haiku'

    return model
