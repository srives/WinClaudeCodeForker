# Version Information

## Current Version: 1.3.0 (2026-01-20)

### Release Notes

This release focuses on Windows Terminal profile management, session discovery improvements, and user experience enhancements.

#### Major Features

**Windows Terminal Profile Management**
- Automatic duplicate name handling (appends integers: Claude-Name1, Claude-Name2, etc.)
- Profile validation on menu load removes invalid references
- Session mapping cleanup when profiles are deleted
- All profile references remain consistent across operations

**Enhanced Session Discovery**
- Reads first 10 lines of .jsonl files to find project path (not just first line)
- Supports sessions where first line is queue-operation
- Discovers sessions in non-standard paths

**User Interface Improvements**
- Path truncation from front instead of back (end is most informational)
- Dynamic continue option text based on profile existence
- Redesigned debug menu with 4 clear options
- Better visual hierarchy and information display

**Win Terminal Config Menu Enhancement**
- Toggle between "Profiles Only" and "Show All" modes (A/P keys)
- Create Windows Terminal profiles for sessions that don't have them
- Integrated background image generation workflow

#### Changes

**Profile Management:**
- `Add-WTProfile` checks for duplicate names and appends integers automatically
- `Remove-WTProfile` cleans up all session mapping references to deleted profile
- `Validate-SessionMappings` runs on startup to verify profile existence
- All functions that create profiles use the actual returned profile name

**Session Discovery:**
- Extended .jsonl parsing from 1 line to 10 lines when searching for cwd field
- Handles sessions in unconventional directory structures
- Better support for unindexed sessions

**User Experience:**
- Continue option shows different text: "Resume Claude Session with Windows Profile" vs "Create Windows Terminal Profile and Resume Claude Session"
- Path display truncates from left, keeping the informative end visible
- Debug menu replaced verbose screen with clean 4-option submenu
- Program returns to menu instead of exiting after validation errors

**Bug Fixes:**
- Fixed function name: Generate-BackgroundImage → New-SessionBackgroundImage
- Fixed function name: Add-SessionMappingEntry → Add-SessionMapping
- Fixed exit 0 issues causing premature program termination
- Fixed Add-WTProfile parameter names in Win Terminal Config menu

#### Technical Details

**New Functions:**
- `Validate-SessionMappings()` - Validates profile references and removes invalid ones

**Modified Functions:**
- `Add-WTProfile()` - Added duplicate name detection with integer appending
- `Remove-WTProfile()` - Added session mapping cleanup
- `Get-AllClaudeSessions()` - Reads first 10 lines for cwd field
- `Get-ForkOrContinue()` - Dynamic text based on profile existence
- `Show-DebugToggle()` - Redesigned as 4-option submenu
- `Truncate-String()` - Added -FromLeft switch parameter
- `Start-MainMenu()` - Calls Validate-SessionMappings on startup
- `Start-ContinueSession()` - Added extensive debug logging, uses actual profile names
- `Start-NewSession()` - Uses actual profile name from Add-WTProfile
- `Start-ForkSession()` - Uses actual profile name from Add-WTProfile

**Profile Management Flow:**
1. Startup validates all profile references
2. Creating profiles checks for duplicates and appends integers
3. Deleting profiles removes all session references
4. All operations maintain consistency in session-mapping.json

#### Breaking Changes

None - fully backward compatible with v1.2.0

#### Migration Notes

No manual migration required. Profile validation runs automatically on first launch of v1.3.0.

---

## Previous Version: 1.2.0 (2026-01-20)

### Release Notes

This release introduces modern keyboard navigation and significant performance improvements.

#### Major Features

**Arrow-Key Navigation**
- Navigate menu with UP/DOWN arrow keys
- Instant selection changes without screen refresh
- Enter key to confirm selection
- Single-key commands (no Enter required for menu actions)
- Clean, responsive interface

**Performance Improvements**
- Token usage caching for instant menu navigation
- Eliminated expensive recalculations during arrow navigation
- Session data caching to avoid redundant disk reads
- Menu redisplay optimized to only update when needed

**Improved Menu Design**
- Removed square brackets from menu options
- Pipe separators (|) for cleaner visual layout
- Color-coded letters indicate keyboard shortcuts
- Simplified Win Terminal Config menu

**User Experience**
- All sessions (including unnamed) shown by default
- No need to press [S] to see unnamed sessions on first launch
- Updated help text for newly forked sessions
- Cleaner, more intuitive command structure

#### Changes

**Navigation:**
- Arrow keys (UP/DOWN) navigate between sessions instantly
- Enter selects the highlighted session
- Single-key commands: N, W, S, H, O, D, R, X, Q, C
- No Enter required for menu commands

**Menu Format:**
- Changed from: `[N]ew [W]in Terminal [H]ide`
- Changed to: `New Session | Win Terminal Config | Hide Unnamed Sessions`
- Win Terminal Config menu simplified (removed Cost and Debug options)

**Default Behavior:**
- `$showUnnamed` now defaults to `$true` (show all sessions)
- Users can still press H to hide unnamed sessions

**Performance:**
- Added `$Global:TokenUsageCache` for instant cost lookups
- Session data only reloads on explicit commands (not arrow navigation)
- Menu redisplay uses cached data during navigation

#### Technical Details

**New Global Variables:**
- `$Global:TokenUsageCache` - Caches token usage by session to avoid .jsonl file parsing

**Modified Functions:**
- `Get-SessionTokenUsage()` - Now checks cache before reading files
- `Get-ArrowKeyNavigation()` - Handles arrow keys and single-key commands
- `Show-SessionMenu()` - Optimized for performance with caching
- `Start-MainMenu()` - Added `$reloadSessions` flag for conditional reloading

**Navigation Changes:**
- Arrow navigation returns updated index without triggering session reload
- Menu displays using cached token usage data
- Only commands like Refresh, Cost, Debug trigger data reload

#### Breaking Changes

None - fully backward compatible with v1.1.0

#### Migration Notes

No manual migration required. Token cache will build automatically on first use.

---

## Previous Version: 1.1.0 (2026-01-20)

### Release Notes

This release focuses on reliability, error handling, and cost tracking capabilities.

#### Major Features

**Cost Tracking System**
- Per-session cost calculation based on Claude Sonnet 4.5 pricing
- Detailed cost analysis report ([$] menu option)
- Token usage breakdown (input, output, cache reads/writes)
- Cache hit percentage calculation
- Total cost display in status line

**Debug Mode**
- Toggle debug logging on/off ([D] menu option)
- Persistent logging to `~\.claude-menu\debug.log`
- Session discovery trace information
- File operation diagnostics
- Debug state indicator in status line

**Session Validation**
- Pre-validates session files before continue/fork operations
- Prevents "No conversation found" errors
- Clear error messages with diagnostic information
- Helpful troubleshooting guidance

#### Critical Bug Fixes

1. **Path Decoding Bug** - Fixed regex in `ConvertFrom-ClaudeprojectPath()` to properly decode Claude's path format
2. **Variable Syntax Error** - Fixed PowerShell variable reference with colon at line 138
3. **Command Quoting** - Added proper parameter quoting in Windows Terminal launch command

#### Improvements

**Error Handling**
- Comprehensive error logging system (`Write-ErrorLog()` function)
- Error logging in all catch blocks
- Backup validation before restoration
- JSON structure validation after parsing
- Array initialization checks

**User Experience**
- Visual ASCII box border around main menu
- Enhanced status line with session counts, debug status, and total costs
- Truncation of text that exceeds box width
- Better error messages throughout

**Code Quality**
- Added 8+ new helper functions
- Enhanced 10+ existing functions
- Improved validation at critical points
- Better separation of concerns

#### Technical Details

**New Functions:**
- `Write-ErrorLog()` - Persistent error logging
- `Test-JsonStructure()` - JSON validation helper
- `Test-SessionFileValid()` - Session file integrity check
- `Get-SessionTokenUsage()` - Token usage extraction
- `Get-SessionCost()` - Cost calculation
- `Format-Cost()` / `Format-TokenCount()` - Display formatters
- `Show-CostAnalysis()` - Detailed cost report
- `Truncate-String()` - Text truncation helper

**Pricing Model:**
- Input tokens: $3.00 per 1M
- Cache writes: $3.75 per 1M
- Cache reads: $0.30 per 1M
- Output tokens: $15.00 per 1M

#### Breaking Changes

None - fully backward compatible with v1.0.0

#### Migration Notes

No manual migration required. Simply replace the script file.

New files will be created automatically on first run:
- `~\.claude-menu\debug.txt`
- `~\.claude-menu\debug.log`

---

## Previous Version: 1.0.0 (2026-01-19)

Initial release with core session management, Windows Terminal integration, fork tracking, and background image generation.

See CHANGELOG.md for complete version history.
