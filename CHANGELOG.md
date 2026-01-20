# Changelog

All notable changes to Windows Claude Code Forker will be documented in this file.

## [1.0.0] - 2026-01-19

### Initial Release

#### Features

**Session Management**
- Automatic discovery of all Claude sessions across projects
- Session listing with metadata (messages, dates, model, activity)
- Continue existing sessions
- Fork sessions to create branches
- Delete sessions with comprehensive cleanup

**Windows Terminal Integration**
- Automatic profile creation for forked sessions
- Custom background image generation
- Profile management (regenerate, delete, remove backgrounds)
- Background image customization (session, file, or text input)
- Intelligent profile cleanup (removes only when not used by other sessions)

**Session Tracking**
- Track forked sessions before Claude CLI indexes them
- Display newly forked sessions in [brackets]
- Fork genealogy tracking (parent-child relationships)
- Activity indicators based on file modification time
- Session mapping database for unnamed sessions

**Background Images**
- Auto-generated PNG backgrounds (1920x1080)
- Text positioned at 60% width for visibility
- Fork images show "forked from: [parent]"
- Support for custom images and text overlays
- Background tracking system

**Activity Monitoring**
- Real-time activity indicators
  - `X` = Within 5 minutes
  - `x` = Within 30 minutes
  - `x?` = Within 1 hour
  - `?` = Within 5 hours

**User Interface**
- Interactive console menu
- Color-coded status messages
- Show/hide unnamed sessions
- Refresh menu option
- Windows Terminal profile management mode
- Session options submenu (Continue/Fork/Delete)

#### Technical Implementation

**Core Components**
- Single PowerShell file (Claude-Menu.ps1)
- ~2500 lines of code
- No external dependencies (uses .NET System.Drawing for images)
- Portable (runs from any location)

**Data Management**
- `session-mapping.json` - Maps sessions to Windows Terminal profiles
- `profile-registry.json` - Legacy profile tracking
- `background-tracking.json` - Tracks background image metadata
- Automatic backups of Windows Terminal settings

**Path Handling**
- Correct path encoding for Claude's format (C:\repos → C--repos)
- Support for multiple project directories
- Dynamic session file discovery

**Error Handling**
- Graceful failure recovery
- Automatic backup/restore for Windows Terminal settings
- Validation of all user inputs
- Clear error messages

#### Known Limitations

- Requires Windows 10/11
- Requires PowerShell 5.1+
- Windows Terminal must be installed
- Claude CLI must be in PATH
- Background images only work with PNG format

## Future Enhancements

Potential features for future releases:

**Session Features**
- Export/import sessions
- Session search and filtering
- Session tags and categories
- Session notes and descriptions

**UI Improvements**
- Color themes
- Customizable columns
- Sorting options
- Pagination for large session lists

**Background Customization**
- Multiple background templates
- Color scheme selection
- Font customization
- Image effects and filters

**Integration**
- VS Code integration
- Git branch detection
- Project detection and grouping
- Auto-fork on branch switch

**Performance**
- Caching for faster startup
- Async session loading
- Incremental updates

---

## Version History

### 1.0.0 (2026-01-19)
- Initial public release
- Core session management features
- Windows Terminal integration
- Background image generation
- Fork tracking and genealogy
- Session deletion with cleanup
