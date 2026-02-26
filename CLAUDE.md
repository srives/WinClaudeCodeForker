# CLAUDE.md - Project Knowledge Base

## Project Overview

**Codex (X) and Claude Code (C) Session Manager with Win Terminal Forking** is a PowerShell-based unified session manager for both Claude Code CLI and OpenAI Codex CLI with deep Windows Terminal integration. It enables visual session management across both CLIs, forking workflows, cost tracking, and custom terminal backgrounds.

**Current Version:** 3.0.0 (2026-02-26)
**Author:** S. Rives
**Created:** January 2026
**Platform:** Windows 10/11 with PowerShell 5.1+

## Repository Structure

```
C:\repos\Fork\
├── Claude-Menu.ps1           # Main application (~14,000+ lines PowerShell)
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
- **Session Discovery**: Scans `~/.claude/projects/` for all Claude sessions and `~/.codex/state_*.sqlite` for Codex sessions
- **Unified Menu**: Both Claude and Codex sessions displayed together with Src column (`C` blue / `X` magenta)
- **Fork/Continue**: Branch conversations or resume existing sessions (dispatches to appropriate CLI)
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
- **Configurable Columns**: 12 columns (including Src), toggle visibility with G key
- **co$t Menu**: Press $ to show/hide cost column; hiding it skips all .jsonl parsing for instant load
- **Context Limit Warnings**: Shows usage % with color-coded severity

### Cost Tracking
- **Per-Session Costs**: Calculate costs based on Claude Sonnet 4.5 pricing
- **Token Analytics**: Track input, output, cache reads/writes
- **Cache Hit Rates**: Monitor prompt caching effectiveness
- **Lazy Loading**: Cost column can be toggled via co$t menu ($ key); when OFF, zero .jsonl parsing for instant load
- **Progress Bar**: When Cost column is ON, costs calculated with progress counter ("Calculating costs... 14/38"), then cached

### Performance Optimization
- **Hidden Column I/O Gating**: When columns are hidden (Model, ForkedFrom, Cost, Git, Notes), all associated I/O is skipped entirely
- **Cost Lazy-Loading**: Cost column OFF = zero .jsonl parsing; ON = calculated with progress bar, then cached
- **Model Detection Fast Path**: Uses cached sources (background.txt, session-mapping) instead of .jsonl parsing
- **Background Auto-Regeneration Disabled**: Background images no longer auto-regenerated on refresh (use WT Config > Diagnose manually)
- **Clear-Host Before Reload**: Prevents debug scroll issues on session reload

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
#region Validation Tests        # ~2000 lines - 158 automated tests
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
$Global:ColumnDefinitions     # Master column definitions (single source of truth)
$Global:SortColumn            # Sort property name (e.g. 'Title', 'Model')
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
  "Src": true,
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
- `Get-AllCodexSessions` - Discovers sessions from ~/.codex/state_*.sqlite
- `Get-CodexCLIPath` - Finds the Codex CLI executable path
- `Get-CodexDbPath` - Finds the Codex SQLite database path
- `Get-CodexDefaultModel` - Reads default model from Codex config.toml
- `ConvertTo-ClaudeProjectPath` - Encodes paths (C:\repos → C--repos)
- `ConvertFrom-ClaudeProjectPath` - Decodes paths (C--repos → C:\repos)
- `ConvertTo-CamelCaseTitle` - Converts Codex auto-generated titles to CamelCase (truncated to 30 chars)

### Menu & Navigation
- `Show-SessionMenu` - Renders the main session list
- `Get-ArrowKeyNavigation` - Handles keyboard input
- `Write-SingleMenuRow` - Renders individual session rows
- `Show-ColumnConfigMenu` - Column visibility configuration

### Session Operations
- `Start-NewSession` - Creates a new Claude or Codex session (prompts when Codex available)
- `Start-ContinueSession` - Resumes an existing session (dispatches to claude or codex CLI)
- `Start-ForkSession` - Forks a session with new profile (dispatches to claude or codex CLI)
- `Start-ContinueCodexSession` - Resumes a Codex session via `codex resume <id>`
- `Start-ForkCodexSession` - Forks a Codex session via `codex fork <id>`
- `Test-CodexCLI` - Checks if Codex CLI is installed and available
- `Get-CodexTokenUsage` - Reads aggregate token counts from Codex SQLite database
- `Start-WTClaude` - Launches Claude in WT (writes commandline to profile, avoids WT argument parsing bugs)
- `Rename-ClaudeSession` - Renames with all metadata updates
- `Find-DeadSessions` - Finds sessions whose .jsonl files no longer exist
- `Find-OrphanedWTProfiles` - Finds WT profiles (Claude-*/Codex-*) with no matching session
- `Show-PurgeMenu` - Bulk archive/delete dead sessions and remove orphaned WT profiles
- `Get-CreateProfileChoice` - Shared Y/N prompt for creating WT profiles (used by Continue and unnamed session paths)

### Windows Terminal
- `Get-SessionWTTitle` - Derives WT profile title from session (handles Codex CamelCase titles, sanitization, truncation)
- `Add-WTProfile` - Creates a Windows Terminal profile
- `Remove-WTProfile` - Deletes a profile with cleanup
- `Get-WTProfileName` - Finds profile by session
- `Get-WTProfileDetails` - Gets profile configuration

### Image Generation
- `New-UniformBackgroundImage` - Core image generation (System.Drawing)
- `New-SessionBackgroundImage` - Wrapper for new/fork sessions
- `New-ContinueSessionBackgroundImage` - Wrapper for continued sessions

### Validation
- `Test-SystemValidation` - Runs 158 automated tests (results can be copied to clipboard: errors only, warnings+errors, or all)

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
| $ | co$t menu (show/hide cost column, generate cost table) |
| O | Cost analysis |
| P | Purge & Cleanup (dead sessions + orphaned WT profiles) |
| D | Debug menu |
| R | Refresh |
| G | Column configuration |
| PgUp/PgDn | Page navigation |
| 1-9 | Sort by Nth visible column |
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

The script includes 158 automated validation tests accessible via Debug menu (D → V):

- **Tests 1-15**: Infrastructure (PowerShell, CLI, directories, JSON)
- **Tests 16-30**: Logic (functions, encoding, sanitization)
- **Tests 31-57**: Algorithms (menu keys, sorting, edge cases)
- **Tests 58-65**: Caching system validation
- **Tests 66-80**: Regression prevention, keyboard handlers
- **Tests 81-89**: Codex integration (CLI detection, session discovery, SQLite reading)
- **Tests 90-108**: Purge/cleanup, profile creation, array wrapping, Codex model/timestamp fixes
- **Tests 109-138**: Functional tests that EXECUTE real functions with mock inputs (Format-Cost, Format-TokenCount, ConvertTo-CamelCaseTitle, Get-SessionCost, Get-SessionWTTitle, ConvertTo-Hashtable, Test-JsonStructure, Get-DynamicPathWidth, etc.)
- **Tests 139-148**: Data integrity tests (no duplicate session IDs, ColumnDefinitions matches config, WT profile backgrounds exist)
- **Tests 149-158**: Regression tests (no bare Write-Host in discovery, no blank line padding, both WT prefixes checked, .ps1 wrapping, Clear-Host before reload)

**Validation results can be copied to clipboard:** Errors only, Warnings+Errors, or All results.

### Test Philosophy
- Every test section has a RULE comment: "When a test fails, examine the PRODUCTION CODE first"
- Machine-independent: Tests logic, not user configuration
- Functional tests EXECUTE real functions with mock inputs (not just checking function existence)
- Regression prevention: Tests that would have caught bugs we fixed
- Data integrity: Verifies internal consistency of session data and column definitions

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

## Recent Work (February 26, 2026)

### v3.0.0 - Codex CLI Integration, Performance Optimization, 158 Tests

1. **Unified Claude + Codex Session Menu**
   - Both Claude and OpenAI Codex CLI sessions appear together in the main menu
   - New "Src" column shows `C` (Claude, blue) or `X` (Codex, magenta) for each session
   - Codex sessions discovered from SQLite database (`~/.codex/state_*.sqlite`)
   - Title bar shows "Codex (X) and Claude Code (C)" with color-coded markers
   - Session stats line split into two color-coded segments: Claude stats in blue, Codex stats in magenta (each with own cost total)
   - Cost totals show in header when Cost column is on, with progress bar "Calculating costs... 14/38"
   - About screen shows SYS1000.NET as clickable link (OSC 8 hyperlink)

2. **Codex Session Operations**
   - Continue dispatches to `codex resume <id>` for Codex sessions
   - Fork dispatches to `codex fork <id>` for Codex sessions
   - New session prompts "Claude | codeX | Abort" when Codex CLI is detected
   - CamelCase titles for Codex sessions (e.g. [DontFixItJustCheckCreate])
   - Codex model read from rollout JSONL `turn_context` entries (not generic "openai")
   - Codex timestamps parsed as Unix epoch integers

3. **Codex WT Profiles + Background Watermarks**
   - Continue (codex resume) now creates/reuses a `Codex-<name>` WT profile with background watermark
   - Fork (codex fork) prompts for a name, generates fork background image, creates `Codex-<name>` WT profile
   - Codex WT profiles use `Codex-` prefix (vs `Claude-` for Claude sessions)
   - `Get-SessionWTTitle` shared function for WT profile title derivation (handles Codex CamelCase, sanitization, truncation)
   - All 6 call sites updated to pass Source and use `Get-SessionWTTitle`
   - `Get-WTProfileName` accepts -Source parameter, checks both Claude-/Codex- prefixes
   - `Get-CreateProfileChoice` shared Y/N prompt for profile creation
   - Named sessions without profiles get explicit Y/N prompt on Continue

4. **Performance Optimization**
   - co$t menu ($ key): sub-menu to show/hide cost column and generate cost table
   - When Cost column is OFF: zero .jsonl parsing, instant load
   - When Cost column is ON: costs calculated with progress counter, then cached
   - Hidden columns skip all I/O: Model, ForkedFrom, Cost, Git, Notes columns all gated by visibility
   - Background auto-regeneration disabled for performance (use WT Config > Diagnose manually)
   - Model detection uses fast cached sources (background.txt, session-mapping) instead of .jsonl parsing
   - Clear-Host before session reload prevents debug scroll issues
   - Cursor positioning for "Last command" display instead of blank line padding

5. **Display Changes**
   - Title: "Codex (X) and Claude Code (C) Session Manager with Win Terminal Forking"
   - Debug/Permissions moved to "Current directory" line
   - Session stats line color-coded: Claude in blue, Codex in magenta, with per-CLI cost totals

6. **Claude-Specific Feature Labeling**
   - Quiet/Chatty mode: "CLAUDE CODE: SWITCH TO QUIET/CHATTY MODE?" with note "(This does not affect Codex sessions.)"
   - Trusted session prompt: "Claude Code: Do you want a trusted session..."
   - Model choice prompt: "Select Claude Code model:"

7. **Purge & Cleanup Enhancements** (`Show-PurgeMenu`, `Find-OrphanedWTProfiles`)
    - Renamed from "PURGE DEAD SESSIONS" to "PURGE & CLEANUP"
    - Two sections: [1] Dead Sessions, [2] Orphaned WT Profiles
    - W key to bulk remove orphaned Windows Terminal profiles (Claude-* and Codex-*)
    - `Find-OrphanedWTProfiles` function checks Claude-* and Codex-* profiles

8. **Bug Fixes**
   - `Format-Cost`: `"<$0.01"` was returning `<.01` (PowerShell $0 variable interpolation) -- fixed to single quotes
   - Token count overflow: `[int]` to `[long]` for accumulators and `Format-TokenCount` parameter (prevents crash at 2.1B+ tokens)
   - `Format-TokenCount`: added B (billion) suffix for counts over 1B
   - PowerShell array wrapping: all `Get-AllClaudeSessions`/`Get-AllCodexSessions` calls wrapped in `@()` (fixes `.Count` returning `$null` for single items)
   - `ConvertTo-CamelCaseTitle`: truncation increased from 20 to 30 chars for more meaningful titles
   - `Set-BackgroundFromFile`: now creates companion .txt file (fixes pairing warnings)
   - Removed stray `Write-Host ""` in `Get-AllClaudeSessions` (caused blank lines on refresh)
   - `Get-ModelFromBackgroundTxt`: needs to handle Codex- prefix (flagged as warning)

9. **Validation Tests Expanded to 158**
   - Functional tests that EXECUTE real functions with mock inputs (Format-Cost, Format-TokenCount, ConvertTo-CamelCaseTitle, Get-SessionCost, Get-SessionWTTitle, ConvertTo-Hashtable, Test-JsonStructure, Get-DynamicPathWidth, etc.)
   - Data integrity tests (no duplicate session IDs, ColumnDefinitions matches config, WT profile backgrounds exist)
   - Regression tests (no bare Write-Host in discovery, no blank line padding, both WT prefixes checked, .ps1 wrapping, Clear-Host before reload)
   - Every test section has RULE comment: "When a test fails, examine the PRODUCTION CODE first"
   - Validation results can be copied to clipboard: Errors only, Warnings+Errors, or All results

### Previous: v2.1.1 - Claude CLI .exe Compatibility, Purge, Column Sort Fix (February 24, 2026)

1. **Claude CLI .exe Launch Fix** (`Start-WTClaude`)
   - Claude CLI updated from `.cmd` shim to native `claude.exe` (Feb 2026)
   - Windows Terminal cannot pass .exe paths + arguments through its command line
   - Fix: writes full claude command into WT profile's `commandline` field in settings.json before launch
   - Validates claude path exists before attempting launch
   - Invalidates WT settings cache after writes

2. **Purge Dead Sessions** (`Find-DeadSessions`, `Show-PurgeMenu`)
   - Press P in main menu to scan for sessions whose .jsonl files are missing
   - Lists dead sessions (excludes already-archived)
   - Bulk Archive All or Delete All with confirmation
   - Dead sessions show skull (U+2620) in Active column

3. **Column Sort Fix** (`$Global:ColumnDefinitions`)
   - Sort keys now map to Nth VISIBLE column, not hardcoded column numbers
   - Master column definitions array is single source of truth for headers, widths, sort properties
   - Same column press toggles direction; new column starts ascending
   - Eliminated all hardcoded column-to-number mapping

4. **Bug Fixes**
   - Enter key no longer confirms bulk deletion in Purge (only Y)
   - Unique .cmd filenames for profile-less launches (race condition fix)
   - WT settings cache invalidated after profile commandline updates

### Previous: Linux Port Progress (January 26, 2026)
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

- **3.0.0**: Codex CLI integration, unified Claude + Codex menu, performance optimization (hidden columns skip I/O, cost lazy-loading), co$t menu, 158 tests with clipboard copy, CamelCase titles, bug fixes (Format-Cost, token overflow, array wrapping)
- **2.1.1**: Claude .exe launch fix, Purge dead sessions, column sort fix, bug fixes
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
