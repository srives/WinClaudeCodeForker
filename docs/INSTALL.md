# Installation Guide

## Quick Install (Recommended)

### Step 1: Copy the Script

Copy `Claude-Menu.ps1` to your Claude menu directory:

```powershell
# Create the directory if it doesn't exist
New-Item -ItemType Directory -Path "$env:USERPROFILE\.claude-menu" -Force

# Copy the script
Copy-Item "Claude-Menu.ps1" "$env:USERPROFILE\.claude-menu\"
```

### Step 2: Create Desktop Shortcut

Run this PowerShell command to create a desktop shortcut:

```powershell
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\Claude Session Manager.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$env:USERPROFILE\.claude-menu\Claude-Menu.ps1`""
$Shortcut.WorkingDirectory = "$env:USERPROFILE"
$Shortcut.IconLocation = "powershell.exe,0"
$Shortcut.Save()
Write-Host "Shortcut created on Desktop!" -ForegroundColor Green
```

### Step 3: Run

Double-click the "Claude Session Manager" shortcut on your desktop!

---

## Alternative: Command Line Launcher

### Option A: Batch File

Create `claude-fork.cmd` in a folder that's in your PATH (e.g., `C:\Windows\System32` or `C:\scripts`):

```batch
@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%USERPROFILE%\.claude-menu\Claude-Menu.ps1"
```

Then run from anywhere:
```cmd
claude-fork
```

### Option B: PowerShell Alias

Add to your PowerShell profile (`$PROFILE`):

```powershell
function Start-ClaudeSessionManager {
    & "$env:USERPROFILE\.claude-menu\Claude-Menu.ps1"
}
Set-Alias -Name claude-fork -Value Start-ClaudeSessionManager
```

Then run from anywhere:
```powershell
claude-fork
```

---

## Detailed Installation

### Prerequisites Check

Before installing, verify you have the required components:

#### 1. Check PowerShell Version
```powershell
$PSVersionTable.PSVersion
# Should be 5.1 or higher
```

#### 2. Check Windows Terminal
```powershell
Get-AppxPackage Microsoft.WindowsTerminal
# Should return package information
```

If not installed, install from:
- Microsoft Store: Search "Windows Terminal"
- Or download from: https://aka.ms/terminal

#### 3. Check Claude CLI
```powershell
claude --version
# Should return version information
```

If not installed, follow Claude Code installation instructions.

### Installation Steps

#### 1. Choose Installation Location

Pick one:
- **Recommended**: `$env:USERPROFILE\.claude-menu\Claude-Menu.ps1`
- **Alternative**: `C:\scripts\Claude-Menu.ps1`
- **Alternative**: Any folder you prefer

#### 2. Copy the Script

```powershell
# Create directory
$installPath = "$env:USERPROFILE\.claude-menu"
New-Item -ItemType Directory -Path $installPath -Force

# Copy script
Copy-Item "Claude-Menu.ps1" $installPath

# Verify
Test-Path "$installPath\Claude-Menu.ps1"
# Should return: True
```

#### 3. Test Run

```powershell
& "$env:USERPROFILE\.claude-menu\Claude-Menu.ps1"
```

You should see the main menu appear!

#### 4. Create Shortcuts (Optional)

##### Desktop Shortcut

```powershell
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\Claude Session Manager.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$env:USERPROFILE\.claude-menu\Claude-Menu.ps1`""
$Shortcut.WorkingDirectory = "$env:USERPROFILE"
$Shortcut.Save()
```

##### Start Menu Shortcut

```powershell
$WshShell = New-Object -ComObject WScript.Shell
$startMenuPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
$Shortcut = $WshShell.CreateShortcut("$startMenuPath\Claude Session Manager.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$env:USERPROFILE\.claude-menu\Claude-Menu.ps1`""
$Shortcut.WorkingDirectory = "$env:USERPROFILE"
$Shortcut.Save()
```

##### Taskbar Pin

1. Create desktop shortcut (above)
2. Right-click the shortcut
3. Select "Pin to taskbar"
4. Delete the desktop shortcut if you don't want it

---

## Troubleshooting Installation

### "Script cannot be run" error

**Problem**: PowerShell execution policy blocks scripts.

**Solution**: Run with bypass flag:
```powershell
powershell -ExecutionPolicy Bypass -File "Claude-Menu.ps1"
```

Or change execution policy permanently (not recommended):
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### "Claude CLI not found" error

**Problem**: Claude CLI is not in PATH.

**Solution**:
1. Find Claude CLI location (usually `~\.local\bin\claude.exe`)
2. Add to PATH or run from that directory
3. Or reinstall Claude CLI

### "Windows Terminal not found" error

**Problem**: Windows Terminal is not installed.

**Solution**:
1. Install from Microsoft Store
2. Or download from: https://aka.ms/terminal
3. Restart PowerShell after installation

### Script runs but shows no sessions

**Problem**: No Claude sessions exist yet.

**Solution**:
1. Create a session: `claude` (in any directory)
2. Or use: `claude --continue`
3. Press [R] to refresh the menu
4. Enable debug mode with [D] to see session discovery trace

### "No conversation found with session ID" error

**Problem**: Session exists in index but .jsonl file is missing or corrupted.

**What's New in v1.1.0**:
The script now validates session files BEFORE attempting to continue or fork, showing:
```
ERROR: Session file is missing or corrupted!

This usually happens when:
  1. The session was created but never used (empty conversation)
  2. The session .jsonl file was deleted or moved
  3. File system corruption occurred

You may want to delete this session from the menu.
```

**Solution**:
1. Delete the problematic session from the menu (option 3)
2. Or manually check `~\.claude\projects\<encoded-path>\<session-id>.jsonl`
3. Enable debug mode [D] to see detailed file validation logs

---

## Uninstallation

To completely remove the script and all data:

```powershell
# Remove script
Remove-Item "$env:USERPROFILE\.claude-menu" -Recurse -Force

# Remove shortcuts (if created)
Remove-Item "$env:USERPROFILE\Desktop\Claude Session Manager.lnk" -ErrorAction SilentlyContinue
Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Claude Session Manager.lnk" -ErrorAction SilentlyContinue

# Note: This does NOT remove your Claude sessions or Windows Terminal profiles
# You may want to manually clean up Windows Terminal profiles starting with "Claude-"
```

---

## Upgrading

To upgrade to a new version:

1. Download the new `Claude-Menu.ps1`
2. Copy over the old file:
   ```powershell
   Copy-Item "Claude-Menu.ps1" "$env:USERPROFILE\.claude-menu\" -Force
   ```
3. Run the script - it will automatically update data structures if needed

Your session data, profiles, and settings are preserved during upgrades.

### Upgrading to v1.1.0

**New Files Created:**
- `~\.claude-menu\debug.txt` - Debug mode state (on/off)
- `~\.claude-menu\debug.log` - Error and debug logging

**New Features Available:**
- Press **[$]** for cost analysis
- Press **[D]** for debug mode
- Press **[Q]** or **[C]** to toggle permission mode
- Visual box border around menu
- Session validation prevents "No conversation found" errors

**Bug Fixes:**
- Path decoding now works correctly (`C--repos-Fork` → `C:\repos\Fork`)
- Better error logging throughout the script
- JSON structure validation after parsing

No configuration changes required - just copy the new file!

---

## First Run

When you run the script for the first time:

1. It creates `~\.claude-menu\` directory
2. It checks for Claude CLI and Windows Terminal
3. It scans for existing Claude sessions
4. It initializes tracking databases
5. It displays the main menu

No manual configuration is required!

---

## Getting Help

After installation, run the script and explore:

- Main menu shows all available options
- Press [A] to abort/go back at any prompt
- Press [R] to refresh the menu
- All operations ask for confirmation before making changes

Enjoy managing your Claude sessions!
