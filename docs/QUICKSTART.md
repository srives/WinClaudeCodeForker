# Quick Start Guide

Get up and running with Windows Claude Code Forker in 2 minutes!

## What's New in v1.4.0
- Git branch shown on background images and in session info
- Model name (Opus/Sonnet/Haiku) displayed on background images
- Smart conflict resolution auto-overwrites orphaned background images
- Choose directory when creating new sessions
- More abort options with proper cleanup

## One-Line Install

Copy and paste this into PowerShell:

```powershell
# Create directory and copy script
New-Item -ItemType Directory -Path "$env:USERPROFILE\.claude-menu" -Force | Out-Null
Copy-Item "C:\repos\WinClaudeCodeForker\Claude-Menu.ps1" "$env:USERPROFILE\.claude-menu\"

# Create desktop shortcut
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\Claude Session Manager.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$env:USERPROFILE\.claude-menu\Claude-Menu.ps1`""
$Shortcut.WorkingDirectory = "$env:USERPROFILE"
$Shortcut.Save()

Write-Host "`n✓ Installation complete! Look for 'Claude Session Manager' on your desktop." -ForegroundColor Green
```

## First Use

1. **Double-click** "Claude Session Manager" on your desktop
2. You'll see a menu of all your Claude sessions (including unnamed ones)
3. **Use UP/DOWN arrows** to navigate between sessions
4. **Press Enter** to select a session
5. Choose:
   - **1** to Continue (resume the session with existing profile, or create profile if needed)
   - **2** to Fork (create a branch with custom name)
   - **3** to Delete (remove the session)

## Common Tasks

### Create a New Session
1. Press **N** from the main menu (no Enter required)
2. Choose to use current directory or set a different one
3. Enter session name
4. Choose model (Opus/Sonnet/Haiku)
5. Choose trusted session mode or default permissions

### Fork a Session
1. Use **UP/DOWN arrows** to navigate to a session
2. Press **Enter** to select it
3. Press **2** for Fork
4. Enter a name for the forked session
5. Choose a model (Opus/Sonnet/Haiku)
6. Your forked session launches in a new Windows Terminal window!

### Delete a Session
1. Use **UP/DOWN arrows** to navigate to a session
2. Press **Enter** to select it
3. Press **3** for Delete
4. Confirm with **Y**

### Manage Windows Terminal Profiles
Press **W** from the main menu to:
- Toggle between showing all sessions or profiles only (A/P keys)
- Create Windows Terminal profiles for sessions that don't have them
- Regenerate background images
- Delete profiles
- Remove backgrounds

### View Cost Analysis
Press **O** to see:
- Cost per session
- Token usage breakdown
- Cache hit percentages
- Total costs and averages

### Enable Debug Mode
Press **D** to access debug menu with options:
1. Toggle Debug flag (ON/OFF)
2. Open debug log in Notepad
3. Show debug instructions
4. Abort (return to main menu)

When enabled, detailed session discovery and operation traces are written to the log.

### Toggle Permission Mode
- Press **Q** for Quiet mode (bypass prompts) - Recommended
- Press **C** for Chatty mode (ask each time)

### Refresh the Menu
Press **R** to reload session data

## Menu Legend

**Activity Indicators:**
- `X` = Active within 5 minutes
- `x` = Active within 30 minutes
- `x?` = Active within 1 hour
- `?` = Active within 5 hours

**Session Names:**
- `session-name` = Named session
- `[fork-name]` = Newly forked (not yet indexed by Claude)
- `(unnamed)` = Session without a custom name

**Fork Column:**
- `<- parent` = Forked from parent session

## Tips

💡 **Tip 1**: Use arrow keys to navigate - it's instant! No lag or recalculation

💡 **Tip 2**: All commands are single-key (no Enter needed) - just press N, W, O, D, R, X, etc.

💡 **Tip 3**: Forked sessions get custom background images showing their name and parent

💡 **Tip 4**: Press R after forking to see the new session immediately

💡 **Tip 5**: Windows Terminal profiles are automatically cleaned up when deleting sessions

💡 **Tip 6**: You can fork unnamed sessions - just give them a name when prompted

💡 **Tip 7**: Background images are positioned at 60% width for better visibility

💡 **Tip 8**: Press O regularly to monitor your Claude API costs per session

💡 **Tip 9**: Enable debug mode with D if sessions aren't appearing correctly

💡 **Tip 10**: The script validates session files before operations to prevent errors

💡 **Tip 11**: Total cost appears in the status line at the top of the menu

💡 **Tip 12**: Use Quiet mode (Q) for faster workflow (bypasses permission prompts)

💡 **Tip 13**: All sessions (including unnamed) are shown by default - no need to press S

💡 **Tip 14**: Background images now show git branch and model name for instant context

💡 **Tip 15**: Choose your working directory when creating new sessions

💡 **Tip 16**: Orphaned background images (not used by any profile) are automatically overwritten

## Keyboard Shortcuts

**Navigation:**
- **UP/DOWN arrows** - Navigate between sessions (instant)
- **Enter** - Select the highlighted session

**Single-Key Commands** (no Enter required):
- **N** - New session
- **W** - Windows Terminal config
- **S** - Show unnamed sessions
- **H** - Hide unnamed sessions
- **O** - cOst analysis report
- **D** - Debug mode toggle
- **Q** - Quiet mode (bypass permissions)
- **C** - Chatty mode (ask permissions)
- **R** - Refresh menu
- **X** - eXit

## What Gets Created

The script creates these files in your home directory:

```
~\.claude-menu\
├── Claude-Menu.ps1              # The script (~4000 lines)
├── session-mapping.json         # Session tracking
├── profile-registry.json        # Profile registry
├── background-tracking.json     # Background tracking
├── debug.txt                    # Debug mode state
├── debug.log                    # Error and debug logging
└── <session-name>\
    └── background.png           # Generated images
```

**Note**: Your actual Claude sessions remain in `~\.claude\projects\`

**New in v1.4.0:**
- Git branch detection and display
- Model name on background images
- Smart conflict resolution for background images
- Directory selection for new sessions

**New in v1.1.0:**
- `debug.txt` - Stores debug mode on/off state
- `debug.log` - Contains all error logs and debug traces (when enabled)

## Need Help?

- Press **[A]** at any prompt to go back
- All destructive actions require confirmation
- Read README.md for detailed documentation
- Check INSTALL.md for troubleshooting

## Next Steps

Once you're comfortable with the basics:

1. Try customizing background images (press [W])
2. Explore fork genealogy tracking
3. Set up quick launch with a batch file
4. Customize Windows Terminal color schemes for your profiles

Happy forking! 🍴
