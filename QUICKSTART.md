# Quick Start Guide

Get up and running with Windows Claude Code Forker in 2 minutes!

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
2. You'll see a menu of all your Claude sessions
3. **Type a number** to select a session
4. Choose:
   - **1** to Continue (resume the session)
   - **2** to Fork (create a branch with custom name)
   - **3** to Delete (remove the session)

## Common Tasks

### Create a New Session
Press **[N]** from the main menu

### Fork a Session
1. Select a session number
2. Press **2** for Fork
3. Enter a name for the forked session
4. Choose a model (Opus/Sonnet/Haiku)
5. Your forked session launches in a new Windows Terminal window!

### Delete a Session
1. Select a session number
2. Press **3** for Delete
3. Confirm with **Y**

### Manage Windows Terminal Profiles
Press **[W]** from the main menu to:
- Regenerate background images
- Delete profiles
- Remove backgrounds

### Refresh the Menu
Press **[R]** to reload session data

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

💡 **Tip 1**: Forked sessions get custom background images showing their name and parent

💡 **Tip 2**: Press [R] after forking to see the new session immediately

💡 **Tip 3**: Windows Terminal profiles are automatically cleaned up when deleting sessions

💡 **Tip 4**: You can fork unnamed sessions - just give them a name when prompted

💡 **Tip 5**: Background images are positioned at 60% width for better visibility

## Keyboard Shortcuts

From the main menu:

- **[1-99]** - Select session by number
- **[N]** - New session
- **[W]** - Windows Terminal config
- **[S]** - Show unnamed sessions
- **[H]** - Hide unnamed sessions
- **[R]** - Refresh menu
- **[A]** - Abort/Exit

## What Gets Created

The script creates these files in your home directory:

```
~\.claude-menu\
├── Claude-Menu.ps1              # The script
├── session-mapping.json         # Session tracking
├── profile-registry.json        # Profile registry
├── background-tracking.json     # Background tracking
└── <session-name>\
    └── background.png           # Generated images
```

**Note**: Your actual Claude sessions remain in `~\.claude\projects\`

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
