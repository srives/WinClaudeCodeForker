# CLAUDE.md - Project Knowledge Base

## Project Overview

**Windows Claude Code Forker** (aka Claude Code Session Manager) is a PowerShell-based session manager for Claude Code CLI with deep Windows Terminal integration. It enables visual session management, forking workflows, cost tracking, and custom terminal backgrounds.

**Current Version:** 2.0.1
**Author:** S. Rives
**Created:** January 2026
**Platform:** Windows 10/11 with PowerShell 5.1+

## Repository Structure

```
C:\repos\Fork\
├── Claude-Menu.ps1           # Main application (~11,800 lines PowerShell)
├── README.md                 # User documentation
├── CLAUDE.md                 # This file - project knowledge base
├── linux/                    # Linux port (Python + shell wrappers)
│   ├── claude-menu.py        # Main entry point
│   ├── claude-menu.sh        # Bash wrapper
│   ├── claude-menu.fish      # Fish wrapper
│   ├── install.sh            # Installer script
│   ├── config/
│   │   └── default.yaml      # Default configuration
│   └── lib/
│       ├── __init__.py
│       ├── config.py         # Configuration management
│       ├── session.py        # Session discovery
│       ├── menu.py           # Curses-based interactive menu
│       ├── image.py          # Background image generation
│       └── terminal/
│           ├── __init__.py
│           ├── base.py       # Abstract terminal adapter
│           ├── kitty.py      # Kitty terminal adapter
│           └── konsole.py    # Konsole terminal adapter
└── docs/
    ├── CHANGELOG.md          # Complete version history
    ├── VERSION.md            # Current version details
    ├── INSTALL.md            # Installation guide
    ├── QUICKSTART.md         # Quick start guide
    ├── README-FULL.md        # Complete documentation
    ├── PROJECT.md            # Project structure
    ├── PRODUCT_ANALYSIS.md   # Development cost analysis
    ├── LINUX.md              # Linux port documentation
    ├── LICENSE               # MIT License
    ├── MainMenu.png          # Screenshot
    └── screenshot_watermark.png  # Background watermark example
```

## Key Features

### Session Management
- **Session Discovery**: Scans `~/.claude/projects/` for all Claude sessions
- **Fork/Continue**: Branch conversations or resume existing sessions
- **Session Renaming**: Update session names with all metadata references
- **Session Notes**: Add notes to any session for context
- **Archive Status**: Mark sessions as archived

### Windows Terminal Integration
- **Profile Management**: Creates/manages Windows Terminal profiles for sessions
- **Background Images**: Generates custom watermark backgrounds showing:
  - Session name (48pt bold)
  - "Forked from: [parent]" (if applicable)
  - Computer:Username
  - Git branch (if applicable)
  - AI model (Opus/Sonnet/Haiku)
  - Full directory path
- **Profile Cleanup**: Removes orphaned profiles and tracks usage

### Visual Features
- **Arrow Key Navigation**: UP/DOWN to navigate, Enter to select
- **Color-Coded Display**: Activity markers, model indicators, cost coloring
- **Dynamic Pagination**: Handles hundreds of sessions with PgUp/PgDn
- **Configurable Columns**: 11 columns, toggle visibility with G key
- **Context Limit Warnings**: Shows usage % with color-coded severity

### Cost Tracking
- **Per-Session Costs**: Calculate costs based on Claude Sonnet 4.5 pricing
- **Token Analytics**: Track input, output, cache reads/writes
- **Cache Hit Rates**: Monitor prompt caching effectiveness

## Architecture

### Single-File Design
The Windows version is intentionally a single PowerShell file for easy distribution - users copy one file and run it.

### Code Organization (Claude-Menu.ps1)

```powershell
#region Utility Functions       # ~200 lines - Helper functions
#region Session Discovery       # ~400 lines - Find and parse sessions
#region Menu Display            # ~800 lines - UI rendering
#region User Input              # ~300 lines - Key handling, navigation
#region Session Operations      # ~600 lines - Continue, fork, delete
#region Fork Workflow           # ~400 lines - Fork creation process
#region WT Profile Management   # ~500 lines - Windows Terminal profiles
#region Image Generation        # ~400 lines - Background images
#region Session Mapping         # ~300 lines - Session tracking JSON
#region Profile Registry        # ~200 lines - Legacy profile tracking
#region Model Detection         # ~150 lines - Parse model from sessions
#region Background Tracking     # ~300 lines - Background image metadata
#region Validation Tests        # ~800 lines - 80 automated tests
#region Main Program            # ~200 lines - Entry point, main loop
```

### Global Variables

```powershell
$Global:MenuPath              # ~/.claude-menu/
$Global:ProfileRegistryPath   # profile-registry.json
$Global:SessionMappingPath    # session-mapping.json
$Global:BackgroundTrackingPath # background-tracking.json
$Global:ColumnConfigPath      # column-config.json
$Global:WTSettingsPath        # Windows Terminal settings.json
$Global:ClaudePath            # ~/.claude/
$Global:ClaudeProjectsPath    # ~/.claude/projects/
$Global:TokenUsageCache       # Cached token usage for performance
$Global:ModelCache            # Cached models to avoid re-parsing
$Global:WTSettingsCache       # Cached WT settings
$Global:SessionMappingCache   # Cached session mappings
```

### Data Files

All data stored in `~/.claude-menu/`:

**session-mapping.json** - Maps sessions to WT profiles
```json
{
  "version": 1,
  "sessions": [{
    "sessionId": "uuid",
    "wtProfileName": "Claude-name",
    "projectPath": "C:\\repos",
    "model": "sonnet",
    "forkedFrom": "parent-uuid",
    "gitBranch": "main",
    "notes": "Optional notes",
    "created": "2026-01-19T..."
  }]
}
```

**profile-registry.json** - Legacy profile tracking
```json
{
  "version": 1,
  "profiles": [{
    "sessionName": "name",
    "wtProfileGuid": "{guid}",
    "originalSessionId": "parent-uuid",
    "projectPath": "C:\\repos",
    "backgroundImage": "path",
    "model": "sonnet"
  }]
}
```

**background-tracking.json** - Background image metadata
```json
{
  "version": 1,
  "backgrounds": [{
    "sessionName": "name",
    "backgroundPath": "path",
    "textContent": "text on image",
    "imageType": "fork|continue|custom-text|custom-file"
  }]
}
```

**column-config.json** - Visible columns
```json
{
  "Active": true,
  "Model": true,
  "Session": true,
  "Notes": false,
  "Messages": true,
  "Created": true,
  "Modified": true,
  "Cost": true,
  "WinTerminal": true,
  "ForkedFrom": true,
  "Path": true
}
```

## Key Functions

### Session Discovery
- `Get-AllClaudeSessions` - Discovers sessions from ~/.claude/projects/
- `ConvertTo-ClaudeProjectPath` - Encodes paths (C:\repos → C--repos)
- `ConvertFrom-ClaudeProjectPath` - Decodes paths (C--repos → C:\repos)

### Menu & Navigation
- `Show-SessionMenu` - Renders the main session list
- `Get-ArrowKeyNavigation` - Handles keyboard input
- `Write-SingleMenuRow` - Renders individual session rows
- `Show-ColumnConfigMenu` - Column visibility configuration

### Session Operations
- `Start-NewSession` - Creates a new Claude session
- `Start-ContinueSession` - Resumes an existing session
- `Start-ForkSession` - Forks a session with new profile
- `Rename-ClaudeSession` - Renames with all metadata updates

### Windows Terminal
- `Add-WTProfile` - Creates a Windows Terminal profile
- `Remove-WTProfile` - Deletes a profile with cleanup
- `Get-WTProfileName` - Finds profile by session
- `Get-WTProfileDetails` - Gets profile configuration

### Image Generation
- `New-UniformBackgroundImage` - Core image generation (System.Drawing)
- `New-SessionBackgroundImage` - Wrapper for new/fork sessions
- `New-ContinueSessionBackgroundImage` - Wrapper for continued sessions

### Validation
- `Test-SystemValidation` - Runs 80 automated tests

## Menu Keys

### Main Menu
| Key | Action |
|-----|--------|
| ↑/↓ | Navigate sessions |
| Enter | Select session |
| N | New session |
| W | Win Terminal Config mode |
| H/S | Hide/Show unnamed sessions |
| Q/C | Quiet/Chatty permission mode |
| O | Cost analysis |
| D | Debug menu |
| R | Refresh |
| G | Column configuration |
| PgUp/PgDn | Page navigation |
| 1-11 | Sort by column |
| X/Esc | Exit |

### Session Options (after selecting)
| Key | Action |
|-----|--------|
| 1/C | Continue session |
| 2/F | Fork session |
| 3/D | Delete session |
| 4/M | Rename session |
| N | Add/edit notes |
| A | Archive/unarchive |
| L | Context limit guide |
| Esc | Back |

## Testing

The script includes 80 automated validation tests accessible via Debug menu (D → V):

- **Tests 1-15**: Infrastructure (PowerShell, CLI, directories, JSON)
- **Tests 16-30**: Logic (functions, encoding, sanitization)
- **Tests 31-57**: Algorithms (menu keys, sorting, edge cases)
- **Tests 58-65**: Caching system validation
- **Tests 66-80**: Regression prevention, keyboard handlers

## Linux Port (v2.0.1 - In Progress)

The `linux/` directory contains a Python port (~2,500 lines) supporting:
- **Terminals**: Kitty, Konsole, Direct (WSL/headless)
- **Shells**: Bash, Fish wrappers calling Python core
- **Image Generation**: ImageMagick with Pillow fallback
- **Menu UI**: Python curses (built-in)
- **Debug Logging**: Full debug system with file output

### Linux Files
```
linux/
├── claude-menu.py          # Main entry point (~500 lines)
├── claude-menu.sh          # Bash wrapper
├── claude-menu.fish        # Fish wrapper
├── install.sh              # Smart installer with dependency detection
├── LINUX.md                # Linux documentation
├── .gitattributes          # Force LF line endings
├── config/
│   └── default.yaml        # Default configuration
└── lib/
    ├── __init__.py
    ├── config.py           # Config management, logging (~200 lines)
    ├── session.py          # Session discovery (~250 lines)
    ├── menu.py             # Curses menu (~350 lines)
    ├── image.py            # Background generation (~150 lines)
    └── terminal/
        ├── __init__.py     # Adapter factory, WSL detection
        ├── base.py         # Abstract adapter
        ├── kitty.py        # Kitty terminal adapter
        ├── konsole.py      # Konsole terminal adapter
        └── direct.py       # Direct mode for WSL/headless
```

### Linux Installation
```bash
cd linux/
bash install.sh   # Smart installer with dependency detection
claude-menu
```

### WSL Support

**Direct Mode** (default for WSL without display):
- Sessions run in current terminal (no new windows)
- Background watermarks NOT available (limitation)
- Claude data detected from Windows home (`/mnt/c/Users/...`)

**GUI Mode** (WSL with WSLg or X server):
- Install Kitty: `sudo apt install kitty`
- Enable with: `claude-menu --terminal kitty`
- Background watermarks work

### Debug Logging (Linux)
```bash
# Enable debug mode
claude-menu --enable-debug

# Debug menu options (press 'd' or 'i'):
# 4 - Toggle debug logging on/off
# 5 - View last 50 lines of debug log
# 6 - Clear debug log
# 7 - Scan for sessions (verbose) - shows all paths checked
```

### Known Issues (In Progress)
- **Session path detection in WSL**: Working on auto-detecting Claude data in Windows home
- **Path encoding**: Claude uses `-home-user-project` format (leading hyphen)
- **Background watermarks**: Only work with GUI terminals (Kitty/Konsole)

## Development Guidelines

### Code Style
- Use PowerShell naming conventions (Verb-Noun)
- Add synopsis/description to functions
- Use `Write-ColorText` for user feedback
- Handle errors with try/catch
- Add comments for complex logic

### Adding Features
1. Add function in appropriate region
2. Update documentation (README, CHANGELOG)
3. Test with various session states
4. Add validation tests if applicable
5. Increment version

### Testing Checklist
- [ ] New session creation
- [ ] Session continuation
- [ ] Session forking (named and unnamed)
- [ ] Session deletion
- [ ] Windows Terminal profile creation
- [ ] Background image generation
- [ ] Profile management
- [ ] Menu navigation
- [ ] Error handling

## Common Issues

### Sessions Not Appearing
1. Press R to refresh
2. Enable debug mode (D)
3. Check `~/.claude-menu/debug.log`

### Background Images Not Showing
1. Open Windows Terminal Settings
2. Select your Claude profile
3. Check Background Image path and opacity (30%)
4. Disable Acrylic effects if enabled
5. Restart Windows Terminal (it caches images)

### Path Issues
- Claude encodes paths: `C:\repos` → `C--repos`
- Use Windows-style backslashes in WT settings
- Check for Linux-style forward slashes (use Diagnose option)

## Cost Pricing (Claude Sonnet 4.5)

| Token Type | Cost per 1M |
|------------|-------------|
| Input | $3.00 |
| Cache writes | $3.75 |
| Cache reads | $0.30 |
| Output | $15.00 |

## Recent Work (January 26, 2026)

### Linux Port Progress
The Linux port is functional with most features working. Recent additions:

1. **DirectAdapter for WSL/Headless** (`lib/terminal/direct.py`)
   - Runs sessions in current terminal when no GUI available
   - Auto-detected when no DISPLAY/WAYLAND_DISPLAY environment

2. **Debug Logging System** (`lib/config.py`)
   - `setup_logging(debug)` - Configures file + console handlers
   - `log_debug/log_info/log_error` - Logging functions
   - Log file: `~/.config/claude-menu/logs/debug.log`

3. **Multi-Path Session Discovery** (`lib/config.py`)
   - Checks `~/.claude/projects/` (Linux home)
   - Checks `/mnt/c/Users/<user>/.claude/projects/` (Windows home via WSL)
   - Checks `~/.config/claude/projects/` (XDG fallback)
   - `get_all_claude_paths()` returns all candidates for debugging

4. **Path Encoding Fix** (`lib/session.py`)
   - Claude uses leading hyphen: `/home/user/project` → `-home-user-project`
   - Updated `_decode_project_path()` and `_encode_project_path()`

5. **Enhanced Debug Menu** (`claude-menu.py`)
   - Option 7: Verbose session scan showing all paths
   - Option 4/5/6: Toggle/view/clear debug log
   - Shows dependency status with install instructions

### Current Issue
Session discovery in WSL - need to verify:
1. Claude data location (`~/.claude/` vs `/mnt/c/Users/.../claude/`)
2. Path encoding matches Claude's actual format
3. Sessions created in WSL are being stored correctly

### To Continue
1. Test in WSL: `cp -r /mnt/c/repos/Fork/linux ~/linux && cd ~/linux && bash install.sh`
2. Run debug scan: `claude-menu` → press 'd' → option 7
3. Check where Claude stores data: `ls -la ~/.claude/` and `ls /mnt/c/Users/*/.claude/`

## Version History Highlights

- **2.0.1**: Linux port with WSL support, debug logging, multi-path detection
- **2.0.0**: 80 validation tests, Linux port started
- **1.10.x**: Caching system, diagnostics, path fixes
- **1.9.x**: Column configuration, notes, separated headers
- **1.8.x**: Session notes, silent key handling
- **1.7.x**: Silent invalid input, consolidated menus
- **1.6.x**: Uniform menu system, Esc key support
- **1.5.x**: Pagination, session rename, tracked names
- **1.4.x**: Git integration, model display, smart images
- **1.3.x**: Arrow navigation, performance improvements
- **1.2.x**: Duplicate handling, validation on startup
- **1.1.x**: Cost tracking, debug mode, error handling
- **1.0.0**: Initial release

## Quick Commands

```powershell
# Run the session manager
powershell -ExecutionPolicy Bypass -File "Claude-Menu.ps1"

# Launch with debug mode
# (Run script, then press D to access debug menu)

# Run validation tests
# (Run script, press D, then press V)
```

## Resources

- [Claude Code Documentation](https://claude.ai/claude-code)
- [Windows Terminal Docs](https://aka.ms/terminal)
- [GitHub Repository](https://github.com/srives/WinClaudeCodeForker)
