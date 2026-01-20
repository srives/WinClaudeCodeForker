# Quick Start Guide: Launch and Manage Claude Code Sessions in Windows Terminal

1. Download this repo
2. Run inst.cmd
3. Optional: Put fork.cmd in your PATH
4. Run fork.cmd whenever you want to manage Claude sessions


# Windows Claude Code Forker

Have you ever been working in Claude Code CLI and wished you could easily see and manage all your sessions across projects?
Have you ever lost track of which session you were working on, or wanted to fork a session into its own dedicated terminal 
window with a custom background?

This is for you. It is a PowerShell-based session manager for Claude Code CLI with Windows Terminal integration--a nice way 
to start Claude Code and see everything you are working on across all sessions across your hard drive.

## Features

- 🔍 **Session Discovery** - Automatically finds all Claude sessions across projects
- 🍴 **Fork Sessions** - Create branching sessions with custom Windows Terminal profiles
- 🎨 **Custom Backgrounds** - Generate or use custom background images for each session
- 📊 **Activity Tracking** - See which sessions are active with real-time indicators
- 🔗 **Fork Tracking** - View session genealogy and relationships
- 🗑️ **Session Management** - Delete sessions and automatically clean up profiles
- ⚙️ **Profile Management** - Manage Windows Terminal profiles and background images

## See It In Action

### Never Lose Context - Visual Session Identification

Each forked session gets a custom Windows Terminal profile with a watermark showing the session name and origin. No more "wait, which Claude window is this?"

![Windows Terminal with session watermark](screenshot_watermark.png)
*Windows Terminal showing session context directly in the background - instantly know which project you're working on*

### Interactive Session Management

Launch the menu to see all your Claude sessions across all projects, with fork relationships, activity indicators, and quick actions.

![Main menu showing session list](MainMenu.png)
*Main menu with session discovery, fork tracking, and Windows Terminal profile management*

### Why This Matters

When you're:
- 🔀 Testing different approaches in parallel sessions
- 🎯 Managing multiple client projects simultaneously
- 🧪 Comparing AI responses to the same prompt
- 📋 Keeping experimental work separate from production

You need **instant visual context** - and that's exactly what the background watermarks provide. One glance tells you which session you're in.

## Prerequisites

- **Windows 10/11**
- **PowerShell 5.1+** (pre-installed on Windows)
- **Windows Terminal** ([Download](https://aka.ms/terminal))
- **Claude Code CLI** (Anthropic's official CLI tool)

## Installation

### Single-File Install

1. **Copy the script** to any location you prefer:
   ```powershell
   # Option 1: Copy to your home directory
   Copy-Item Claude-Menu.ps1 $env:USERPROFILE\.claude-menu\

   # Option 2: Copy to a scripts folder
   Copy-Item Claude-Menu.ps1 C:\scripts\
   ```

2. **Create a shortcut** (optional but recommended):

   **Desktop Shortcut:**
   - Right-click Desktop → New → Shortcut
   - Target: `powershell.exe -ExecutionPolicy Bypass -File "C:\path\to\Claude-Menu.ps1"`
   - Name: "Claude Session Manager"

   **Or use PowerShell to create it:**
   ```powershell
   $WshShell = New-Object -ComObject WScript.Shell
   $Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\Claude Session Manager.lnk")
   $Shortcut.TargetPath = "powershell.exe"
   $Shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$env:USERPROFILE\.claude-menu\Claude-Menu.ps1`""
   $Shortcut.WorkingDirectory = "$env:USERPROFILE"
   $Shortcut.Save()
   ```

3. **Run from anywhere:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File "C:\path\to\Claude-Menu.ps1"
   ```

### Quick Launch with Batch File

Create a `claude-fork.cmd` file anywhere:

```batch
@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%USERPROFILE%\.claude-menu\Claude-Menu.ps1"
```

Then you can run it from any terminal by typing `claude-fork`.

## Usage

### Main Menu

When you launch the script, you'll see an interactive menu showing all your Claude sessions:

```
Claude Code Session Forker, S. Rives, 2026
(Note: Newly forked sessions shown in [brackets] until Claude CLI indexes them)

#   Active Model   Session                        Path       Messages  Created       Modified      Win Terminal           Fork
1   X      sonnet  my-project                     C:\repos   45        2026-01-18    2026-01-19    Claude-my-project
2          opus    [test-fork]                    C:\repos   0         2026-01-19    2026-01-19    Claude-test-fork       <- my-project
3          haiku   (unnamed)                      C:\temp    12        2026-01-17    2026-01-17    -

[1..3] fork or join, [N] New Session, [W] Win Terminal Config, [S] Show unnamed sessions, [R] Refresh, [A] Abort:
```

**Activity Indicators:**
- `X` = Modified within 5 minutes
- `x` = Modified within 30 minutes
- `x?` = Modified within 1 hour
- `?` = Modified within 5 hours
- (blank) = Older than 5 hours

### Session Options

When you select a session number, you get options:

```
Session options
Session: my-project
Session ID: 12345-67890-abcdef...

1. Continue - Resume in same terminal
2. Fork - Create new branch with custom Windows Terminal profile
   (Will fork session: 12345-67890-abcdef...)
3. Delete session

Enter choice [1-3], [A] Abort:
```

### Forking a Session

1. Select session number
2. Choose option 2 (Fork)
3. Enter a name for the new fork
4. Background image is generated automatically
5. Windows Terminal profile is created
6. Select model (Opus/Sonnet/Haiku)
7. New session launches in its own Windows Terminal window

### Windows Terminal Profile Management

Press `[W]` to manage Windows Terminal profiles:

**Profile Management Menu:**
- Regenerate background image (from session, file, or text)
- Delete Windows Terminal profile
- Remove background image from profile

### Deleting Sessions

Choose option 3 from the session options menu. You'll see a confirmation:

```
WARNING: You are about to delete the following session:

  Session: test-fork
  ID: 12345-67890-abcdef...
  Path: C:\repos
  Windows Terminal Profile: Claude-test-fork

This action cannot be undone!

Are you sure? (Y/N):
```

The script automatically:
- Removes session from Claude's index
- Deletes the .jsonl file
- Cleans up tracking data
- Removes Windows Terminal profile (if not used by other sessions)
- Deletes background images

## Features in Detail

### Fork Tracking

The script maintains a genealogy of forked sessions. When you fork a session, it tracks the parent-child relationship and displays it in the main menu:

```
Fork
<- parent-session
```

### Background Images

Forked sessions get custom background images showing:
- Session name
- "forked from: [parent name]"
- Positioned at 60% width for visibility

You can customize backgrounds:
- **Regenerate from session** - Recreate the original
- **Use custom image** - Provide your own image file
- **Generate from text** - Create with custom text overlay

### Session Mapping

The script tracks sessions that Claude CLI hasn't indexed yet, showing them in `[brackets]` until they appear in Claude's official index.

## File Structure

The script creates and manages these files:

```
C:\Users\<username>\.claude-menu\
├── Claude-Menu.ps1                  # Main script
├── session-mapping.json             # Session to WT profile mapping
├── profile-registry.json            # Profile registry (legacy)
├── background-tracking.json         # Background image tracking
└── <session-name>\
    └── background.png               # Generated background images
```

## Troubleshooting

### Background images not showing
1. Check Windows Terminal Settings → Profiles → [Your Profile]
2. Verify 'Background image path' is set
3. Adjust 'Background image opacity' (default: 30%)
4. Ensure 'useAcrylic' is disabled
5. Try 'Text antialiasing' set to 'grayscale'

### Script won't run
```powershell
# Check execution policy
Get-ExecutionPolicy

# If restricted, run with bypass:
powershell -ExecutionPolicy Bypass -File "Claude-Menu.ps1"
```

### Sessions not appearing
- Press `[R]` to refresh the menu
- Ensure Claude CLI has created sessions (`claude --continue`)
- Check if sessions exist in `~\.claude\projects\`

## Technical Details

### Path Encoding

Claude encodes project paths:
- `C:\repos` → `C--repos`
- Pattern: Remove colon, replace backslash with double-dash

### Session Files

Claude stores sessions at:
```
~\.claude\projects\<encoded-path>\<session-id>.jsonl
```

Each project has a `sessions-index.json` manifest.

### Windows Terminal Integration

Profiles are created in:
```
%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
```

The script automatically backs up before modifications.

## License

Created by S. Rives, 2026

## Support

For issues or questions, please check:
- Claude Code documentation: [claude.com/claude-code](https://claude.com/claude-code)
- Windows Terminal docs: [aka.ms/terminal](https://aka.ms/terminal)
