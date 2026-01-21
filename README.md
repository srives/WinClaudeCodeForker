# Quick Start Guide:

[Download WinClaudeForker.exe Installer Here](https://github.com/srives/WinClaudeCodeForker/releases/tag/name)

# Windows Claude Code Forker

> Visual session management for Claude Code CLI. Never lose track of your sessions again.

![Main Menu](docs/MainMenu.png)

**The Problem:** Working with multiple Claude Code sessions? Can't remember which terminal window is which project? No visual way to see all your sessions?

**The Solution:** This tool gives you visual session management, one-click forking with custom backgrounds, git branch awareness, and instant context at a glance.

![Session with Watermark](docs/screenshot_watermark.png)
*Each session gets a custom background showing session name, git branch, and model - instant context*

---

## ✨ Key Features

- 🔍 **Session Discovery** - See all Claude sessions across your entire drive
- 🍴 **Fork Sessions** - Branch conversations with custom Windows Terminal profiles
- 🎨 **Visual Context** - Custom backgrounds show session name, git branch, and AI model
- 🌿 **Git Integration** - Automatically detects and displays current branch
- ⚡ **Arrow Navigation** - Instant keyboard navigation with no lag
- 💰 **Cost Tracking** - Monitor API usage per session
- 🤖 **Model Tracking** - See which model (Opus/Sonnet/Haiku) each session uses
- 🐛 **Debug Mode** - Comprehensive logging for troubleshooting

---

## 🚀 Quick Install

**Option 1: Download Installer**
1. Download [WinClaudeForker.exe](https://github.com/srives/WinClaudeCodeForker/releases)
2. Run the installer
3. Look for "Claude Session Manager" on your desktop

**Option 2: Manual Install**
```powershell
# Copy script to your profile
New-Item -ItemType Directory -Path "$env:USERPROFILE\.claude-menu" -Force
Copy-Item "Claude-Menu.ps1" "$env:USERPROFILE\.claude-menu\"

# Create desktop shortcut
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\Claude Session Manager.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$env:USERPROFILE\.claude-menu\Claude-Menu.ps1`""
$Shortcut.Save()
```

**Requirements:** Windows 10/11 • PowerShell 5.1+ • Windows Terminal • Claude Code CLI

---

## 🎯 Quick Start

1. Launch "Claude Session Manager"
2. See all your sessions with activity indicators
3. Use **↑↓ arrows** to navigate
4. Press **Enter** to select a session
5. Choose: **Continue** | **Fork** | **Delete**

**Keyboard Shortcuts:**
- `N` - New session
- `W` - Windows Terminal config
- `O` - Cost analysis
- `D` - Debug mode
- `R` - Refresh
- `X` - Exit

---

## 📸 What You Get

### Main Menu
```
Claude Code Session Forker, S. Rives, v.2026.1.20
Current directory: C:\repos\myproject

+------------------------------------------------------------------------------+
| #  Active Model   Session           Messages  Created    Modified      Cost |
+------------------------------------------------------------------------------+
| 1  X      sonnet  my-project        45        01/18...   01/19...     $1.20 |
| 2         opus    [test-fork]       0         01/19...   01/19...     $0.00 |
| 3         haiku   api-redesign      28        01/17...   01/18...     $2.45 |
+------------------------------------------------------------------------------+

New Session | Win Terminal Config | Hide Unnamed | Cost | Debug | Refresh | eXit
```

### Session Options
```
Session: my-project
Session ID: 12345-67890-abcdef...
Path: C:\repos\myproject
Git Branch: main

1. Continue - Resume in same terminal
2. Fork - Create new branch with custom profile
3. Delete session
```

### Background Images Show
- **Line 1:** Session name
- **Line 2:** Forked from (if applicable)
- **Line 3:** Git branch
- **Line 4:** AI model

---

## 🆕 What's New in v1.4.0

- 🌿 Git branch detection and display
- 🤖 Model name on background images
- 🎨 Smart conflict resolution (auto-overwrites orphaned backgrounds)
- 📁 Directory selection for new sessions
- 🚫 Enhanced abort options with cleanup

[Full Changelog →](docs/CHANGELOG.md)

---

## 📚 Documentation

- **[Quick Start Guide](docs/QUICKSTART.md)** - Get running in 2 minutes
- **[Full Documentation](docs/README-FULL.md)** - Complete feature reference
- **[Installation Guide](docs/INSTALL.md)** - Detailed setup instructions
- **[Changelog](docs/CHANGELOG.md)** - Version history
- **[Project Info](docs/PROJECT.md)** - Development notes

---

## 🤔 Why This Exists

Claude Code CLI is powerful but lacks visual session management. When you're:
- 🔀 Testing different approaches in parallel
- 🎯 Managing multiple projects simultaneously
- 🧪 Comparing AI responses
- 📋 Keeping experimental work separate

You need **instant visual context**. This tool provides it.

---

## 🛠️ How It Works

- Discovers Claude sessions by scanning `~\.claude\projects\`
- Creates Windows Terminal profiles with custom GUIDs
- Generates PNG backgrounds (1920x1080) with System.Drawing
- Tracks session relationships in JSON files
- Integrates with git to show branch information
- Parses .jsonl files to calculate token costs

**Built with:** PowerShell • Windows Terminal API • Claude Code CLI • Git • System.Drawing

---

## 🐛 Troubleshooting

**Sessions not appearing?**
- Press `R` to refresh
- Enable debug mode with `D`
- Check `~\.claude-menu\debug.log`

**Background images not showing?**
- Check Windows Terminal Settings → Profile → Background Image
- Ensure opacity is set (default: 30%)
- Disable Acrylic effects

**Script won't run?**
```powershell
powershell -ExecutionPolicy Bypass -File "Claude-Menu.ps1"
```

[More troubleshooting →](docs/README-FULL.md#troubleshooting)

---

## 📊 Cost Tracking

View detailed cost analysis per session:
```
Session                    Cost    Input   Output  Cached  Hit%
my-big-project            $15.23   2.5M    850K    12.3M   89%
frontend-refactor          $8.45   1.2M    420K     8.1M   87%
api-design                 $3.67   780K    190K     4.2M   84%
```

Uses Claude Sonnet 4.5 pricing: $3/$3.75/$0.30/$15 per 1M tokens

---

## 🤝 Contributing

This project was built with Claude Code's help - a meta tool for managing Claude itself!

Issues, suggestions, and contributions are welcome.

---

## 📝 [License](docs/LICENSE)

Created by S. Rives, 2026

Limited License (see the above document for more).

---

## 🔗 Links

- [Claude Code Documentation](https://claude.com/claude-code)
- [Windows Terminal Docs](https://aka.ms/terminal)
- [GitHub Releases](https://github.com/srives/WinClaudeCodeForker/releases)

---

**Star ⭐ this repo if it makes your Claude Code workflow better!**
