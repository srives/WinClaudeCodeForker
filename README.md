# Windows Claude Code Forker v1.10.2

> **Visual session management for Claude Code CLI**
> Never lose track of your conversations. See all your sessions, fork with confidence, track your costs.

![Main Menu](docs/MainMenu.png)

---

## 🎯 The Problem

Working with multiple Claude Code sessions? Can't remember which terminal is which project? No visual way to track your conversations? Wondering how much you're spending on API calls?

## ✨ The Solution

**Windows Claude Code Forker** gives you instant visual context for all your Claude sessions:
- 📋 See all sessions at a glance with sortable columns
- 🍴 Fork conversations with custom Windows Terminal backgrounds
- 💰 Track costs per session with detailed analytics
- 🌿 Git branch awareness in every session
- ⚡ Lightning-fast arrow-key navigation
- 🎨 Custom backgrounds showing session context

![Session with Watermark](docs/screenshot_watermark.png)
*Each forked session gets a unique background: session name, parent, git branch, and model*

---

## 🚀 Quick Install

### Option 1: Installer (Recommended)
1. Download **[WinClaudeForker.exe](https://github.com/srives/WinClaudeCodeForker/releases)**
2. Run the installer
3. Launch "Claude Session Manager" from your desktop

### Option 2: Manual Install
```powershell
# Create directory
New-Item -ItemType Directory -Path "$env:USERPROFILE\.claude-menu" -Force

# Copy script
Copy-Item "Claude-Menu.ps1" "$env:USERPROFILE\.claude-menu\"

# Create desktop shortcut
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\Claude Session Manager.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$env:USERPROFILE\.claude-menu\Claude-Menu.ps1`""
$Shortcut.Save()
```

**Requirements:**
- Windows 10/11
- PowerShell 5.1+
- Windows Terminal
- Claude Code CLI

---

## 💡 Key Features

### Session Management
- **All Sessions Visible** - Scans your entire drive for Claude sessions
- **Fork with Context** - Branch conversations with custom Windows Terminal profiles
- **Archive & Notes** - Tag sessions with notes, archive old conversations
- **Rename Anytime** - Rename sessions and update all references automatically

### Visual Intelligence
- **Custom Backgrounds** - Each fork gets a unique background showing:
  - Session name
  - Parent session (if forked)
  - Git branch
  - AI model (Opus/Sonnet/Haiku)
  - Project directory
- **Activity Markers** - See which sessions are active at a glance
- **Git Integration** - Automatically detects and displays git branches

### Cost Tracking
- **Per-Session Costs** - See exactly how much each conversation costs
- **Token Analytics** - Track input, output, and cache usage
- **Cache Hit Rates** - Monitor prompt caching effectiveness
- **Total Spend** - Know your total API spend across all sessions

### Professional UX
- **Arrow Navigation** - Instant keyboard navigation with ↑↓ keys
- **Dynamic Columns** - Customize which columns appear (11 configurable columns)
- **Pagination** - Handle hundreds of sessions with screen-aware pagination
- **Universal Defaults** - Press Enter for default action in any menu
- **Silent Validation** - 40 automated tests protect against bugs

---

## ⌨️ Quick Start

### Launch & Navigate
```
Launch → See all sessions → Use ↑↓ to navigate → Press Enter
```

### Keyboard Shortcuts
| Key | Action |
|-----|--------|
| **↑↓** | Navigate sessions |
| **Enter** | Select / Default action |
| **N** | New session |
| **W** | Windows Terminal config |
| **H** | Hide unnamed sessions |
| **S** | Show unnamed sessions |
| **O** | Cost analysis |
| **D** | Debug mode |
| **R** | Refresh |
| **G** | Column configuration |
| **X** | Exit |
| **1-11** | Sort by column |

### After Selecting a Session
```
Continue → Resume in current terminal
Fork → Create branch with custom background
Delete → Remove session with cleanup
Rename → Update session name everywhere
Notes → Add annotations
```

---

## 📊 Cost Analysis

View detailed cost breakdown for all sessions:

```
Session                    Cost    Input   Output  Cached  Hit%
my-big-project            $15.23   2.5M    850K    12.3M   89%
frontend-refactor          $8.45   1.2M    420K     8.1M   87%
api-design                 $3.67   780K    190K     4.2M   84%
─────────────────────────────────────────────────────────────
TOTAL                     $27.35   4.5M    1.5M    24.6M   88%
```

*Pricing: Claude Sonnet 4.5 ($3/$3.75/$0.30/$15 per 1M tokens)*

---

## 🎨 Visual Context at a Glance

### Main Menu Example
```
+──────────────────────────────────────────────────────────────────────+
| #  Active Model   Session           Messages  Created    Cost        |
+──────────────────────────────────────────────────────────────────────+
| 1  X      sonnet  my-project        45        01/18      $1.20       |
| 2         opus    [test-fork]       0         01/19      $0.00       |
| 3         haiku   api-redesign      28        01/17      $2.45       |
+──────────────────────────────────────────────────────────────────────+

New Session | Win Terminal Config | Hide Unnamed | Cost | Debug | Refresh | eXit
```

### Background Images Show
- **Line 1:** Session name (bold, 48pt)
- **Line 2:** Forked from parent (if applicable)
- **Line 3:** Git branch
- **Line 4:** AI model (Opus/Sonnet/Haiku)
- **Line 5:** Computer:User
- **Line 6:** Full directory path

---

## 🔧 Advanced Features

### Column Configuration
Press **G** to customize which columns appear:
- ✓ Active indicator
- ✓ Model name
- ✓ Session name
- ☐ Notes (hidden by default)
- ✓ Message count
- ✓ Created date
- ✓ Modified date
- ✓ Cost
- ✓ Windows Terminal profile
- ✓ Forked from
- ✓ Path

### Validation System
Built-in self-protection with 40 automated tests:
- Infrastructure validation (PowerShell, Claude CLI, Windows Terminal)
- Logic validation (path encoding, GUID format, model names)
- Data consistency (JSON structure, session mappings)
- Menu integrity (key handlers match menu options)

Press **D** for Debug menu → **V** to run validation tests.

---

## 🐛 Troubleshooting

**Sessions not appearing?**
- Press `R` to refresh
- Enable debug mode with `D`
- Check `~\.claude-menu\debug.log`

**Background images not showing?**
- Open Windows Terminal Settings
- Select your Claude profile
- Check Background Image path and opacity (30%)
- Disable Acrylic effects if enabled

**Script won't run?**
```powershell
powershell -ExecutionPolicy Bypass -File "Claude-Menu.ps1"
```

**Need more help?**
- Check [Full Documentation](docs/README-FULL.md)
- Review [Changelog](docs/CHANGELOG.md)
- Open an issue on GitHub

---

## 📚 Documentation

- **[Quick Start Guide](docs/QUICKSTART.md)** - Get running in 2 minutes
- **[Full Documentation](docs/README-FULL.md)** - Complete feature reference
- **[Installation Guide](docs/INSTALL.md)** - Detailed setup instructions
- **[Changelog](docs/CHANGELOG.md)** - Version history
- **[Product Analysis](docs/PRODUCT_ANALYSIS.md)** - Development insights

---

## 💎 What Makes This Special

### Professional Quality
- **Enterprise-grade UX** - Arrow navigation, silent input handling, universal defaults
- **40 Automated Tests** - Self-validating code protects against regressions
- **Comprehensive Error Handling** - Graceful recovery from failures
- **Performance Optimized** - Caching, pagination, instant response

### Unique Features
- **Only professional-grade session manager** for Claude Code
- **Cost tracking** per session (unique feature)
- **Visual fork tracking** with custom backgrounds
- **Windows Terminal deep integration**
- **Git branch awareness**
- **Customizable columns**

### Built with AI
This tool was created with Claude Code's help - **a meta tool for managing Claude itself!**

Demonstrates AI-assisted development achieving professional-grade quality in days instead of months.

---

## 🤝 Contributing

Issues, suggestions, and contributions welcome!

This is an active project. Current focus areas:
- VS Code integration
- Cloud sync for configurations
- Team collaboration features
- Plugin architecture

---

## 📝 License

Created by S. Rives, 2026
See [LICENSE](docs/LICENSE) for details.

---

## 🔗 Links

- **[GitHub Repository](https://github.com/srives/WinClaudeCodeForker)**
- **[Releases](https://github.com/srives/WinClaudeCodeForker/releases)**
- **[Claude Code Documentation](https://claude.com/claude-code)**
- **[Windows Terminal Docs](https://aka.ms/terminal)**

---

**⭐ Star this repo if it makes your Claude Code workflow better!**
