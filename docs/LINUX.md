# Claude Code Session Manager - Linux

A terminal-based session manager for Claude Code CLI on Linux, with support for Kitty and Konsole terminal emulators.

## Features

- **Session Discovery**: Automatically finds all Claude Code sessions
- **Fork/Continue Workflows**: Resume or fork existing sessions
- **Background Watermarks**: Visual session identification with custom backgrounds
- **Multiple Terminal Support**: Works with Kitty and Konsole
- **Shell Agnostic**: Bash and Fish wrappers available

## Requirements

### Required

- **Python 3.8+** (usually pre-installed on modern Linux)
- **Claude Code CLI** (must be installed and authenticated)

### Terminal Emulators (at least one)

- **Kitty** - Recommended, excellent background image support
- **Konsole** - KDE's terminal with profile-based backgrounds

### Optional (for background images)

- **ImageMagick** - Preferred for image generation (`convert` command)
- **OR Python Pillow** - Fallback option (`pip install pillow`)

## Installation

### Quick Install

```bash
cd linux/
./install.sh
```

The installer will:
1. Check for Python 3 and supported terminals
2. Create directories in `~/.local/share/claude-menu/`
3. Copy files and create symlinks in `~/.local/bin/`
4. Generate initial configuration

### Manual Install

```bash
# Create directories
mkdir -p ~/.local/share/claude-menu
mkdir -p ~/.local/bin
mkdir -p ~/.config/claude-menu

# Copy files
cp -r linux/lib ~/.local/share/claude-menu/
cp linux/claude-menu.py ~/.local/share/claude-menu/
cp linux/claude-menu.sh ~/.local/share/claude-menu/
cp linux/claude-menu.fish ~/.local/share/claude-menu/

# Make executable
chmod +x ~/.local/share/claude-menu/claude-menu.py
chmod +x ~/.local/share/claude-menu/claude-menu.sh
chmod +x ~/.local/share/claude-menu/claude-menu.fish

# Create symlinks
ln -sf ~/.local/share/claude-menu/claude-menu.py ~/.local/bin/claude-menu
```

### Add to PATH

Ensure `~/.local/bin` is in your PATH:

**Bash** (`~/.bashrc`):
```bash
export PATH="$HOME/.local/bin:$PATH"
```

**Fish** (`~/.config/fish/config.fish`):
```fish
set -gx PATH $HOME/.local/bin $PATH
```

## Usage

### Launch the Session Manager

```bash
claude-menu
```

Or use the shell-specific wrappers:
```bash
claude-menu-bash   # Bash wrapper
claude-menu-fish   # Fish wrapper
```

### Command Line Options

```
claude-menu [options]

Options:
  --help              Show help message
  --version           Show version information
  --config            Display current configuration
  --terminal TYPE     Set terminal emulator (kitty or konsole)
```

### Interactive Menu

The session manager presents an interactive menu:

```
Claude Code Session Manager
═══════════════════════════════════════════════════════════════════

  Session Name          Project Path             Last Modified
  ──────────────────────────────────────────────────────────────────
▸ my-project            ~/projects/my-project    01/26 14:30
  another-session       ~/work/another           01/25 09:15
  old-work              ~/archive/old            01/20 16:45

[N] New  [C] Continue  [F] Fork  [D] Delete  [R] Refresh  [Q] Quit
```

**Navigation:**
- `↑/↓` or `j/k`: Move selection
- `Enter`: Open session action menu
- `N`: Start new session
- `C`: Continue selected session
- `F`: Fork selected session
- `D`: Delete selected session
- `R`: Refresh session list
- `Q`: Quit

### Session Actions

When you select a session, you can:

- **Continue**: Resume the session in a terminal with the existing context
- **Fork**: Create a new session based on this one (useful for branching work)
- **Delete**: Remove the terminal profile (doesn't delete Claude's session data)
- **Rename**: Change the session's display name

## Configuration

Configuration is stored in `~/.config/claude-menu/config.json`:

```json
{
  "version": 1,
  "config": {
    "terminal": "kitty",
    "shell": "/bin/bash",
    "debug": false
  }
}
```

### Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `terminal` | Terminal emulator (`kitty` or `konsole`) | Auto-detected |
| `shell` | Shell for new sessions | `$SHELL` |
| `debug` | Enable debug logging | `false` |

### Change Terminal

```bash
claude-menu --terminal konsole
```

## Terminal Configuration

### Kitty

The session manager creates session files in `~/.config/kitty/sessions/`:

```
# ~/.config/kitty/sessions/claude-myproject.conf
cd /home/user/projects/myproject
launch --title "Claude: myproject"
```

Background images require Kitty's `background_image` support. Add to `~/.config/kitty/kitty.conf`:

```
background_opacity 0.95
```

### Konsole

The session manager creates profile files in `~/.local/share/konsole/`:

```ini
# ~/.local/share/konsole/Claude-myproject.profile
[General]
Name=Claude-myproject
Command=/bin/bash
Directory=/home/user/projects/myproject

[Appearance]
Wallpaper=/path/to/background.png
WallpaperOpacity=0.3
```

## Background Images

Background images provide visual session identification, showing:
- Session name
- Project directory
- Git branch (if applicable)
- Forked-from info (if applicable)
- AI model being used

### Image Generation

The manager tries these methods in order:

1. **ImageMagick** (preferred):
   ```bash
   sudo apt install imagemagick  # Debian/Ubuntu
   sudo dnf install ImageMagick  # Fedora
   ```

2. **Pillow** (fallback):
   ```bash
   pip3 install pillow
   ```

### Custom Backgrounds

Background images are stored in `~/.config/claude-menu/backgrounds/`. Each session gets a unique background based on its name and metadata.

## Troubleshooting

### "No supported terminal emulator found"

Install Kitty or Konsole:
```bash
# Kitty
sudo apt install kitty

# Konsole
sudo apt install konsole
```

### "Claude CLI not found"

Ensure Claude Code CLI is installed and in your PATH:
```bash
which claude
claude --version
```

### Sessions not appearing

Sessions are discovered from `~/.claude/projects/`. If sessions don't appear:

1. Verify Claude CLI is working: `claude --help`
2. Check that sessions exist: `ls ~/.claude/projects/`
3. Enable debug mode: Edit config to set `"debug": true`

### Background images not showing

1. **Kitty**: Ensure `background_image` is not disabled in `~/.config/kitty/kitty.conf`
2. **Konsole**: Check that the profile's Appearance settings allow wallpapers
3. **Missing tools**: Install ImageMagick or Pillow (see above)

### Permission errors

```bash
chmod +x ~/.local/share/claude-menu/claude-menu.py
chmod +x ~/.local/bin/claude-menu
```

## File Locations

| File | Location |
|------|----------|
| Executable | `~/.local/bin/claude-menu` |
| Library | `~/.local/share/claude-menu/lib/` |
| Config | `~/.config/claude-menu/config.json` |
| Backgrounds | `~/.config/claude-menu/backgrounds/` |
| Logs | `~/.config/claude-menu/logs/` |
| Kitty sessions | `~/.config/kitty/sessions/claude-*.conf` |
| Konsole profiles | `~/.local/share/konsole/Claude-*.profile` |

## Differences from Windows Version

| Feature | Windows | Linux |
|---------|---------|-------|
| Terminal | Windows Terminal | Kitty / Konsole |
| Shell | PowerShell | Bash / Fish |
| Config location | `%APPDATA%` | `~/.config/claude-menu/` |
| Image generation | .NET | ImageMagick / Pillow |

## Version

Linux port version: 2.0.0

Based on Claude Code Session Manager for Windows v2.0.0.

## License

Same license as the main Claude Code Session Manager project.
