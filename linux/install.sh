#!/bin/bash
#
# Claude Code Session Manager - Installer for Linux
#
# This script installs the Claude Code Session Manager to your system.
#

set -e

VERSION="2.0.0"
INSTALL_DIR="$HOME/.local/share/claude-menu"
BIN_DIR="$HOME/.local/bin"
IS_WSL=false

echo "========================================"
echo "Claude Code Session Manager v$VERSION"
echo "Installer for Linux"
echo "========================================"
echo

# Detect if running in WSL
if grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL=true
    echo "WSL environment detected"
    echo
fi

# Detect package manager
detect_pkg_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v zypper &> /dev/null; then
        echo "zypper"
    elif command -v apk &> /dev/null; then
        echo "apk"
    else
        echo ""
    fi
}

PKG_MANAGER=$(detect_pkg_manager)

# Install package function with distro-specific names
install_pkg() {
    local pkg_name="$1"
    local pkg_apt="${2:-$1}"
    local pkg_dnf="${3:-$1}"
    local pkg_pacman="${4:-$1}"

    echo "  Installing $pkg_name..."

    case "$PKG_MANAGER" in
        apt)
            sudo apt-get update -qq
            sudo apt-get install -y -qq "$pkg_apt" 2>/dev/null
            ;;
        dnf)
            sudo dnf install -y -q "$pkg_dnf" 2>/dev/null
            ;;
        pacman)
            sudo pacman -S --noconfirm --quiet "$pkg_pacman" 2>/dev/null
            ;;
        zypper)
            sudo zypper install -y -q "$pkg_dnf" 2>/dev/null
            ;;
        apk)
            sudo apk add --quiet "$pkg_pacman" 2>/dev/null
            ;;
        *)
            echo "  Unknown package manager. Please install $pkg_name manually."
            return 1
            ;;
    esac
}

# Check and install Python 3
echo "Checking Python 3..."
if ! command -v python3 &> /dev/null; then
    echo "  Python 3 not found. Installing..."
    if [ -n "$PKG_MANAGER" ]; then
        install_pkg "python3" "python3" "python3" "python"
    else
        echo "Error: Python 3 is required. Please install it manually."
        exit 1
    fi
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "✓ Python $PYTHON_VERSION found"

# Check and install image library (PIL/Pillow or ImageMagick)
echo ""
echo "Checking image libraries..."
HAS_IMAGE_LIB=false

# Check ImageMagick
if command -v convert &> /dev/null; then
    echo "✓ ImageMagick found"
    HAS_IMAGE_LIB=true
fi

# Check PIL/Pillow
if python3 -c "from PIL import Image" 2>/dev/null; then
    echo "✓ PIL/Pillow found"
    HAS_IMAGE_LIB=true
fi

# Install if neither found
if [ "$HAS_IMAGE_LIB" = false ]; then
    echo "  No image library found. Installing Pillow..."

    # Try apt package first (python3-pil)
    if [ "$PKG_MANAGER" = "apt" ]; then
        if sudo apt-get install -y -qq python3-pil 2>/dev/null; then
            echo "✓ Pillow installed via apt"
            HAS_IMAGE_LIB=true
        fi
    fi

    # Try pip if apt failed or not available
    if [ "$HAS_IMAGE_LIB" = false ]; then
        # Check if pip3 exists
        if ! command -v pip3 &> /dev/null; then
            echo "  pip3 not found. Installing..."
            case "$PKG_MANAGER" in
                apt)    sudo apt-get install -y -qq python3-pip 2>/dev/null ;;
                dnf)    sudo dnf install -y -q python3-pip 2>/dev/null ;;
                pacman) sudo pacman -S --noconfirm --quiet python-pip 2>/dev/null ;;
                zypper) sudo zypper install -y -q python3-pip 2>/dev/null ;;
                apk)    sudo apk add --quiet py3-pip 2>/dev/null ;;
            esac
        fi

        # Try pip install
        if command -v pip3 &> /dev/null; then
            if pip3 install --user pillow 2>/dev/null; then
                echo "✓ Pillow installed via pip"
                HAS_IMAGE_LIB=true
            fi
        fi
    fi

    # Last resort: try ImageMagick
    if [ "$HAS_IMAGE_LIB" = false ]; then
        echo "  Trying ImageMagick..."
        case "$PKG_MANAGER" in
            apt)    sudo apt-get install -y -qq imagemagick-6.q16 2>/dev/null || sudo apt-get install -y -qq graphicsmagick 2>/dev/null ;;
            dnf)    sudo dnf install -y -q ImageMagick 2>/dev/null ;;
            pacman) sudo pacman -S --noconfirm --quiet imagemagick 2>/dev/null ;;
            *)      ;;
        esac

        if command -v convert &> /dev/null; then
            echo "✓ ImageMagick installed"
            HAS_IMAGE_LIB=true
        fi
    fi

    if [ "$HAS_IMAGE_LIB" = false ]; then
        echo "  Warning: Could not install image library."
        echo "  Background images will not be available."
        echo "  You can manually install with: pip3 install pillow"
    fi
fi

# Check for terminal emulator (skip for WSL)
echo ""
echo "Checking terminal emulator..."
TERMINAL=""

if command -v kitty &> /dev/null; then
    TERMINAL="kitty"
    echo "✓ Kitty terminal found"
elif command -v konsole &> /dev/null; then
    TERMINAL="konsole"
    echo "✓ Konsole terminal found"
else
    if [ "$IS_WSL" = true ]; then
        echo "  WSL detected - using direct mode (no GUI terminal needed)"
        TERMINAL="direct"
    else
        echo "  No supported terminal found."
        echo "  Would you like to install Kitty? [Y/n]"
        read -r response
        if [[ ! "$response" =~ ^[Nn]$ ]]; then
            echo "  Installing Kitty..."
            if install_pkg "kitty" "kitty" "kitty" "kitty"; then
                TERMINAL="kitty"
                echo "✓ Kitty installed"
            else
                echo "  Could not install Kitty."
                echo "  Install Kitty or Konsole manually for full functionality."
            fi
        fi
    fi
fi

# Check for Claude CLI
echo ""
echo "Checking Claude CLI..."
if command -v claude &> /dev/null; then
    echo "✓ Claude CLI found"
else
    echo "  Warning: Claude CLI not found."
    echo "  Install from: https://claude.ai/download"
fi

echo ""

# Create directories
echo "Creating directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "$HOME/.config/claude-menu"
mkdir -p "$HOME/.config/claude-menu/backgrounds"
mkdir -p "$HOME/.config/claude-menu/logs"

# Copy files
echo "Installing files..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cp -r "$SCRIPT_DIR/lib" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/claude-menu.py" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/claude-menu.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/claude-menu.fish" "$INSTALL_DIR/"

# Make scripts executable
chmod +x "$INSTALL_DIR/claude-menu.py"
chmod +x "$INSTALL_DIR/claude-menu.sh"
chmod +x "$INSTALL_DIR/claude-menu.fish"

# Create symlinks in bin directory
echo "Creating symlinks..."
ln -sf "$INSTALL_DIR/claude-menu.py" "$BIN_DIR/claude-menu"
ln -sf "$INSTALL_DIR/claude-menu.sh" "$BIN_DIR/claude-menu-bash"
ln -sf "$INSTALL_DIR/claude-menu.fish" "$BIN_DIR/claude-menu-fish"

# Create initial config if not exists
CONFIG_FILE="$HOME/.config/claude-menu/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating default configuration..."
    cat > "$CONFIG_FILE" << EOF
{
  "version": 1,
  "config": {
    "terminal": "$TERMINAL",
    "shell": "$SHELL",
    "debug": false
  }
}
EOF
fi

echo ""
echo "========================================"
echo "Installation complete!"
echo "========================================"
echo ""
echo "Installation directory: $INSTALL_DIR"
echo "Configuration: $CONFIG_FILE"
echo ""
echo "Usage:"
echo "  claude-menu          # Run the session manager"
echo "  claude-menu --help   # Show help"
echo ""

# Check if BIN_DIR is in PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo "Add to your PATH (add to ~/.bashrc or ~/.config/fish/config.fish):"
    echo ""
    echo "  # Bash:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
    echo "  # Fish:"
    echo "  set -gx PATH \$HOME/.local/bin \$PATH"
    echo ""
fi

if [ -n "$TERMINAL" ]; then
    if [ "$TERMINAL" = "direct" ]; then
        echo "Mode: Direct (WSL) - sessions run in current terminal"
        echo ""
        echo "========================================"
        echo "NOTE: Background Watermarks in WSL"
        echo "========================================"
        echo ""
        echo "Background watermark images require a GUI terminal emulator."
        echo "In direct mode (WSL without display), watermarks are disabled."
        echo ""
        echo "To enable watermarks in WSL:"
        echo ""
        echo "  1. Enable GUI support:"
        echo "     - Windows 11: WSLg is built-in (should work automatically)"
        echo "     - Windows 10: Install an X server (VcXsrv, X410, etc.)"
        echo ""
        echo "  2. Install Kitty terminal in WSL:"
        echo "     sudo apt install kitty"
        echo ""
        echo "  3. Set DISPLAY if needed (Windows 10):"
        echo "     export DISPLAY=:0"
        echo ""
        echo "  4. Switch to Kitty mode:"
        echo "     claude-menu --terminal kitty"
        echo ""
        echo "Alternatively, use the Windows version (Claude-Menu.ps1) which"
        echo "supports watermarks natively in Windows Terminal."
        echo ""
    else
        echo "Terminal: $TERMINAL"
        echo ""
        echo "Background watermarks: Enabled"
        echo "  Watermark images will appear in new terminal windows."
    fi
else
    echo "No terminal configured. Set with: claude-menu --terminal kitty"
fi

echo ""
echo "Key bindings:"
echo "  ↑/↓     Navigate sessions"
echo "  Enter   Continue selected session"
echo "  n       New session"
echo "  c       Continue session"
echo "  f       Fork session"
echo "  x       Delete session"
echo "  d/i     Debug/Info menu"
echo "  r       Refresh"
echo "  q       Quit"
echo ""
echo "For more information, see: LINUX.md"
echo ""
