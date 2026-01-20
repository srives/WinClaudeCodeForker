# Project Structure

## Overview

**Windows Claude Code Forker** is a single-file PowerShell application for managing Claude Code CLI sessions with Windows Terminal integration.

## Files

```
WinClaudeCodeForker/
├── Claude-Menu.ps1          # Main application (92KB, ~2500 lines)
├── README.md                # User documentation
├── INSTALL.md               # Installation guide
├── QUICKSTART.md            # Quick start guide
├── CHANGELOG.md             # Version history
├── LICENSE                  # MIT License
├── PROJECT.md               # This file
└── .gitignore              # Git ignore rules
```

## Architecture

### Single-File Design

The entire application is contained in `Claude-Menu.ps1` for easy distribution. Users only need to copy this one file.

### Code Organization

The script is organized into logical regions:

```powershell
#region Utility Functions
  - Write-ColorText
  - Test-ClaudeCLI
  - Test-WindowsTerminal

#region Session Discovery
  - Get-AllClaudeSessions
  - ConvertTo-ClaudeProjectPath

#region Menu Display
  - Get-WTProfileName
  - Get-SessionMapping
  - Get-SessionMappingEntry
  - Get-ForkedFromInfo
  - Get-ForkTree
  - Get-SessionActivityMarker
  - Show-SessionMenu

#region User Input
  - Get-UserSelection

#region Session Operations
  - Start-NewSession
  - Start-ContinueSession
  - Get-SessionManagementChoice
  - Get-RegenerateImageChoice
  - Get-ForkOrContinue

#region Fork Workflow
  - Get-SessionName
  - Get-ModelChoice
  - Start-ForkSession

#region Windows Terminal Profile Management
  - Backup-WTSettings
  - Test-WTSettingsValid
  - Add-WTProfile
  - Get-WTProfileDetails
  - Remove-WTProfile
  - Initialize-BaseWTProfile

#region Image Generation
  - New-SessionBackgroundImage
  - New-ContinueSessionBackgroundImage
  - Update-SessionBackgroundImage

#region Session Mapping
  - Initialize-SessionMapping
  - Add-SessionMapping

#region Profile Registry
  - Initialize-ProfileRegistry
  - Add-ProfileRegistry
  - Get-ModelFromRegistry
  - Get-ForkedFromInfo

#region Model Detection
  - Get-ModelFromSession

#region Session Deletion
  - Remove-Session

#region Background Tracking
  - Initialize-BackgroundTracking
  - Save-BackgroundTracking
  - Get-BackgroundTracking
  - New-CustomTextBackgroundImage
  - Set-BackgroundFromFile
  - Remove-BackgroundFromProfile

#region Main Program
  - Initialize-Environment
  - Start-MainMenu
```

## Data Files

The script creates and manages these files in `~\.claude-menu\`:

### session-mapping.json
Maps Claude session IDs to Windows Terminal profiles.

```json
{
  "version": 1,
  "sessions": [
    {
      "sessionId": "uuid",
      "wtProfileName": "Claude-name",
      "projectPath": "C:\\repos",
      "model": "sonnet",
      "forkedFrom": "parent-uuid",
      "created": "2026-01-19T..."
    }
  ]
}
```

### profile-registry.json
Legacy profile tracking (still used for compatibility).

```json
{
  "version": 1,
  "profiles": [
    {
      "sessionName": "name",
      "wtProfileGuid": "{guid}",
      "originalSessionId": "parent-uuid",
      "created": "2026-01-19T...",
      "projectPath": "C:\\repos",
      "backgroundImage": "path",
      "model": "sonnet"
    }
  ]
}
```

### background-tracking.json
Tracks background images and their content.

```json
{
  "version": 1,
  "backgrounds": [
    {
      "sessionName": "name",
      "backgroundPath": "path",
      "textContent": "text",
      "imageType": "fork|continue|custom-text|custom-file",
      "created": "2026-01-19T..."
    }
  ]
}
```

## Key Technologies

- **PowerShell 5.1+** - Scripting language
- **.NET System.Drawing** - Image generation
- **Windows Terminal JSON API** - Profile management
- **Claude CLI** - Session management

## Design Decisions

### Why Single File?

**Pros:**
- Easy to distribute (copy one file)
- No installation required
- No dependencies to manage
- Works from any location
- Simple versioning

**Cons:**
- Large file size (~92KB, ~2500 lines)
- Harder to navigate/maintain
- No code splitting

**Conclusion**: Single file wins for this use case due to ease of distribution.

### Why PowerShell?

**Pros:**
- Native to Windows (no installation)
- Direct access to .NET Framework
- Easy file/registry manipulation
- JSON parsing built-in
- Can launch external programs easily

**Cons:**
- Windows-only
- Some users unfamiliar with it
- Execution policy restrictions

**Conclusion**: Perfect fit for Windows Terminal integration.

### Why Not Python/Node.js?

- Would require installation
- More complex distribution
- No significant benefits for this use case

## Development Guidelines

### Adding New Features

1. **Add function** in appropriate region
2. **Update documentation** in all relevant MD files
3. **Test** with various session states
4. **Update CHANGELOG.md**
5. **Increment version** if releasing

### Code Style

- Use PowerShell naming conventions (Verb-Noun)
- Add synopsis/description to all functions
- Use `Write-ColorText` for user feedback
- Handle errors gracefully with try/catch
- Validate all user inputs
- Add comments for complex logic

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

## Distribution

### Preparing a Release

1. **Test thoroughly** on clean Windows install
2. **Update version** in script header
3. **Update CHANGELOG.md**
4. **Create release tag**
5. **Package**: Just `Claude-Menu.ps1` is needed
6. **Share**: GitHub release, website, etc.

### Installation for Users

Users need only:
1. Copy `Claude-Menu.ps1`
2. Run it from anywhere
3. Optional: Create shortcut

## Future Enhancements

See CHANGELOG.md for potential future features.

### Modular Architecture (v2.0?)

If the project grows significantly, consider:
- Breaking into modules
- Using PowerShell module system
- Publishing to PowerShell Gallery
- Adding automated tests

### GUI Version?

Potential future direction:
- WPF/Windows Forms GUI
- System tray integration
- Notification support

## Contributing

To contribute:

1. **Fork** the repository
2. **Create branch** for feature
3. **Make changes** following code style
4. **Test thoroughly**
5. **Update documentation**
6. **Submit pull request**

## Technical Notes

### Path Encoding

Claude encodes paths by removing colons and replacing backslashes:
- Input: `C:\repos`
- Encoded: `C--repos`

### Session Files

Claude stores sessions as JSONL (JSON Lines):
```
~\.claude\projects\<encoded-path>\<session-id>.jsonl
```

Each line is a complete JSON object.

### Windows Terminal Settings

Located at:
```
%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
```

Always backup before modification!

### Image Generation

Uses System.Drawing to create PNG images:
- Size: 1920x1080 (full HD)
- Format: PNG with transparency
- Text: Consolas font, positioned at 60% width

## Support

For questions or issues:
- Check README.md
- Review INSTALL.md
- Read QUICKSTART.md
- Create GitHub issue

## License

MIT License - See LICENSE file

---

**Project Created**: January 2026
**Author**: S. Rives
**Language**: PowerShell 5.1+
**Platform**: Windows 10/11
