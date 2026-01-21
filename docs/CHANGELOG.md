# Changelog

All notable changes to Windows Claude Code Forker will be documented in this file.

## [1.4.0] - 2026-01-20

### Major Features

#### Git Integration
- **Git Branch Detection** - Automatically detects git branch in session directories
- **Branch Display on Background** - Shows git branch as third line on background images
- **Session Info Enhancement** - Displays git branch in session options menu when selecting a session

#### Model Information Display
- **Model on Background Images** - Shows model name (Opus/Sonnet/Haiku) as fourth line on background images
- **Model-First Workflow** - Reordered operations to select model before generating background image
- **Model Tracking** - Retrieves and displays model information from session-mapping.json

#### Smart Background Image Management
- **Conflict Resolution** - When background image already exists, offers 4 options: Overwrite, Use, Create New Name, Abort
- **Usage-Aware Auto-Overwrite** - Automatically overwrites orphaned background images (0 sessions using it)
- **Profile Usage Display** - Shows which Windows Terminal profiles are using a background before prompting
- **Auto-Numbering** - Creates unique names (Name1, Name2, etc.) when user chooses to create new session

#### Directory Selection for New Sessions
- **Current Directory Display** - Shows current directory in main menu header
- **Directory Choice** - Prompts to use current directory or set different one when creating new sessions
- **Directory Validation** - Validates directory exists, reprompts if invalid
- **Multiple Abort Points** - User can abort at directory selection and other critical points

#### Enhanced User Control
- **Trusted Session Abort** - Added abort option to trusted session prompt with proper cleanup
- **Cleanup on Abort** - Removes Windows Terminal profile and background image when aborting session creation

### Bug Fixes

#### Critical Path Handling Fix
- **Trailing Backslash Bug** - Fixed Windows Terminal crash (error 0x8007010b) caused by trailing backslashes in startingDirectory
- **Path Normalization** - Applied TrimEnd('\') consistently throughout directory handling in Start-NewSession and Add-WTProfile

#### PSCustomObject Property Errors
- **Save-BackgroundTracking Fix** - Fixed "property 'updated' cannot be found" error by replacing entire object instead of modifying properties
- **Add-SessionMapping Fix** - Fixed same error using object replacement pattern
- **Preserved Optional Properties** - Properly handles optional fields like forkedFrom during updates

### Technical Details

**New Functions:**
- `Get-GitBranch()` - Detects git branch from directory using `git rev-parse --abbrev-ref HEAD`
- `Resolve-BackgroundImageConflict()` - Handles background image conflicts with smart auto-overwrite logic
- `Get-SessionsUsingBackground()` - Counts Windows Terminal profiles using a specific background image

**Modified Functions:**
- `Show-SessionMenu()` - Added current directory display in header
- `Start-NewSession()` - Added directory selection, validation, conflict resolution, model-first ordering
- `New-SessionBackgroundImage()` - Added GitBranch and Model parameters with comprehensive debug logging
- `New-ContinueSessionBackgroundImage()` - Added GitBranch and Model parameters
- `Add-WTProfile()` - Added path normalization to remove trailing backslashes
- `Save-BackgroundTracking()` - Changed to replace entire object instead of modifying properties
- `Add-SessionMapping()` - Changed to replace entire object instead of modifying properties
- `Get-TrustedSessionChoice()` - Changed return values from boolean to 'yes'/'no'/'abort', added cleanup logic
- `Get-ForkOrContinue()` - Added git branch display in session info
- `Start-ForkSession()` - Integrated conflict resolution workflow
- `Start-ContinueSession()` - Integrated conflict resolution and git branch detection

**Background Image Format:**
- Line 1: Session name
- Line 2: Origin text or "forked from: [parent]"
- Line 3: Git branch (if detected)
- Line 4: Model name

**Conflict Resolution Logic:**
1. Check if background image already exists
2. Count how many profiles are using it
3. If count = 0, automatically overwrite without prompting
4. If count > 0, show profile list and offer options
5. Support creating new unique names with auto-numbering

---

## [1.3.0] - 2026-01-20

### Major Features

#### Windows Terminal Profile Management
- **Automatic Duplicate Handling** - When creating a profile with a name that already exists, automatically appends an integer (Claude-Name1, Claude-Name2, etc.)
- **Profile Validation on Startup** - New `Validate-SessionMappings()` function runs on menu load to verify all profile references are valid
- **Cleanup on Profile Deletion** - When deleting a Windows Terminal profile, automatically removes all session references to it
- **Consistent Naming** - All profile creation operations capture and use the actual profile name returned (which may have integer suffix)

#### Enhanced Session Discovery
- **Extended .jsonl Parsing** - Now reads first 10 lines of session files to find cwd field (previously only read first line)
- **Queue-Operation Support** - Handles sessions where first line is queue-operation instead of session data
- **Non-Standard Paths** - Successfully discovers sessions in unconventional directory structures like "GTP Software Inc\STRATUS Logs\Revit"

#### User Interface Improvements
- **Smart Path Truncation** - Paths now truncate from the front (keeping end visible) using new -FromLeft parameter on `Truncate-String()`
- **Dynamic Continue Text** - Option 1 shows different text based on whether session has a profile:
  - With profile: "Continue - Resume Claude Session with Windows Profile"
  - Without profile: "Continue - Create Windows Terminal Profile and Resume Claude Session"
- **Redesigned Debug Menu** - Replaced verbose debug screen with clean 4-option submenu:
  1. Toggle Debug flag
  2. Notepad Debug Log
  3. Show instructions
  4. Abort

#### Win Terminal Config Enhancements
- **Toggle Display Mode** - New A/P keys to toggle between "Profiles Only" and "Show All" sessions
- **Profile Creation for Unnamed** - Select sessions without profiles to create Windows Terminal profiles with background images
- **Integrated Workflow** - Seamless profile creation and session tracking updates

### Changes

**Profile Management:**
- Modified `Add-WTProfile()` to check for duplicate names and append integers
- Modified `Remove-WTProfile()` to clean up session mapping references
- Added `Validate-SessionMappings()` called from `Start-MainMenu()`
- Updated all callers: `Start-NewSession()`, `Start-ContinueSession()`, `Start-ForkSession()`, Win Terminal Config menu

**Session Discovery:**
- `Get-AllClaudeSessions()` now scans first 10 lines of .jsonl files for cwd field
- Better handling of unindexed sessions
- Support for sessions without sessions-index.json

**User Experience:**
- `Get-ForkOrContinue()` displays dynamic text based on profile existence
- `Truncate-String()` added -FromLeft switch for better path visibility
- `Show-DebugToggle()` redesigned as submenu instead of verbose info dump
- Fixed program flow to return to menu instead of exiting on validation failures

**Bug Fixes:**
- Fixed function call: `Generate-BackgroundImage` → `New-SessionBackgroundImage`
- Fixed function call: `Add-SessionMappingEntry` → `Add-SessionMapping`
- Fixed incorrect parameter names in `Add-WTProfile` call
- Fixed `exit 0` causing premature termination in `Start-ContinueSession()` and `Start-NewSession()`

### Technical Details

**New Functions:**
- `Validate-SessionMappings()` - Validates profile references and removes invalid ones on startup

**Modified Functions:**
- `Add-WTProfile()` - Lines 3027-3041: Duplicate detection loop with integer appending
- `Remove-WTProfile()` - Lines 3128-3165: Session mapping cleanup
- `Get-AllClaudeSessions()` - Lines 719-768: Extended .jsonl parsing to 10 lines
- `Get-ForkOrContinue()` - Lines 2361-2389: Dynamic text based on profile check
- `Show-DebugToggle()` - Lines 282-377: Complete redesign as 4-option menu
- `Truncate-String()` - Lines 58-85: Added -FromLeft parameter
- `Start-MainMenu()` - Line 4211: Added `Validate-SessionMappings()` call
- `Start-ContinueSession()` - Extensive debug logging, uses actual profile names
- `Start-NewSession()` - Uses actual profile name from Add-WTProfile
- `Start-ForkSession()` - Uses actual profile name from Add-WTProfile

**Validation Flow:**
1. On startup, `Start-MainMenu()` calls `Validate-SessionMappings()`
2. Loads Windows Terminal settings to get actual profile list
3. Checks each session mapping against actual profiles
4. Removes wtProfileName field from sessions if profile doesn't exist
5. Saves updated session-mapping.json

---

## [1.2.0] - 2026-01-20

### Major Features

#### Arrow-Key Navigation
- **Keyboard Navigation** - Navigate menu with UP/DOWN arrow keys for instant selection changes
- **Single-Key Commands** - All menu actions now work with single key press (no Enter required)
- **Enter to Select** - Press Enter to confirm selection of highlighted session
- **Instant Response** - Arrow navigation is immediate with no screen refresh lag

#### Performance Improvements
- **Token Usage Caching** - Added `$Global:TokenUsageCache` to cache token usage data
- **Session Data Caching** - Session data only reloads on explicit commands (not during arrow navigation)
- **Eliminated Recalculations** - Arrow navigation no longer triggers expensive .jsonl file parsing
- **Optimized Menu Display** - Menu redisplay uses cached data during navigation

#### User Interface
- **Cleaner Menu Format** - Removed square brackets from menu options for better readability
- **Pipe Separators** - Added ` | ` separators between menu options
- **Color-Coded Letters** - Key letters highlighted in color to indicate shortcuts
- **Simplified Win Terminal Menu** - Removed Cost and Debug options from Win Terminal Config menu

#### User Experience
- **Show All by Default** - All sessions (including unnamed) are now shown by default
- **Updated Help Text** - Clarified that forked sessions show in brackets until /rename and cache
- **Menu Command Format** - Changed from `[N]ew [W]in Terminal` to `New Session | Win Terminal Config`

### Changes

**Navigation:**
- UP/DOWN arrows navigate between sessions
- Enter selects highlighted session
- Single-key commands: N (New), W (Win Terminal), S (Show), H (Hide), O (cOst), D (Debug), R (Refresh), X (eXit), Q (Quiet), C (Chatty)

**Menu Format:**
- Main Menu: `New Session | Win Terminal Config | Hide Unnamed Sessions | Quiet Mode | cOst | Debug | Refresh | eXit`
- Win Terminal Config: `Refresh | eXit`

**Default Behavior:**
- `$showUnnamed = $true` (show all sessions by default)

**Performance:**
- `Get-SessionTokenUsage()` now checks cache before reading files
- `Get-ArrowKeyNavigation()` handles navigation and single-key commands
- `Start-MainMenu()` uses `$reloadSessions` flag for conditional loading

### Technical Details

**New Global Variables:**
- `$Global:TokenUsageCache = @{}` - Caches token usage to avoid repeated file parsing

**Modified Functions:**
- `Get-SessionTokenUsage()` - Added cache check before file read
- `Get-ArrowKeyNavigation()` - New function for arrow key and single-key command handling
- `Show-SessionMenu()` - Optimized for cached data display
- `Start-MainMenu()` - Added `$reloadSessions` flag logic

**Navigation Implementation:**
- Arrow keys update selection without returning to main loop
- Commands return to main loop with specific action type
- Navigate action skips session reload and uses cached data

---

## [1.1.0] - 2026-01-20

### Major Improvements

#### Reliability & Error Handling
- **Error Logging System** - Added comprehensive error logging to debug.log file for all silent catch blocks
- **Backup Validation** - Windows Terminal settings backups are now validated before restoration
- **JSON Structure Validation** - All JSON parsing now validates expected structure with `Test-JsonStructure()` helper
- **Session File Validation** - Added `Test-SessionFileValid()` to prevent "No conversation found" errors before resuming/forking sessions
- **Array Initialization** - Added null checks and initialization for `$Sessions` arrays to prevent null reference errors

#### Critical Bug Fixes
- **Fixed Path Decoding Bug** - Corrected `ConvertFrom-ClaudeprojectPath()` regex to properly decode Claude's path format (`C--repos-Fork` → `C:\repos\Fork`)
- **Fixed Variable Syntax Error** - Corrected line 138 PowerShell variable reference with colon
- **Fixed Command Quoting** - Added proper quoting around model parameter in Windows Terminal launch command

#### User Experience Improvements
- **Cost Tracking** - Added comprehensive cost analysis feature:
  - Per-session cost display in main menu (Claude Sonnet 4.5 pricing)
  - [$] Cost Analysis menu option for detailed cost report
  - Total cost display in status line
  - Token usage breakdown (input, output, cache reads/writes)
  - Cache hit percentage calculation
- **Debug Mode** - Added comprehensive debug system:
  - [D]ebug menu option to toggle debug mode on/off
  - Persistent logging to `~\.claude-menu\debug.log`
  - Session discovery trace information
  - Debug state indicator in status line
- **Visual Menu Box** - Added ASCII box border around main menu for better visual separation
- **Status Line** - Enhanced status line showing:
  - Session counts (named/unnamed)
  - Debug mode status
  - Permission mode (Quiet/Chatty)
  - Total cost across all sessions
- **Session Validation Messages** - Added helpful error messages when attempting to continue/fork corrupted or missing session files

#### Code Quality
- **Error Logging Function** - New `Write-ErrorLog()` function for consistent error tracking
- **JSON Validation Helper** - New `Test-JsonStructure()` function to validate required properties
- **Session File Validator** - New `Test-SessionFileValid()` function to check .jsonl file integrity
- **Truncation Helper** - Improved `Truncate-String()` function for consistent text truncation

### Technical Details

**New Functions Added:**
- `Write-ErrorLog()` - Logs errors to debug.log regardless of debug state
- `Test-JsonStructure()` - Validates JSON objects have required properties
- `Test-SessionFileValid()` - Validates session .jsonl files exist and are readable
- `Get-SessionTokenUsage()` - Parses .jsonl files to extract token usage
- `Get-SessionCost()` - Calculates cost using Claude Sonnet 4.5 pricing
- `Format-Cost()` - Formats cost values for display
- `Format-TokenCount()` - Formats token counts with K/M suffixes
- `Show-CostAnalysis()` - Displays detailed cost analysis report

**Enhanced Functions:**
- `ConvertFrom-ClaudeprojectPath()` - Fixed regex pattern, added error logging
- `Get-GlobalPermissionStatus()` - Returns detailed diagnostic info in debug mode
- `Show-SessionMenu()` - Added visual box border, cost column
- `Start-ContinueSession()` - Added session file validation before resume
- `Start-ForkSession()` - Added session file validation before forking

**Improved Error Handling:**
- Added error logging to 10+ catch blocks
- Enhanced backup restoration with validation
- Better error messages for missing/corrupted session files

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
