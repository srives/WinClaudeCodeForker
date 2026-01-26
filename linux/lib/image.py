"""
Background image generation for Claude Code Session Manager (Linux).
Uses ImageMagick (convert) with PIL/Pillow fallback.
"""

import os
import shutil
import subprocess
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict
from dataclasses import dataclass

from .config import get_session_background_dir


@dataclass
class BackgroundInfo:
    """Information to display on the background image."""
    session_name: str
    directory: str
    computer_user: str = ''
    forked_from: Optional[str] = None
    git_branch: Optional[str] = None
    model: Optional[str] = None

    def __post_init__(self):
        if not self.computer_user:
            import socket
            self.computer_user = f"{socket.gethostname()}:{os.environ.get('USER', 'user')}"


def create_background_image(
    info: BackgroundInfo,
    output_path: Optional[Path] = None
) -> Optional[Path]:
    """
    Create a background image with session information.

    Tries ImageMagick first, falls back to PIL.

    Args:
        info: BackgroundInfo with session details
        output_path: Optional output path (default: ~/.config/claude-menu/backgrounds/{name}/)

    Returns:
        Path to the created image, or None on failure
    """
    # Determine output path
    if output_path is None:
        bg_dir = get_session_background_dir(info.session_name)
        bg_dir.mkdir(parents=True, exist_ok=True)
        output_path = bg_dir / 'background.png'
    else:
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)

    # Try ImageMagick first
    if _has_imagemagick():
        success = _create_with_imagemagick(info, output_path)
        if success:
            _create_text_file(info, output_path.with_suffix('.txt'))
            return output_path

    # Fall back to PIL
    if _has_pil():
        success = _create_with_pil(info, output_path)
        if success:
            _create_text_file(info, output_path.with_suffix('.txt'))
            return output_path

    print("Error: Neither ImageMagick nor PIL is available for image generation")
    return None


def _has_imagemagick() -> bool:
    """Check if ImageMagick's convert command is available."""
    return shutil.which('convert') is not None


def _has_pil() -> bool:
    """Check if PIL/Pillow is available."""
    try:
        from PIL import Image
        return True
    except ImportError:
        return False


def _create_with_imagemagick(info: BackgroundInfo, output_path: Path) -> bool:
    """
    Create background image using ImageMagick.

    Image specs:
    - Resolution: 1920x1080
    - Background: Semi-transparent dark blue (rgba 20,20,40,0.7)
    - Text: White, right-aligned at 60% width
    """
    try:
        # Build text annotations
        annotations = []
        y_pos = 100

        # Session name (large, bold)
        annotations.extend([
            '-font', 'DejaVu-Sans-Mono-Bold',
            '-pointsize', '48',
            '-fill', 'white',
            '-gravity', 'NorthEast',
            '-annotate', f'+200+{y_pos}', info.session_name,
        ])
        y_pos += 80

        # Forked from (if applicable)
        if info.forked_from:
            annotations.extend([
                '-font', 'DejaVu-Sans-Mono-Oblique',
                '-pointsize', '32',
                '-annotate', f'+200+{y_pos}', f'Forked from: {info.forked_from}',
            ])
            y_pos += 60

        # Computer:User
        annotations.extend([
            '-font', 'DejaVu-Sans-Mono',
            '-pointsize', '28',
            '-annotate', f'+200+{y_pos}', info.computer_user,
        ])
        y_pos += 50

        # Git branch (if applicable)
        if info.git_branch:
            annotations.extend([
                '-annotate', f'+200+{y_pos}', f'branch: {info.git_branch}',
            ])
            y_pos += 50

        # Model (if applicable)
        if info.model:
            annotations.extend([
                '-annotate', f'+200+{y_pos}', f'model: {info.model}',
            ])
            y_pos += 50

        # Directory
        annotations.extend([
            '-pointsize', '24',
            '-annotate', f'+200+{y_pos}', info.directory,
        ])

        # Build full command
        cmd = [
            'convert',
            '-size', '1920x1080',
            'xc:rgba(20,20,40,0.7)',
            *annotations,
            str(output_path),
        ]

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30
        )

        return result.returncode == 0

    except (subprocess.SubprocessError, FileNotFoundError) as e:
        print(f"ImageMagick error: {e}")
        return False


def _create_with_pil(info: BackgroundInfo, output_path: Path) -> bool:
    """
    Create background image using PIL/Pillow.
    """
    try:
        from PIL import Image, ImageDraw, ImageFont

        # Create image with semi-transparent dark blue background
        width, height = 1920, 1080
        img = Image.new('RGBA', (width, height), (20, 20, 40, 180))
        draw = ImageDraw.Draw(img)

        # Try to load fonts (fall back to default if not found)
        try:
            font_large = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf', 48)
            font_medium = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', 32)
            font_small = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', 24)
        except IOError:
            # Fall back to default font
            font_large = ImageFont.load_default()
            font_medium = ImageFont.load_default()
            font_small = ImageFont.load_default()

        # Calculate text positions (right-aligned at 60% width)
        x_pos = int(width * 0.6)
        y_pos = 100
        text_color = (255, 255, 255, 255)

        # Session name
        draw.text((x_pos, y_pos), info.session_name, fill=text_color, font=font_large)
        y_pos += 80

        # Forked from
        if info.forked_from:
            draw.text((x_pos, y_pos), f'Forked from: {info.forked_from}', fill=text_color, font=font_medium)
            y_pos += 60

        # Computer:User
        draw.text((x_pos, y_pos), info.computer_user, fill=text_color, font=font_medium)
        y_pos += 50

        # Git branch
        if info.git_branch:
            draw.text((x_pos, y_pos), f'branch: {info.git_branch}', fill=text_color, font=font_medium)
            y_pos += 50

        # Model
        if info.model:
            draw.text((x_pos, y_pos), f'model: {info.model}', fill=text_color, font=font_medium)
            y_pos += 50

        # Directory
        draw.text((x_pos, y_pos), info.directory, fill=text_color, font=font_small)

        # Save image
        img.save(str(output_path), 'PNG')
        return True

    except Exception as e:
        print(f"PIL error: {e}")
        return False


def _create_text_file(info: BackgroundInfo, output_path: Path):
    """
    Create a companion .txt file with the same information.
    This file is used for metadata extraction and verification.
    """
    try:
        lines = [
            f"Session: {info.session_name}",
        ]

        if info.forked_from:
            lines.append(f"Forked from: {info.forked_from}")

        lines.append(f"Computer:User: {info.computer_user}")

        if info.git_branch:
            lines.append(f"Branch: {info.git_branch}")

        if info.model:
            lines.append(f"Model: {info.model}")

        lines.append(f"Directory: {info.directory}")
        lines.append("")
        lines.append(f"Generated: {datetime.now().isoformat()}")

        output_path.write_text('\n'.join(lines))

    except IOError as e:
        print(f"Error creating text file: {e}")


def read_background_txt(txt_path: Path) -> Optional[Dict[str, str]]:
    """
    Read metadata from a background.txt file.

    Returns a dictionary with keys:
    - session, forked_from, computer_user, branch, model, directory
    """
    try:
        if not txt_path.exists():
            return None

        content = txt_path.read_text()
        data = {}

        for line in content.split('\n'):
            line = line.strip()
            if ':' in line:
                key, _, value = line.partition(':')
                key = key.strip().lower().replace(' ', '_').replace(':', '')
                value = value.strip()

                # Map keys to standard names
                key_map = {
                    'session': 'session',
                    'forked_from': 'forked_from',
                    'computer_user': 'computer_user',
                    'computeruser': 'computer_user',
                    'branch': 'branch',
                    'model': 'model',
                    'directory': 'directory',
                }

                if key in key_map:
                    data[key_map[key]] = value

        return data if data else None

    except IOError:
        return None


def update_background_if_changed(
    session_name: str,
    current_info: BackgroundInfo
) -> bool:
    """
    Check if background metadata has changed and regenerate if needed.

    Returns True if background was updated.
    """
    bg_dir = get_session_background_dir(session_name)
    txt_path = bg_dir / 'background.txt'

    # Read existing metadata
    existing = read_background_txt(txt_path)

    if existing is None:
        # No existing file, create new
        create_background_image(current_info)
        return True

    # Check for changes
    changed = False
    if existing.get('model', '') != (current_info.model or ''):
        changed = True
    if existing.get('branch', '') != (current_info.git_branch or ''):
        changed = True
    if existing.get('directory', '') != current_info.directory:
        changed = True

    if changed:
        create_background_image(current_info)
        return True

    return False
