# Version Information

## Current Version: 2.0.0 (2026-01-26)

### Release Notes

This release expands the validation test suite from 65 to 80 tests, adding machine-independent tests that detect regressions in key areas.

#### New Validation Tests (Tests 66-80)

**Keyboard Handler Tests:**
- Test 66: Enter Key Handler Pattern - Verifies Enter key defaults exist in 10+ menus (added in v1.10.0)
- Test 67: Escape Key Handler Pattern - Verifies Escape key abort handling in menus

**Regression Prevention Tests:**
- Test 68: Select-Object -First 1 Pattern - Catches the duplicate profile bug we fixed in 7 locations
- Test 77: Draw-SessionRow Has Limit - Catches missing Limit column bug we fixed

**Core Function Tests:**
- Test 69: Get-ForkOrContinue Function - Verifies fork/continue logic with required parameters
- Test 70: Date/Time Formatting - Validates Get-ShortDateTimeString format output
- Test 71: Cost Calculation Logic - Tests cost math with known values
- Test 74: Get-SessionCost Function - Verifies graceful handling of missing sessions
- Test 76: Draw-SessionRow Function - Critical display function validation

**Feature Function Tests:**
- Test 72: Archive/Restore Functions - 4 archive-related functions
- Test 73: Font Functions - 3 Nerd Font installation functions
- Test 75: WT Profile Functions - 3 Windows Terminal profile functions
- Test 78: Session Notes Functions - Get/Set session notes
- Test 79: Git Branch Detection - Handles non-git directories gracefully
- Test 80: Refresh Returns Updates - Verifies UpdatedBackgrounds list is returned

**Test Philosophy:**
- Machine-independent: Tests logic, not user configuration
- Regression prevention: Tests that would have caught bugs we fixed
- Function existence: Ensures critical functions are present
- Math validation: Verifies calculations with known values

---

## Previous Version: 1.10.5 (2026-01-25)

### Release Notes

This release adds comprehensive context limit management features to help users understand and manage their session context usage before auto-compaction occurs.

#### Major Features

**Context Limit Management System (LimitFeature)**
- Context usage percentage displayed in Session Options screen with color-coded severity
- New Limit column in main menu (configurable, hidden by default due to performance)
- Color coding: Green (<50%), Cyan (50-74%), Yellow (75-89%), Red (90%+ CRITICAL)
- Actionable guidance at 75% and 90% thresholds
- Fixed token calculation to include all cached tokens (was showing 0% before)

**Limit Instructions Guide (L Key)**
- Press 'L' in Session Options to view comprehensive context management guide
- Covers 4 strategies: Fork, /memory, CLAUDE.md, /compact
- Explains where /memory saves data, how many times you can use it
- Shows recommended workflow for long-running sessions
- Quick reference for all commands

**Background Parameter Refresh System**
- Refresh now checks ALL background parameters (model, branch, computer:user, directory, forked-from)
- Auto-regenerates background if ANY parameter changed
- Model caching for performance optimization
- Expensive operations only run on explicit Refresh

#### Bug Fixes

- Fixed Limit column not appearing during up/down arrow navigation
- Fixed context calculation showing 0% (now correctly sums all token types)
- Added Test 55 to prevent future column consistency issues

---

## Previous Version: 1.10.4 (2026-01-25)

### Release Notes

This release added background image sanity checking and automatic model change detection.

#### Features

- Background Image Sanity Check menu option
- Automatic model change detection with background regeneration
- Git branch tracking in session mappings
- Background image .txt companion files

---

## Previous Version: 1.10.2 (2026-01-24)

### Release Notes

This version added a comprehensive validation system with 40 automated tests to protect the program from failures and ensure code integrity.

#### Major Features

**Comprehensive Validation System (40 Tests)**
- Built-in self-protection with automated test suite
- Infrastructure validation (15 tests): PowerShell, CLI tools, directories, JSON integrity
- Logic validation (15 tests): Functions, encoding, sanitization, parsing, globals
- Algorithm validation (10 tests): Menu integrity, edge cases, consistency
- Accessible from Debug menu (Press D → V)
- Self-healing detection catches mismatches before they cause errors
- Machine-independent tests validate logic, not user configuration

**Test Categories:**
- Infrastructure (15 tests): PowerShell version, Claude CLI, Windows Terminal, directories, JSON integrity, orphaned resources
- Logic (15 tests): Function existence, path encoding, string truncation, GUID format, date parsing, model validation
- Algorithms (10 tests): Menu key handlers, column sort keys, path edge cases, JSON structure, session consistency

**Self-Protection Features:**
- Menu keys match handlers (catches refactoring errors)
- Function existence validation (prevents missing function errors)
- Path encoding edge cases (validates algorithm correctness)
- Non-invasive tests (don't modify user state)

#### Bug Fixes

**Test Accuracy Fixes**
- Fixed Test 17: Corrected function name from "New-BackgroundImage" to "New-SessionBackgroundImage"
- Fixed Test 24: Removed global state modification (now uses local test value)
- Fixed Test 28: Removed debug state toggling (now only checks function existence)
- All 40 tests now pass with accurate validation

#### Changes

**Validation System:**
- New `Test-SystemValidation()` function (lines 526-1155) with 40 comprehensive tests
- Added 'V' option to Debug menu for running validation tests
- Test results display with color-coded status (Green/Yellow/Red)
- Summary shows passed/warned/failed counts with health assessment
- Script-scoped counter variables for accurate result tracking

**Test Output:**
```
========================================
      SYSTEM VALIDATION TESTS
========================================

[PASS] PowerShell Version (Version 5.1)
[PASS] Claude CLI (Found at path)
[WARN] Orphaned WT Profiles (5 orphaned)
...

========================================
           TEST SUMMARY
========================================
Passed: 38 | Warnings: 2 | Failed: 0
```

### Previous Version: 1.10.1 (2026-01-24)

### Release Notes

This release fixes critical menu border alignment issues and refactors header rendering for improved reliability and visual consistency.

#### Major Features

**Separated Header Box**
- Headers now display in separate box above main menu
- Clean visual separation between column headers and data rows
- Header box format: `+---+` border, headers, `+---+` border
- Data box format: `+---+` border, data rows, `+---+` border
- Consistent with professional UI design patterns

**Sorted Column Highlighting**
- Active sort column now highlighted in yellow in headers
- Non-sorted columns display in cyan
- Visual indicator of current sort order
- Works for both main menu and Win Terminal Config menu

**Intelligent Header Truncation**
- Headers automatically truncate when screen width is insufficient
- Prevents text wrapping that breaks menu layout
- Columns drop gracefully when space unavailable
- Border placement always accurate regardless of window size

#### Bug Fixes

**Border Alignment Fixed**
- Fixed off-by-one error in menu box right border placement
- Border now aligns perfectly with top/bottom borders
- Created shared `Get-DynamicPathWidth()` function for consistent calculations
- Eliminated duplicate math logic between `Show-SessionMenu()` and `Write-SingleMenuRow()`

**Precise Header Positioning**
- Created `PlaceHeaderRightHandBorder()` function for cursor-based border placement
- Border position calculated from actual cursor position, not estimated width
- Handles edge cases where columns overflow available space
- Truncates overflowing text rather than allowing wrapping

#### Technical Details

**New Functions:**
- `Get-DynamicPathWidth($BoxWidth, $ColumnConfig)` - Centralized path width calculation
- `Write-SessionMenuHeader($BoxWidth, $OnlyWithProfiles)` - Dedicated header rendering function
- `PlaceHeaderRightHandBorder($RowWidth)` - Cursor-based border placement

**Refactored Logic:**
- Header rendering completely isolated from data row rendering
- Both `Show-SessionMenu()` and `Write-SingleMenuRow()` now call shared `Get-DynamicPathWidth()`
- Header truncation logic prevents text from exceeding `$BoxWidth - 1` position
- Space calculation based on actual cursor position rather than predicted width

**Border Calculation:**
- Row structure: `|` (1) + ` ` (1) + content + ` ` (1) + `|` (1) = BoxWidth
- Content width: BoxWidth - 4
- Path width: BoxWidth - 4 - (column widths) - (spaces between columns)
- Right border placement: Read cursor X position, calculate spaces needed to reach BoxWidth - 1

**Header Rendering Flow:**
1. Write top border: `+----...----+`
2. Write left border and padding: `| `
3. Loop through visible columns, checking available space before each
4. Truncate column text if exceeds available space
5. Stop printing columns if no space remains
6. Call `PlaceHeaderRightHandBorder()` to place `|` at exact position
7. Write bottom border: `+----...----+`

#### Changes

**Menu Structure:**
- Removed redundant border line between header and data sections
- Header box and data box are now visually distinct
- Header respects column configuration (hidden columns don't show)

**Border Logic:**
- Eliminated all hardcoded border width assumptions
- Border placement now measured, not calculated
- Handles window resize gracefully

---

## Previous Version: 1.9.0 (2026-01-24)

### Release Notes

This release adds dynamic column configuration with persistent settings, allowing users to customize which columns appear in the main menu.

#### Major Features

**Column Configuration System**
- Press G key in main menu to access column configuration
- Interactive menu with checkboxes for all 11 columns:
  - Active, Model, Session, Notes, Messages, Created, Modified, Cost, Win Terminal, Forked From, Path
- Arrow key navigation with yellow highlighting on current selection
- Space or Enter to toggle checkboxes
- Save and Exit / Abort options
- Configuration persisted to `~/.claude-menu/column-config.json`

**Notes Column (10 characters)**
- Added Notes column to main menu display
- Hidden by default, can be enabled via column configuration
- Integrated with existing notes functionality
- Full sortable column (press 4 key for notes sort)

**Dynamic Column Display**
- Headers and rows built dynamically based on user configuration
- Column widths adjust automatically when columns hidden/shown
- Path column remains variable width, adjusts to available space
- Arrow key navigation respects column configuration

#### Changes

**Column Management:**
- New `Get-ColumnConfiguration()` function - loads settings from JSON
- New `Set-ColumnConfiguration()` function - saves settings to JSON
- New `Show-ColumnConfigMenu()` function - interactive configuration UI
- Default configuration: All columns visible except Notes

**Menu Updates:**
- Added "confiG" option to main menu prompt (G key)
- Only shown in main menu, not in Win Terminal Config mode
- Menu prompt: `...Refresh | confiG | PgUp | PgDn | eXit`

**Display Updates:**
- `Show-SessionMenu()` builds headers/rows dynamically based on config
- `Write-SingleMenuRow()` respects column configuration during navigation
- Column sort mapping updated: 1=Active, 2=Model, 3=Session, 4=Notes, 5=Messages, 6=Created, 7=Modified, 8=Cost, 9=WinTerminal, 10=ForkedFrom, 11=Path

**Technical Details:**
- Column config file: `$Global:ColumnConfigPath = "$Global:MenuPath\column-config.json"`
- Configuration structure: Hashtable with column names as keys, boolean visibility as values
- Config persists across program restarts
- Error handling with fallback to default configuration

#### Default Column Visibility
```json
{
  "Active": true,
  "Model": true,
  "Session": true,
  "Notes": false,
  "Messages": true,
  "Created": true,
  "Modified": true,
  "Cost": true,
  "WinTerminal": true,
  "ForkedFrom": true,
  "Path": true
}
```

---

## Previous Version: 1.8.0 (2026-01-24)

### Release Notes

This release adds session notes functionality, fixes the rename feature, and improves menu UX by removing all key echoing and streamlining the debug menu.

#### Major Features

**Session Notes**
- Add notes to any session (archived or active)
- Press N key in session options menu to add/edit notes
- Notes displayed under session options: "Notes: your text here"
- Notes stored persistently in session-mapping.json
- Press Enter with empty input to clear notes

**Menu Key Handling Improvements**
- Invalid key presses no longer echo to screen
- All menus silently ignore invalid input without visual feedback
- Only valid keys trigger actions - cleaner, more professional UX
- Applies to all 15+ menus throughout application

**Debug Menu Enhancements**
- Simplified toggle text: "Debug Off" (when on) or "Debug On" (when off)
- Removed redundant "Toggle - Turn Debug" prefix
- Centered "DEBUG MODE" header text in separator lines
- Changed hotkey from T (Toggle) to D (Debug)

#### Bug Fixes

**Rename Feature Fixed**
- Fixed parameter name error when calling New-SessionBackgroundImage
- Changed from incorrect `-ProjectPath` to use proper wrapper function
- Rename now correctly generates new background images and profiles
- Error was: "A parameter cannot be found that matches parameter name 'ProjectPath'"

#### Changes

**Notes Implementation:**
- Added `Get-SessionNotes()` function - retrieves notes from session-mapping.json
- Added `Set-SessionNotes()` function - stores notes with proper property handling
- Updated `Get-ForkOrContinue()` to accept and display Notes parameter
- Added N key handler for both archived and normal session menus
- Added notes action handler in main loop with current notes display
- Notes integrated into session display: shown under "Session options"

**Menu Echo Removal:**
- Removed `Write-Host $choice` statements from all menu functions
- Removed echo from: Get-ForkOrContinue, Get-SessionManagementChoice, Get-RegenerateImageChoice
- Removed echo from: Get-ModelChoice, Get-TrustedSessionChoice, directory selection
- Removed echo from: Enable/Disable-GlobalBypassPermissions, Resolve-BackgroundImageConflict
- Removed echo from: Show-DebugToggle, all Y/N confirmation prompts
- Debug logging still captures key presses for troubleshooting

**Debug Menu Updates:**
- Menu text: `Debug Off | Notepad - Open Debug Log | Instructions - Show debug mode help | Abort`
- Header centered in 40-character wide separator lines
- Switch case changed from 'T' to 'D' for consistency with menu text
- More concise and professional appearance

#### Technical Details

**New Functions:**
- `Get-SessionNotes($SessionId)` - Returns notes string from session-mapping.json
- `Set-SessionNotes($SessionId, $Notes)` - Stores notes, creating entry if needed

**Modified Functions:**
- `Get-ForkOrContinue()` - Added Notes parameter, displays notes under session options
- `Rename-ClaudeSession()` - Fixed to use `New-SessionBackgroundImage` wrapper instead of direct call
- `Show-DebugToggle()` - Simplified toggle text, centered header, changed hotkey to D
- All menu functions - Removed key echo statements, silently ignore invalid input

**Session Mapping Schema:**
- Added `notes` field to session entries in session-mapping.json
- Notes stored as string, empty string if no notes
- Property added dynamically with Add-Member if doesn't exist

---

## Previous Version: 1.7.0 (2026-01-21)

### Release Notes

This release refines the user interface with silent error handling, consolidated single-line menus, improved navigation prompts, and fixes cursor positioning issues during workflows.

#### Major Features

**Silent Invalid Input Handling**
- Invalid key presses no longer display error messages
- Menus silently wait for valid input without feedback
- Cleaner, less intrusive user experience
- No "Invalid choice. Please enter..." messages

**Single Display Menu Prompts**
- Menu prompts displayed once before input loop
- No repeated redisplay after invalid input
- Prompt remains visible on screen
- Reduces visual clutter and screen flashing

**Consolidated Single-Line Menus**
- All menu options now shown on single line with descriptions
- Example: `Opus - Most capable | Sonnet - Balanced (Recommended) | Haiku - Fast | Abort`
- Eliminates redundant multi-line descriptions followed by summary line
- More compact, easier to scan
- Applies to: Model selection, Directory choice, Debug menu, Session management, Image regeneration, Fork/Continue, Trusted session, Background conflict

**Improved Navigation Prompt**
- Changed from `Use UP/DOWN arrows, Enter to select` to `Choose with ▲▼, then [Enter] to select`
- Arrow symbols (▲▼) displayed in yellow
- [Enter] displayed in yellow
- More visual, easier to understand at a glance

**Directory Path Inline Display**
- Directory selection now shows actual path in menu: `Use Current - C:\repos\Fork | Set different directory | Abort`
- Removed redundant "Current directory: C:\repos\Fork" line above prompt
- More compact presentation

**Win Terminal Config Menu Consistency**
- Changed "eXit" to "Abort" to match other menus
- Changed "All Sessions" key from 'A' to 'L' to free up 'A' for Abort
- Consistent terminology across all menus

#### Bug Fixes

**Fixed Cursor Jumping During Workflows**
- Removed cursor positioning code from all dialog functions
- Dialogs no longer jump back to main menu position during workflows
- Fixed issue where model selection appeared above name entry during new session creation
- Workflows now flow naturally down the screen
- Affected functions: Get-ModelChoice, Get-TrustedSessionChoice, Get-ForkOrContinue, Get-SessionManagementChoice, Get-RegenerateImageChoice, Show-DebugToggle, Show-CostAnalysis, Enable-GlobalBypassPermissions, Disable-GlobalBypassPermissions, Start-NewSession

#### Changes

**Menu Format Updates:**
- All menus converted from multi-line to single-line format
- All trailing colons after "Abort" removed
- All menu options include descriptions inline

**Input Handling:**
- Removed all "Invalid choice" error messages and sleep delays
- Default switch cases now just continue loop silently
- Win Terminal Config menu 'A' key now triggers Abort
- Win Terminal Config menu 'L' key now triggers "aLl Sessions"

**Navigation:**
- Arrow symbols use `[char]0x25B2` (▲) and `[char]0x25BC` (▼)
- All arrow and [Enter] text displayed in yellow color

---

## Previous Version: 1.6.0 (2026-01-21)

### Release Notes

This release standardizes the user interface with uniform menu prompts, single-keypress input, consolidated background image generation, and critical bug fixes.

#### Major Features

**Uniform Menu System**
- All menus now use consistent prompt format with highlighted key letters in yellow
- Single-keypress input throughout - no Enter key needed
- Example: `1 Continue | 2 Fork | 3 Delete | 4 Rename | Abort` (keys in yellow)
- Applies to all 13+ menus: Debug, Session Management, Model Selection, Permission Modes, Confirmations, etc.
- Cleaner, more intuitive interface with reduced keystrokes

**Universal Escape Key Support**
- Esc key works as Abort/Cancel/No in all menus
- Silent feature - not advertised but always available
- Consistent behavior: Esc = back one level throughout entire application

**Unified Background Image Generation**
- Single `New-UniformBackgroundImage()` function replaces three separate implementations
- All background images now display identical 6-line format:
  1. Session Name (48pt bold)
  2. "Forked from: [parent]" (32pt italic, optional)
  3. COMPUTER:USERNAME (32pt italic)
  4. "branch: [branch]" (32pt italic, optional)
  5. "model: [model]" (32pt italic, optional)
  6. Full directory path (32pt italic)
- 1920x1080 PNG, semi-transparent dark blue background (ARGB: 180,20,20,40)
- Consistent across new sessions, forks, continued sessions, and custom text

**Fixed "Last Command" Display Clearing**
- Cursor position captured BEFORE "Last command" display (not after)
- Menu actions properly clear the command display and reposition cursor
- ANSI escape sequence clears screen from cursor down
- Dialogs now appear immediately below sub-menu without blank space

#### Bug Fixes

**Unnamed Session Launch Fixed**
- Unnamed sessions now launch in Windows Terminal (not broken inline mode)
- Changed from `Start-Process -NoNewWindow -Wait` to `wt.exe -d "$dir" -- "$claudePath" --resume $sessionId`
- Fixed 7 locations where this bug occurred
- Sessions without profiles now work correctly

#### Changes

**Menu Prompt Updates:**
- `Enable-GlobalBypassPermissions`: `Switch to Quiet Mode | Show Info | Abort` (Q, S, A in yellow)
- `Disable-GlobalBypassPermissions`: `Switch to Chatty Mode | Show Info | Abort` (C, S, A in yellow)
- `Show-DebugToggle`: `1 Toggle | 2 Notepad | 3 Instructions | 4 Abort`
- `Get-SessionManagementChoice`: `1 Regenerate | 2 Delete | 3 Remove | Abort`
- `Get-RegenerateImageChoice`: `1 Refresh | 2 File | 3 Text | Abort`
- `Get-ForkOrContinue`: `1 Continue | 2 Fork | 3 Delete | 4 Rename | Abort`
- `Get-ModelChoice`: `1 Opus | 2 Sonnet | 3 Haiku | Abort`
- `Get-TrustedSessionChoice`: `Yes | No | Abort`
- All Y/N confirmations: `Yes | No` (Y, N in yellow)

**Input Handling:**
- Replaced `Read-Host` with `$host.UI.RawUI.ReadKey()` for single-keypress
- Added Esc key handling (virtual key code 27) to all prompt loops
- Key echo displays immediately after press

**Background Image Functions:**
- `New-UniformBackgroundImage()` - Core generation function (lines 4781-4918)
- `New-SessionBackgroundImage()` - Wrapper for new/fork sessions
- `New-ContinueSessionBackgroundImage()` - Wrapper for continued sessions
- `New-CustomTextBackgroundImage()` - Wrapper for custom text
- All wrappers now pass ProjectPath parameter for Line 6 display

**"Last Command" Fix:**
- `$Global:PromptEndY` captured at line 2107 (before "Last command" display)
- Previously captured at line 2146 (after display with padding)
- Clearing code in `Get-ArrowKeyNavigation` at lines 2252-2301
- Removes cursor positioning from individual dialog functions

---

## Previous Version: 1.5.0 (2026-01-21)

### Release Notes

This release adds dynamic pagination, session renaming, improved tracked name handling, and simplified mode switching.

#### Major Features

**Dynamic Menu Pagination**
- Screen-aware height calculation adjusts to terminal size automatically
- Maintains 5-line buffer below sub-menu for readability
- Page navigation with PgUp/PgDn keys
- Page indicator shows "pg 1/x" when multiple pages exist
- Automatic page reset when changing sort order
- Sorts all data, displays current page slice

**Session Rename (M Key)**
- Rename sessions directly from main menu
- Updates all references automatically:
  - Claude's sessions-index.json (customTitle field)
  - Windows Terminal profile name
  - Session mapping file (wtProfileName + timestamp)
- Character sanitization for filesystem safety
- Instant menu refresh to show new name
- Cancel option (press Enter with empty name)

**Tracked Name Support**
- Sessions in [brackets] now properly recognized as having names
- Windows Terminal profile detection works for tracked names
- No duplicate "create profile" prompts for sessions with tracked names
- Display name priority: customTitle → trackedName → sessionId
- Fork workflow displays tracked names correctly

**Simplified Mode Switching**
- Clean [Y/I/N] prompt for Quiet/Chatty mode
- [Y] enables mode immediately (one keypress)
- [I] shows detailed information on demand
- [N] cancels operation
- Detailed explanations hidden by default to reduce information overload

#### Changes

**Pagination:**
- Added `$Global:CurrentPage` variable to track current page
- `Show-SessionMenu()` calculates available rows dynamically
- Window height calculation: height - 17 (title + headers + borders + prompts + buffer)
- Page indicator displayed when totalPages > 1
- Returns `TotalPages`, `CurrentPage`, and `AllRows` in menu result
- PgUp/PgDn handlers added to `Get-ArrowKeyNavigation()` (virtual key codes 33/34)
- Main loop handles PageUp/PageDown actions

**Session Rename:**
- New `Rename-ClaudeSession()` function handles complete rename workflow
- Updates Claude's sessions-index.json customTitle
- Renames Windows Terminal profile if exists
- Updates session-mapping.json wtProfileName and timestamp
- Added 'M' key handler in `Get-ArrowKeyNavigation()`
- Added Rename action handler in main loop
- Sub-menu shows "renaMe" option (M highlighted)

**Tracked Name Support:**
- `Start-ContinueSession()` checks both customTitle AND trackedName
- `Show-SessionMenu()` passes trackedName to `Get-WTProfileName()` if customTitle empty
- `Start-ForkSession()` uses tracked names for display
- Display name resolution updated in 4+ locations: customTitle → trackedName → sessionId

**Mode Switching:**
- `Enable-GlobalBypassPermissions()` uses [Y/I/N] prompt structure
- `Disable-GlobalBypassPermissions()` uses [Y/I/N] prompt structure
- Detailed information shown only when user presses [I]
- Faster common case (Y for enable, N for cancel)

**Bug Fixes:**
- Fixed sessions with tracked names incorrectly prompting to create profiles
- Fixed mode switching headers saying "YOU ARE IN" instead of "ENABLING"

#### Technical Details

**New Functions:**
- `Rename-ClaudeSession()` - Comprehensive session rename with all metadata updates

**New Global Variables:**
- `$Global:CurrentPage` - Tracks current page number for pagination

**Modified Functions:**
- `Show-SessionMenu()` - Added pagination logic with dynamic row calculation and page slicing
- `Get-ArrowKeyNavigation()` - Added PgUp/PgDn key handlers, added $TotalPages parameter
- `Start-ContinueSession()` - Checks both customTitle AND trackedName for named sessions
- `Start-ForkSession()` - Enhanced display name resolution with tracked name support
- `Enable-GlobalBypassPermissions()` - Redesigned with [Y/I/N] prompt structure
- `Disable-GlobalBypassPermissions()` - Redesigned with [Y/I/N] prompt structure
- Main loop - Added PageUp/PageDown/Rename action handlers

**Pagination Implementation:**
1. Calculate available rows: `windowHeight - 17`
2. Determine if pagination needed: `totalRows > availableRows`
3. Calculate total pages: `Ceiling(totalRows / rowsPerPage)`
4. Validate current page is within bounds
5. Slice sorted data: `$rows[$startIndex..$endIndex]`
6. Display page indicator when `totalPages > 1`
7. Reset to page 1 on sort changes

**Rename Workflow:**
1. Prompt for new name (or cancel with empty input)
2. Sanitize filesystem characters
3. Update Claude's sessions-index.json
4. Rename Windows Terminal profile if exists
5. Update session-mapping.json
6. Refresh menu to show changes

**Sub-menu Updates:**
- "renaMe" option added to all three prompt variations (DeleteMode, ShowUnnamed, Normal)
- "PgUp | PgDn" shown when $TotalPages > 1

#### Breaking Changes

None - fully backward compatible with v1.4.0

#### Migration Notes

No manual migration required. All new features work automatically:
- Pagination activates automatically when session count exceeds screen capacity
- Rename functionality available immediately (press M on any session)
- Tracked name recognition works for existing sessions
- Mode switching prompts updated automatically

---

## Previous Version: 1.4.0 (2026-01-20)

### Release Notes

This release focuses on Git integration, model tracking, smart image management, and directory selection.

#### Major Features

**Git Branch Integration**
- Automatically detects git branch in session directories
- Displays branch on background images (third line)
- Shows git branch in session options menu

**Model Information Display**
- Shows model name (Opus/Sonnet/Haiku) on background images (fourth line)
- Model-first workflow (select before generating background)
- Model tracking in session-mapping.json

**Smart Background Image Management**
- Conflict resolution with 4 options: Overwrite, Use, Create New Name, Abort
- Auto-overwrites orphaned backgrounds (0 profiles using it)
- Shows profile usage before prompting
- Auto-numbering for unique names (Name1, Name2, etc.)

**Directory Selection**
- Shows current directory in main menu header
- Prompts for directory when creating new sessions
- Directory validation with reprompting
- Multiple abort points during session creation

---

## Previous Version: 1.3.0 (2026-01-20)

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
