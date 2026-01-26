# Claude Code Session Manager - Linux

A terminal-based session manager for Claude Code CLI on Linux, with support for session discovery, fork/continue workflows, and background watermark images.

## Features

- **Session Discovery**: Automatically finds all Claude Code sessions
- **Fork/Continue**: Continue existing sessions or fork them with new names
- **Background Watermarks**: Display session info as terminal background images (requires GUI terminal)
- **Multiple Terminals**: Support for Kitty, Konsole, and direct mode (WSL/SSH)
- **Shell Support**: Works with Bash, Fish, and any POSIX shell

## Requirements

### Required
- Python 3.8+
- Claude Code CLI (`claude` command)

### Optional (for background images)
- PIL/Pillow (`pip3 install pillow`) OR ImageMagick (`convert` command)

### Terminal Emulators (for watermarks)
- **Kitty** - Recommended, best background image support
- **Konsole** - KDE terminal with profile-based backgrounds
- **Direct mode** - For WSL/SSH (no watermarks, runs in current terminal)

## Installation

```bash
# Clone or download the linux directory
cd linux

# Run the installer
bash install.sh

# Add to PATH if prompted (add to ~/.bashrc or ~/.zshrc)
export PATH="$HOME/.local/bin:$PATH"
```

The installer will:
1. Check and install Python 3 if needed
2. Install PIL/Pillow or ImageMagick for image generation
3. Detect available terminal emulators
4. Create configuration directory at `~/.config/claude-menu/`
5. Install to `~/.local/share/claude-menu/`
6. Create symlinks in `~/.local/bin/`

## Usage

```bash
# Run the session manager
claude-menu

# Show help
claude-menu --help

# Show version
claude-menu --version

# Set terminal type
claude-menu --terminal kitty
claude-menu --terminal konsole
claude-menu --terminal direct

# Show debug info
claude-menu --debug
```

## Key Bindings

| Key | Action |
|-----|--------|
| ↑/↓ or j/k | Navigate sessions |
| Enter | Continue selected session |
| n | New session |
| c | Continue session |
| f | Fork session |
| x | Delete session |
| r | Refresh session list |
| d or i | Debug/Info menu |
| 1-5 | Sort by column |
| q or Esc | Quit |

## Terminal Modes

### Kitty (Recommended)

Kitty provides the best experience with native background image support.

```bash
# Install Kitty
sudo apt install kitty  # Debian/Ubuntu
sudo dnf install kitty  # Fedora
sudo pacman -S kitty    # Arch

# Set as default
claude-menu --terminal kitty
```

**Features:**
- Background watermark images with session info
- Separate terminal window per session
- Session name in title bar

### Konsole (KDE)

Konsole supports backgrounds via profile settings.

```bash
# Install Konsole
sudo apt install konsole  # Debian/Ubuntu

# Set as default
claude-menu --terminal konsole
```

### Direct Mode (WSL/SSH/Headless)

Direct mode runs Claude in the current terminal. No new windows are spawned.

```bash
# Set direct mode
claude-menu --terminal direct
```

**Limitations:**
- No background watermark images
- Sessions run in current terminal (blocking)
- No separate windows for sessions

## WSL (Windows Subsystem for Linux)

### Direct Mode (Default for WSL)

When running in WSL without a display, direct mode is automatically selected. Sessions run in your current terminal (Windows Terminal, etc.).

**Limitations in Direct Mode:**
- Background watermarks are NOT available
- Cannot control the Windows Terminal background from WSL
- Sessions run in the current terminal window

### Enabling Watermarks in WSL

To get background watermarks working in WSL, you need GUI support:

#### Windows 11 (WSLg)

WSLg is built into Windows 11 and provides native GUI support.

```bash
# Install Kitty
sudo apt install kitty

# Switch to Kitty mode
claude-menu --terminal kitty

# Run claude-menu (Kitty window will open)
claude-menu
```

#### Windows 10 (X Server Required)

1. **Install an X Server on Windows:**
   - [VcXsrv](https://sourceforge.net/projects/vcxsrv/) (free)
   - [X410](https://x410.dev/) (paid, Microsoft Store)
   - [MobaXterm](https://mobaxterm.mobatek.net/) (free version available)

2. **Configure WSL to use the X server:**
   ```bash
   # Add to ~/.bashrc
   export DISPLAY=:0

   # Or for WSL2 with VcXsrv
   export DISPLAY=$(grep -m 1 nameserver /etc/resolv.conf | awk '{print $2}'):0
   ```

3. **Install and use Kitty:**
   ```bash
   sudo apt install kitty
   claude-menu --terminal kitty
   ```

### Alternative: Use Windows Version

If you primarily work in Windows Terminal, consider using the Windows version (`Claude-Menu.ps1`) which supports watermarks natively through Windows Terminal profiles.

```powershell
# In PowerShell
.\Claude-Menu.ps1
```

## Configuration

Configuration is stored at `~/.config/claude-menu/config.json`:

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

### Configuration Options

| Option | Values | Description |
|--------|--------|-------------|
| terminal | kitty, konsole, direct | Terminal emulator to use |
| shell | /bin/bash, /bin/zsh, etc. | Shell for new sessions |
| debug | true, false | Enable debug output |

### Paths

| Path | Description |
|------|-------------|
| `~/.config/claude-menu/` | Configuration directory |
| `~/.config/claude-menu/config.json` | Main configuration file |
| `~/.config/claude-menu/backgrounds/` | Generated background images |
| `~/.local/share/claude-menu/` | Installed program files |
| `~/.claude/projects/` | Claude Code session data |

## Background Watermarks

Background watermarks display session information (name, project path, git branch, model) as a subtle overlay on the terminal background.

### Requirements

1. **GUI Terminal**: Kitty or Konsole (not available in direct mode)
2. **Image Library**: PIL/Pillow or ImageMagick

### How It Works

1. When you fork or create a named session, a background image is generated
2. The image contains session name, project path, git branch, and model info
3. A terminal profile is created with this background image
4. New sessions launch in a terminal window with the background

### Customization

Background images are generated at:
`~/.config/claude-menu/backgrounds/<session-name>/background.png`

A companion text file with the same info:
`~/.config/claude-menu/backgrounds/<session-name>/background.txt`

## Troubleshooting

### "Error launching Kitty: No such file or directory"

Kitty is not installed or not in PATH. Either install Kitty or switch to direct mode:
```bash
claude-menu --terminal direct
```

### "Neither ImageMagick nor PIL is available"

Install an image library:
```bash
# Option 1: Pillow (recommended)
pip3 install pillow

# Option 2: System package
sudo apt install python3-pil

# Option 3: ImageMagick
sudo apt install imagemagick
```

### No sessions found

Ensure Claude Code CLI has been used at least once:
```bash
claude
```

Sessions are stored in `~/.claude/projects/`.

### CRLF Line Ending Errors

If you copied files from Windows and see errors like `$'\r': command not found`:
```bash
# Fix line endings
sed -i 's/\r$//' install.sh
sed -i 's/\r$//' *.py
sed -i 's/\r$//' lib/*.py
```

### Debug Menu

Press `d` or `i` in the main menu to access the debug screen, which shows:
- Environment info (Python version, WSL status)
- Image library status
- Terminal emulator availability
- Claude CLI status
- Configuration and paths

## Fish Shell

The Fish shell is fully supported. Use the Fish wrapper:

```fish
# Run directly
~/.local/share/claude-menu/claude-menu.fish

# Or if in PATH
claude-menu-fish
```

Or just use `claude-menu` - it's a Python script that works with any shell.

## Uninstallation

```bash
# Remove installed files
rm -rf ~/.local/share/claude-menu
rm -f ~/.local/bin/claude-menu
rm -f ~/.local/bin/claude-menu-bash
rm -f ~/.local/bin/claude-menu-fish

# Remove configuration (optional)
rm -rf ~/.config/claude-menu

# Remove terminal profiles created by the tool
# Kitty: check ~/.config/kitty/sessions/
# Konsole: check ~/.local/share/konsole/
```

## Version History

- **2.0.0** - Linux port with Kitty/Konsole/Direct mode support
- Based on Windows version (Claude-Menu.ps1)

## License

Same license as the parent project.
