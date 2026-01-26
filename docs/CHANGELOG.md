# Changelog

All notable changes to Windows Claude Code Forker will be documented in this file.

## [2.0.0] - 2026-01-26

### Validation Tests

#### 15 New Machine-Independent Tests (Tests 66-80)

**Keyboard Handler Tests:**
- **Test 66:** Enter Key Handlers - Verifies Enter key defaults exist in 10+ menus
- **Test 67:** Escape Key Handlers - Verifies Escape key abort handling

**Regression Prevention Tests:**
- **Test 68:** Select-First Pattern - Catches duplicate profile bugs (we found 7 locations)
- **Test 77:** Draw-SessionRow Has Limit - Catches missing column bugs

**Core Function Tests:**
- **Test 69:** Get-ForkOrContinue Function - Fork/continue with required parameters
- **Test 70:** Date/Time Formatting - Validates .ToString('MM/dd HH:mm') pattern
- **Test 71:** Cost Calculation Logic - Tests cost math with known values
- **Test 74:** Get-SessionCost Function - Graceful handling of null input
- **Test 76:** Get-SessionMessageCount - Handles missing sessions (returns 0)
- **Test 77:** Get-SessionTokenUsage - Handles missing sessions (returns null)

**Feature Function Tests:**
- **Test 72:** Archive Status Functions - Set/Get-SessionArchiveStatus exist
- **Test 73:** Session Mapping Functions - 3 mapping functions exist
- **Test 75:** WT Profile Functions - 4 Windows Terminal profile functions exist
- **Test 78:** Session Notes Functions - Get/Set session notes exist
- **Test 79:** Git Branch Detection - Handles non-git directories gracefully
- **Test 80:** Refresh Returns Updates - UpdatedBackgrounds list is returned

**Total Tests:** 80 (up from 65)

---

## [1.10.7] - 2026-01-25

### Performance Optimizations

#### Menu Loading Caching System
- **9 Functions Now Use Caching** - Major performance improvement for menu loading
- **Get-CachedWTSettings** - Windows Terminal settings parsed once per render cycle
- **Get-CachedSessionMapping** - Session mapping JSON parsed once per render cycle
- **Get-CachedProfileRegistry** - Profile registry JSON parsed once per render cycle
- **Clear-MenuCaches** - Clears all caches at start of each menu render
- **Estimated 10-20x Speedup** - For JSON parsing portion of menu loading

#### Functions Updated to Use Caching
- `Get-WTProfileName` - No longer reads WT settings for every session
- `Get-WTProfileDetails` - Uses cached WT settings
- `Get-SessionMapping` - Uses cached session mapping
- `Get-SessionMappingEntry` - Uses cached session mapping
- `Get-ForkedFromInfo` - Uses cached session mapping
- `Get-ForkTree` - Uses cached profile registry
- `Get-ModelFromRegistry` - Uses cached profile registry
- `Get-SessionArchiveStatus` - Uses cached session mapping
- `Get-SessionNotes` - Uses cached session mapping

### New Features

#### Loading Spinner Infrastructure
- **Show-LoadingSpinner Function** - Ready for future use
- **Global Spinner Variables** - SpinnerChars and SpinnerIndex
- **Carriage Return Method** - Simple, reliable spinner animation

### Validation Tests

#### 8 New Tests (Tests 58-65)
- **Test 58:** Caching Functions Exist - Verifies all 4 cache functions available
- **Test 59:** Cache Variables Defined - Checks all 6 cache global variables
- **Test 60:** Clear-MenuCaches Behavior - Verifies cache clearing works
- **Test 61:** Cache Null-Check Pattern - Validates proper cache initialization pattern
- **Test 62:** Functions Use Caching - Confirms key functions use Get-CachedXxx
- **Test 63:** Path Normalization Function - Verifies Normalize-WTBackgroundPaths exists
- **Test 64:** Windows Path Style in WT Settings - Checks for Linux-style path issues
- **Test 65:** Loading Spinner - Validates spinner function and variables

**Total Tests:** 65 (up from 57)

---

## [1.10.6] - 2026-01-25

### New Features

#### Background Image Diagnostics System
- **dIagnose Option** - New 'I' key in Windows Terminal Profile Management menu
- **5-Section Diagnostic Report** - Comprehensive analysis of background image configuration:
  - Session Data (title, ID, path, model, branch, computer:user, forked-from)
  - File Paths (background.png and background.txt existence with timestamps)
  - Windows Terminal Profile (GUID, background path, path style validation)
  - Background.txt Contents (all stored values displayed)
  - Value Comparison (stored vs current with difference highlighting)
- **Path Style Detection** - Identifies Linux-style (forward slash) vs Windows-style (backslash) paths
- **Interactive Fix Option** - Press 'F' to immediately fix incorrect path styles

#### Automatic Path Normalization
- **Normalize-WTBackgroundPaths Function** - Scans all Claude-* profiles during refresh
- **Auto-Fix Linux Paths** - Converts forward slashes to backslashes automatically
- **Refresh Integration** - Path normalization runs on every Refresh (R key)
- **Fixed Path Reports** - Shows which profiles had paths corrected

### Bug Fixes

#### Windows Terminal Path Style Fix
- **Fixed 7 Locations** - All backgroundImage assignments now use Windows-style backslashes
- **Root Cause** - Code was converting `\` to `/` for "JSON compatibility" (incorrect assumption)
- **Impact** - Background images were not displaying because Windows Terminal requires backslash paths

#### Computer:User Comparison Fix
- **Fixed Inconsistency** - Background creation used colon (`:`) but comparison used backslash (`\`)
- **Before** - Stored: `A6:steve`, Current: `A6\steve` (always showed as different)
- **After** - Both now use colon: `A6:steve` (proper comparison)
- **Impact** - Refresh no longer falsely reports all sessions as updated

### Improvements

#### Context-Aware Menu Messages
- **Windows Terminal Config Menu** - Shows: "Windows Terminal will cache images." (red) + "Background image changes need a Windows Terminal restart." (gray)
- **Main Menu** - Shows original: "A newly forked session shows in [brackets]..." message

### Anti-Fragility Improvements
- Edge case detection for path style mismatches
- Self-healing path normalization on refresh
- Consistent separator usage across codebase
- Diagnostic tools for troubleshooting background image issues

---

## [1.10.5] - 2026-01-25

### New Features

#### Context Limit Management System (LimitFeature)
- **Context Usage Display** - Shows context window usage percentage in Session Options screen
- **Color-Coded Severity** - Green (<50%), Cyan (50-74%), Yellow (75-89%), Red (90%+)
- **Actionable Guidance** - Displays warnings and recommendations at high context usage
- **Limit Column** - New configurable column showing context % in main menu (hidden by default)
- **Token Calculation Fix** - Now correctly calculates total context including cached tokens

#### Limit Instructions Guide (L Key)
- **Comprehensive Guide** - Press 'L' in Session Options for detailed context management help
- **Strategy 1: Fork** - When and how to fork sessions to preserve context
- **Strategy 2: /memory** - Full explanation of /memory command, where it saves, usage limits
- **Strategy 3: CLAUDE.md** - How to maintain persistent project knowledge
- **Strategy 4: /compact** - When to use manual compaction
- **Recommended Workflow** - Step-by-step guide for long-running sessions
- **Quick Reference** - Commands at a glance

#### Background Parameter Refresh System
- **Comprehensive Checks** - Refresh now checks ALL background parameters (model, branch, computer:user, directory, forked-from)
- **Auto-Regeneration** - Background images regenerate if ANY parameter changed
- **Performance Optimization** - Model reads only run on explicit Refresh, not on startup/return
- **Model Caching** - Added ModelCache for faster repeated lookups

### Bug Fixes

#### Limit Column Navigation Fix
- **Fixed Draw-SessionRow** - Limit column was missing from up/down arrow navigation redraw
- **Added Consistency Test** - New Test 55 validates all format sections have consistent column order

#### Context Calculation Fix
- **Fixed Token Sum** - Now correctly sums input_tokens + cache_creation_input_tokens + cache_read_input_tokens
- **Was Showing 0%** - Previously only read input_tokens (8) instead of total context (52K+)

### Improvements

- Session Options now shows Context usage with detailed breakdown (e.g., "26% (52K / 200K tokens)")
- Added Test 55: Column Consistency Check to prevent future column sync issues
- Optimized expensive operations to only run on explicit Refresh

---

## [1.10.4] - 2026-01-25

### New Features

#### Background Image Sanity Check
- **Sanity Check Menu** - New option in Windows Terminal Config mode (press 'S')
- Scans all sessions with WT profiles and compares stored data with current session data
- Detects out-of-sync backgrounds (model changes, git branch changes, missing images)
- Allows regenerating individual sessions or all out-of-sync sessions at once
- Updates session-mapping.json with current model and git branch after regeneration

#### Automatic Model Change Detection
- Background images now automatically regenerate when model changes are detected
- Compares stored model in session-mapping.json with current model from session file
- Triggers during session list refresh/load

#### Git Branch Tracking
- Session mappings now track git branch information
- Enables detection of branch changes for background regeneration

#### Background Image Text Files
- Every background image now has a corresponding .txt file
- Contains the same information rendered in the image (session name, model, branch, etc.)
- Makes it easy to inspect background content without viewing the PNG

### Improvements

- Removed colons from all "Yes | No" prompts for cleaner UI
- Fixed PowerShell string interpretation issue with "(deleted or unnamed)" text

## [1.10.3] - 2026-01-24

### Critical Bug Fix

#### PowerShell Comparison Operator Bug
- **Fixed File Creation Bug** - Corrected critical syntax error in `PlaceHeaderRightHandBorder` function (line 2522)
- **Root Cause** - Used `>` (file redirect operator) instead of `-gt` (PowerShell comparison operator)
- **Symptom** - Created mysterious file named "170" in working directory on every script execution
- **Impact** - File contained "1 7 0" (spaced characters) due to PowerShell's file redirect behavior
- **Resolution** - Changed `if ($currentX > $targetX)` to `if ($currentX -gt $targetX)`
- **Verification** - Comprehensive code audit confirms no other instances of this error pattern

### Technical Details

**The Bug:**
```powershell
# INCORRECT (was creating file "170"):
if ($currentX > $targetX) {

# CORRECT (proper PowerShell syntax):
if ($currentX -gt $targetX) {
```

**Why This Happened:**
- In PowerShell, `>` is the file redirect operator, NOT a comparison operator
- PowerShell requires `-gt`, `-lt`, `-eq`, `-ge`, `-le`, `-ne` for comparisons
- When `$currentX=0` and `$targetX=170`, the expression `$currentX > $targetX` was interpreted as "redirect value 0 to file named 170"
- Script ran without errors because PowerShell silently created the file

**Prevention:**
- Performed full codebase audit using regex patterns
- Confirmed 355+ proper PowerShell comparison operators (`-gt`, `-lt`, `-eq`, etc.) used throughout rest of script
- This was an isolated syntax error, not a systemic issue

## [1.10.2] - 2026-01-24

### Major Features

#### Comprehensive Validation System
- **40 Automated Tests** - Built-in self-protection with comprehensive test suite
- **Infrastructure Tests (15)** - Validates PowerShell version, Claude CLI, Windows Terminal, directory structure, JSON integrity, orphaned resources
- **Logic Tests (15)** - Validates functions, path encoding, sanitization, GUID format, date parsing, model names, menu key handlers
- **Algorithm Tests (10)** - Validates string truncation, path encoding edge cases, JSON structure, WT profile format, background paths, session mapping consistency
- **Accessible from Debug Menu** - Press 'D' → 'V' to run all validation tests
- **Self-Healing Detection** - Tests detect mismatches between menu keys and handlers, missing functions, data corruption
- **Machine-Independent** - Tests validate logic and algorithms, not user-specific configuration values

### Bug Fixes

#### Test 17: Function Name Validation
- **Fixed Missing Function Detection** - Corrected function name from "New-BackgroundImage" to "New-SessionBackgroundImage"
- **Accurate Function Checking** - Test 17 now validates actual function names in codebase
- **Zero Failures** - All 40 tests now pass (previously 1 failure)

#### Test 24: Non-Invasive Sort Column Validation
- **Removed Global State Modification** - No longer sets `$Global:SortColumn` during testing
- **Local Test Value** - Uses local variable to validate logic without affecting user's current sort preference
- **User-Friendly** - Validation doesn't disrupt active user sessions

#### Test 28: Non-Invasive Debug State Validation
- **Removed State Toggling** - No longer toggles debug state on/off during testing
- **Function Existence Check** - Validates debug functions exist and return valid types without modifying state
- **Preserves User Settings** - User's debug mode remains unchanged after validation

### Changes

**Validation System:**
- New `Test-SystemValidation()` function - Lines 526-1155: Complete validation framework with 40 tests
- Test categories:
  - **Tests 1-15:** Infrastructure (PowerShell, CLI tools, directories, JSON files, orphaned resources)
  - **Tests 16-30:** Logic & algorithms (functions, encoding, sanitization, parsing, globals)
  - **Tests 31-40:** Menu integrity, edge cases, consistency (key handlers, column sorts, path encoding, GUID validation, model names)
- Added 'V' option to Debug menu for validation tests
- Test results display with color-coded status (PASS=Green, WARN=Yellow, FAIL=Red)
- Summary shows total passed/warned/failed counts
- Script-scoped counter variables for accurate tracking

**Menu Integration:**
- Debug menu updated with Validation option: `Debug Off | Notepad - Open Debug Log | Instructions - Show debug mode help | Validation - Run system tests | Abort`
- Added 'V' key handler in Debug menu (line 630-638)
- Validation accessible via: Main Menu → Debug (D) → Validation (V)

**Test Output Format:**
```
========================================
      SYSTEM VALIDATION TESTS
========================================

[PASS] PowerShell Version
        Version 5.1
[PASS] Claude CLI
        Found at C:\Users\user\.local\bin\claude.exe
[WARN] Orphaned WT Profiles
        5 orphaned profile(s) found
...

========================================
           TEST SUMMARY
========================================

Passed: 38
Warnings: 2
Failed: 0

All critical tests passed. Some warnings noted.
```

### Technical Details

**New Functions:**
- `Test-SystemValidation()` - Lines 526-1155: Master validation function with 40 comprehensive tests
- `Write-TestResult($TestName, $Status, $Message)` - Nested function for formatted test output with color coding

**Test Categories:**

**Infrastructure Tests (1-15):**
1. PowerShell Version (≥5.1)
2. Claude CLI Exists
3. Windows Terminal Available
4. .claude-menu Directory Structure
5. session-mapping.json Integrity
6. background-tracking.json Integrity
7. Windows Terminal settings.json
8. Orphaned Windows Terminal Profiles
9. Missing Session Files
10. Orphaned Background Images
11. Reserved Variable Usage ($input)
12. Claude Projects Directory
13. Path Encoding (C:\repos → C--repos)
14. Session Discovery
15. Column Configuration

**Logic Tests (16-30):**
16. Path Encoding Consistency (Idempotency)
17. Critical Functions Exist
18. Safe Name Sanitization
19. Session ID Format (GUID)
20. Date Parsing Logic
21. Truncate-String Function
22. Global Variable Initialization
23. Model Name Parsing
24. Sort Column Range Validation
25. Menu Navigation Keys Defined
26. Table Box Width Calculation
27. Permission State Consistency
28. Debug State Functions
29. Color Scheme Constants
30. Session Object Structure

**Algorithm Tests (31-40):**
31. Menu Keys Match Handlers
32. Column Sort Keys (1-11)
33. Path Encoding Edge Cases
34. String Truncation Edge Cases
35. JSON File Structure Validation
36. WT Profile Name Format
37. GUID Validation Logic
38. Background Image Path Consistency
39. Session Mapping Consistency
40. Model Name Format Validation

**Self-Protection Features:**
- Test 31 validates every menu key has a corresponding handler
- Test 32 validates all sort column keys work
- Test 17 validates all critical functions exist
- Tests catch refactoring errors before they cause runtime failures
- Tests validate algorithm correctness independent of user data

### Breaking Changes
None - Fully backward compatible

### Migration Notes
No action required. Validation system is immediately available in Debug menu.

---

## [1.10.1] - 2026-01-24

### Major Features

#### Universal Enter Key Defaults
- **Consistent UX** - All menus support Enter key for default/first option
- **15+ Menus Updated** - Debug, directory, modes, model, confirmations, etc.
- **Intuitive** - Press Enter for most common action in any context
- **Reduced Keystrokes** - No need to remember specific hotkeys for defaults

#### Menu Pattern Implementation
- **Debug Menu** - Enter → Toggle Debug (D key equivalent)
- **Directory Selection** - Enter → Use Current Directory (C key)
- **Mode Switching** - Enter → Switch to Chatty/Quiet (C/Q keys)
- **Model Selection** - Enter → Opus (O key equivalent)
- **Profile Management** - Enter → Regenerate (R key equivalent)
- **All Confirmations** - Enter → Yes (Y key equivalent)
- **Fork/Continue** - Enter → Continue (normal) / Unarchive (archived)

#### Menu Text Simplification
- **Concise Labels** - Removed verbose descriptions from options
- **Fork/Continue** - "Continue Claude Session" (was "Continue - Resume Claude Session")
- **Fork/Continue** - "Fork Session" (was "Fork - Create new branch")
- **Easier Scanning** - More compact, professional appearance

### Bug Fixes

#### Gitignore Configuration
- **Removed *.cmd Rule** - .cmd files can now be committed to repository
- **Fixed Blocking** - Resolves issue preventing .cmd file tracking

### Changes

**Enter Key Implementation:**
- Added virtual key code 13 (Enter) detection to all menu loops
- Placed after Esc handling, before main choice logic
- Sets choice variable to appropriate default action
- Maintains existing validation and flow

**Modified Functions:**
- `Show-DebugToggle()` - Line 565
- `Start-NewSession()` - Line 2949 (directory selection)
- `Disable-GlobalBypassPermissions()` - Lines 4417, 4482
- `Enable-GlobalBypassPermissions()` - Lines 4279, 4329
- `Get-ModelChoice()` - Line 4062
- `Get-TrustedSessionChoice()` - Line 4107
- `Get-SessionManagementChoice()` - Line 3708
- `Get-RegenerateImageChoice()` - Line 3755
- `Resolve-BackgroundImageConflict()` - Line 5250
- `Get-ForkOrContinue()` - Line 3893 (with archived session logic)
- Multiple Yes/No confirmation prompts (8 locations)

**Technical Details:**
```powershell
# Pattern used throughout:
if ($key.VirtualKeyCode -eq 13) {
    $choice = 'DEFAULT_ACTION'  # Context-specific default
}
```

**Gitignore Update:**
- Removed line 3: `*.cmd`
- Allows .cmd files in version control
- User-specific files still ignored via *.lnk

### Breaking Changes
None - Fully backward compatible

### Migration Notes
No action required. Enter key defaults work immediately on script reload.

---

## [1.9.5] - 2026-01-24

### Major Features

#### Separated Header Box
- **Visual Separation** - Headers now display in separate box above main menu
- **Professional Layout** - Header box and data box clearly distinguished
- **Clean Design** - Matches professional UI design patterns with boxed sections
- **Both Menus** - Applied to main menu and Win Terminal Config menu

#### Sorted Column Highlighting
- **Yellow Highlight** - Active sort column highlighted in yellow in headers
- **Visual Feedback** - Immediate visual indication of current sort order
- **Both Modes** - Works for main menu (dynamic columns) and Win Terminal Config menu
- **Color Coding** - Sorted column in yellow, all others in cyan

#### Intelligent Header Truncation
- **Auto-Truncation** - Headers truncate when screen width insufficient
- **No Wrapping** - Prevents text wrapping that breaks menu layout
- **Graceful Degradation** - Columns drop when space unavailable
- **Perfect Borders** - Border placement accurate regardless of window size

### Bug Fixes

#### Border Alignment Fixed (Critical)
- **Off-by-One Error** - Fixed menu box right border misalignment
- **Shared Calculation** - Created `Get-DynamicPathWidth()` for consistent path width calculation
- **Eliminated Duplication** - Removed duplicate math logic between functions
- **Perfect Alignment** - Border now aligns perfectly with top/bottom borders in all scenarios

#### Precise Header Positioning
- **Cursor-Based** - Border position calculated from actual cursor position, not estimated
- **Edge Case Handling** - Handles overflow where columns exceed available space
- **Truncation** - Truncates overflowing text rather than allowing wrapping
- **Measured Placement** - Reads actual cursor X position to determine spacing needed

### Changes

**New Functions:**
- `Get-DynamicPathWidth($BoxWidth, $ColumnConfig)` - Lines 1470-1503: Centralized path width calculation with consistent math
- `Write-SessionMenuHeader($BoxWidth, $OnlyWithProfiles)` - Lines 1433-1553: Dedicated header rendering function
- `PlaceHeaderRightHandBorder($RowWidth)` - Lines 1418-1431: Cursor-based border placement function

**Refactored Functions:**
- `Show-SessionMenu()` - Removed inline header rendering, now calls `Write-SessionMenuHeader()`
- `Show-SessionMenu()` - Now uses shared `Get-DynamicPathWidth()` for path calculation
- `Write-SingleMenuRow()` - Now uses shared `Get-DynamicPathWidth()` for path calculation

**Header Rendering:**
- Headers check available space before printing each column
- Columns truncate if exceeding available space
- Stop printing columns if no room remains
- Only add space separators when room available
- Call `PlaceHeaderRightHandBorder()` to place `|` at measured position

**Border Calculation Math:**
- Row structure: `|` (1) + ` ` (1) + content + ` ` (1) + `|` (1) = BoxWidth
- Content width: BoxWidth - 4
- Non-Path column count: 10 columns = 144 characters (when all visible)
- Spaces between N columns: N - 1 spaces
- Path width: BoxWidth - 4 - (sum of visible column widths) - (visible columns - 1)

**Menu Structure:**
- Removed redundant border line between header and data boxes
- Header box: `+---+` | headers | `+---+`
- Data box: `+---+` | data rows | `+---+`

### Technical Details

**Border Placement Algorithm:**
1. Write left border: `|`
2. Write padding: ` `
3. Write columns with spaces between
4. Read actual cursor X position
5. Calculate: `spacesNeeded = (BoxWidth - 1) - currentX`
6. Write spacing: `" " * spacesNeeded`
7. Write right border: `|`

**Header Truncation Logic:**
```powershell
for each column:
    get current cursor X position
    calculate available space = targetX - currentX
    if availableSpace <= 0: break (no room)
    truncate column text to fit available space
    write column with color coding
    add space separator if not last column and room available
```

**Path Width Calculation:**
- Count visible non-Path columns and their widths
- Count spaces needed (N visible columns including Path = N-1 spaces)
- Path width = BoxWidth - 4 - column widths - spaces
- Minimum path width: 15 characters

**Sort Column Highlighting:**
- Profile mode: Maps header index to global column numbers (Session=3, Messages=5, etc.)
- Dynamic mode: Tracks column numbers as columns are built (Active=1, Model=2, etc.)
- Compare column number to `$Global:SortColumn`
- Yellow if match, Cyan if no match

---

## [1.9.0] - 2026-01-24

### Major Features

#### Column Configuration System
- **Interactive Column Management** - Press G key in main menu to access column configuration
- **11 Configurable Columns** - Active, Model, Session, Notes, Messages, Created, Modified, Cost, Win Terminal, Forked From, Path
- **Checkbox Interface** - Visual checkboxes show enabled/disabled state for each column
- **Arrow Key Navigation** - Navigate through column list with UP/DOWN arrows
- **Yellow Highlighting** - Current selection highlighted in yellow for easy identification
- **Toggle with Space/Enter** - Press Space or Enter to toggle checkbox state
- **Save and Exit** - Saves configuration and reloads menu with new column layout
- **Abort Option** - Cancel changes without saving
- **Persistent Configuration** - Settings saved to `~/.claude-menu/column-config.json`
- **Automatic Restoration** - Configuration restored on program restart

#### Notes Column Integration
- **10-Character Column** - Notes column added to main menu display
- **Hidden by Default** - Notes column disabled in default configuration (can be enabled via confiG menu)
- **Full Sorting Support** - Press 4 key to sort by Notes column
- **Integrated with Existing Notes** - Works seamlessly with v1.8.0 notes functionality
- **Column 4 Position** - Positioned between Session and Messages columns

#### Dynamic Display System
- **Dynamic Headers** - Column headers built at runtime based on configuration
- **Dynamic Rows** - Row data rendered based on enabled columns
- **Automatic Width Adjustment** - Column widths adjust when columns hidden/shown
- **Variable Path Column** - Path column adjusts to fill remaining space
- **Navigation Consistency** - Arrow key navigation respects column configuration
- **Sort Mapping Updated** - All 11 columns can be sorted (1=Active, 2=Model, 3=Session, 4=Notes, 5=Messages, etc.)

### Changes

**Column Configuration:**
- New `Get-ColumnConfiguration()` function loads settings from JSON file
- New `Set-ColumnConfiguration()` function saves settings to JSON file
- New `Show-ColumnConfigMenu()` function provides interactive configuration UI
- Default configuration: All columns visible except Notes

**Menu Updates:**
- Added "confiG" option to main menu prompt (G key highlighted in yellow)
- confiG option only shown in main menu, not Win Terminal Config mode
- Updated menu prompt format: `...Refresh | confiG | PgUp | PgDn | eXit`

**Display Updates:**
- `Show-SessionMenu()` builds headers dynamically based on column configuration
- `Show-SessionMenu()` builds rows dynamically based on column configuration
- `Write-SingleMenuRow()` respects column configuration during arrow navigation
- Column sort mapping updated to include Notes as column 4
- All subsequent columns shifted: Messages (4→5), Created (5→6), Modified (6→7), Cost (7→8), Win Terminal (8→9), Forked From (9→10), Path (10→11)

**Technical Implementation:**
- Configuration file path: `$Global:ColumnConfigPath = "$Global:MenuPath\column-config.json"`
- Configuration structure: Hashtable with column names as keys, boolean visibility as values
- Configuration persists across program restarts automatically
- Error handling with automatic fallback to default configuration
- Added G key handler in `Get-ArrowKeyNavigation()` function
- Added ColumnConfig action handler in main loop

### Technical Details

**New Functions:**
- `Get-ColumnConfiguration()` - Lines 5512-5563: Loads configuration from JSON, returns default if missing
- `Set-ColumnConfiguration($Config)` - Lines 5565-5598: Saves configuration hashtable to JSON
- `Show-ColumnConfigMenu()` - Lines 5600-5702: Interactive menu with arrow navigation and checkboxes

**Modified Functions:**
- `Show-SessionMenu()` - Lines 1593-1600: Added notes field to row data
- `Show-SessionMenu()` - Lines 1621-1633: Updated sort column mapping to include Notes
- `Show-SessionMenu()` - Lines 1733-1828: Dynamic header building based on configuration
- `Show-SessionMenu()` - Lines 1874-1936: Dynamic row building based on configuration
- `Write-SingleMenuRow()` - Lines 2009-2068: Respects column configuration during navigation
- `Get-ArrowKeyNavigation()` - Lines 2463-2466: Added G key handler for column configuration
- Main loop - Lines 6901-6914: Added ColumnConfig action handler with reload logic

**Configuration File Format:**
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

**Menu Workflow:**
1. User presses G key in main menu
2. `Show-ColumnConfigMenu()` displays interactive menu
3. User navigates with arrow keys (yellow highlight on current item)
4. User toggles checkboxes with Space or Enter
5. User selects "Save and Exit" to save configuration
6. Menu reloads with new column layout applied
7. Configuration persists to next program start

---

## [1.8.0] - 2026-01-24

### Major Features

#### Session Notes Functionality
- **Add Notes to Sessions** - Press N key in session options menu to add/edit notes
- **Persistent Storage** - Notes stored in session-mapping.json file
- **Works with Any Session** - Add notes to both archived and active sessions
- **Current Notes Display** - Shows existing notes when adding/editing
- **Clear Notes** - Press Enter with empty input to remove notes
- **Notes Display** - Shows notes under "Session options" when viewing session details
- **Integration Ready** - Notes field available for future display enhancements

#### Menu Key Handling Improvements
- **Silent Invalid Input** - Invalid key presses no longer echo to screen
- **No Visual Feedback** - Invalid keys silently ignored without error messages
- **Valid Keys No Echo** - Valid key presses also don't echo (key-activated menus)
- **Cleaner Experience** - More professional, less intrusive user interface
- **15+ Menus Updated** - Applies to all menu functions throughout application

#### Debug Menu Enhancements
- **Simplified Toggle Text** - Changed from "Toggle - Turn Debug Off" to just "Debug Off" (when on)
- **Dynamic Text** - Shows "Debug On" when debug is off, "Debug Off" when debug is on
- **Centered Header** - "DEBUG MODE" text centered in 40-character wide separator lines
- **Hotkey Change** - Changed from T (Toggle) to D (Debug) for consistency
- **Professional Appearance** - More concise and intuitive menu layout

### Bug Fixes

#### Rename Feature Parameter Error
- **Fixed Background Generation** - Corrected function call in `Rename-ClaudeSession()`
- **Error Message** - Was: "A parameter cannot be found that matches parameter name 'ProjectPath'"
- **Root Cause** - Direct call to `New-UniformBackgroundImage` with wrong parameter name
- **Solution** - Changed to use `New-SessionBackgroundImage` wrapper function
- **Location** - Line 5804 in Claude-Menu.ps1
- **Impact** - Rename feature now correctly generates new background images
- **Related Functions** - `Rename-ClaudeSession()` now uses proper wrapper with correct parameter names

### Changes

**Notes Implementation:**
- Added `Get-SessionNotes($SessionId)` function - retrieves notes from session-mapping.json
- Added `Set-SessionNotes($SessionId, $Notes)` function - stores notes with proper property handling
- Updated `Get-ForkOrContinue()` to accept and display Notes parameter
- Added N key handler for both archived and normal session menus (lines 3490-3493, 3519-3522)
- Added notes action handler in main loop (lines 7060-7085)
- Notes displayed under "Session options" line when viewing session details
- Empty string stored if notes cleared

**Menu Echo Removal:**
- Removed all `Write-Host $choice` statements from menu functions
- Affected functions (15+ locations):
  - `Get-ForkOrContinue()` - Removed key echo for C/F/N/D/R/V/A keys
  - `Get-SessionManagementChoice()` - Removed key echo for 1/2/3/A keys
  - `Get-RegenerateImageChoice()` - Removed key echo for 1/2/3/A keys
  - `Get-ModelChoice()` - Removed key echo for 1/2/3/A keys
  - `Get-TrustedSessionChoice()` - Removed key echo for Y/N/A keys
  - Directory selection menu - Removed key echo
  - `Enable-GlobalBypassPermissions()` - Removed key echo (2 prompts)
  - `Disable-GlobalBypassPermissions()` - Removed key echo (2 prompts)
  - `Resolve-BackgroundImageConflict()` - Removed key echo
  - `Show-DebugToggle()` - Removed key echo
  - Y/N confirmation prompts (5 locations) - Removed key echo
  - Create profile prompts (2 locations) - Removed key echo
- Debug logging still captures key presses for troubleshooting

**Debug Menu Updates:**
- Menu text updated: `Debug Off | Notepad - Open Debug Log | Instructions - Show debug mode help | Abort`
- Header separator: `========================================`
- Header text: `               DEBUG MODE               ` (centered in 40 chars)
- Hotkey changed from 'T' to 'D' in switch case (line ~496)
- Toggle text simplified: removed "Toggle - Turn" prefix
- More professional and concise appearance

### Technical Details

**New Functions:**
- `Get-SessionNotes($SessionId)` - Lines 5430-5456: Returns notes string from session-mapping.json
- `Set-SessionNotes($SessionId, $Notes)` - Lines 5458-5510: Stores notes, creates entry if needed

**Modified Functions:**
- `Get-ForkOrContinue()` - Added Notes parameter (line ~3471), displays notes under session options (line ~3489)
- `Rename-ClaudeSession()` - Line 5804: Fixed to use `New-SessionBackgroundImage` instead of `New-UniformBackgroundImage`
- `Show-DebugToggle()` - Lines 481-498: Simplified toggle text, centered header, changed hotkey to D
- All menu functions - Removed key echo statements (15+ functions affected)
- Main loop - Lines 7060-7085: Added notes action handler with current notes display and save functionality

**Session Mapping Schema Update:**
- Added `notes` field to session entries in session-mapping.json
- Notes stored as string value
- Empty string when no notes set
- Property added dynamically with `Add-Member -Force` if doesn't exist
- Example entry:
```json
{
  "projectPath": "C:\\repos",
  "sessionId": "f6a0dbbf-18b7-4728-b44a-4d352a152ec1",
  "created": "2026-01-19T21:58:54.3807879-06:00",
  "wtProfileName": "Claude-DLLMonitor",
  "notes": "Trying to see when the DLLs load and the AppNameSpace"
}
```

**Notes Workflow:**
1. User selects session and presses N key in options menu
2. System retrieves current notes from session-mapping.json
3. Current notes displayed in dark gray if they exist
4. User prompted to enter new notes (or press Enter to clear)
5. Notes saved to session-mapping.json with proper property handling
6. Success message displayed in green
7. Menu returns after 1 second delay

**Key Echo Removal Rationale:**
- Key-activated menus should not echo input (consistent with terminal best practices)
- Invalid keys should be silently ignored (no visual clutter)
- Valid keys should trigger actions immediately without visual confirmation
- Debug logging preserves key press information for troubleshooting
- More professional appearance similar to commercial terminal applications

---

## [1.7.0] - 2026-01-21

### Major Features

#### Silent Invalid Input Handling
- **No Error Messages** - Invalid key presses are silently ignored
- **Cleaner Experience** - No "Invalid choice. Please enter..." messages displayed
- **Silent Waiting** - Menus simply wait for valid input without feedback
- **Reduced Clutter** - Less visual noise and interruptions

#### Single Display Menu Prompts
- **Display Once** - Menu prompts shown once before input loop, not repeatedly
- **No Redisplay** - Invalid input doesn't trigger prompt redisplay
- **Persistent Display** - Prompt remains visible on screen while waiting for input
- **Less Flashing** - Reduces screen flashing and visual clutter

#### Consolidated Single-Line Menus
- **Inline Descriptions** - All menu options with descriptions on single line
- **Eliminated Redundancy** - Removed multi-line descriptions followed by summary line
- **More Compact** - Easier to scan and understand at a glance
- **Examples:**
  - `Opus - Most capable | Sonnet - Balanced (Recommended) | Haiku - Fast | Abort`
  - `Yes - Bypass all permissions (trusted workspace) | No - Use default permission settings | Abort`
  - `Toggle - Turn Debug On/Off | Notepad - Open Debug Log | Instructions - Show debug mode help | Abort`

#### Improved Navigation Prompt
- **Arrow Symbols** - Changed from text "UP/DOWN" to actual arrow symbols ▲▼
- **Visual Enhancement** - Arrows displayed in yellow for easy identification
- **New Format** - `Choose with ▲▼, then [Enter] to select`
- **Consistent Colors** - Both arrows and [Enter] in yellow

#### Directory Path Inline Display
- **Path in Menu** - Shows actual path: `Use Current - C:\repos\Fork | Set different directory | Abort`
- **Removed Redundancy** - No separate "Current directory: C:\repos\Fork" line above menu
- **More Compact** - Single-line presentation with all information

#### Win Terminal Config Menu Consistency
- **Abort Instead of Exit** - Changed "eXit" to "Abort" for consistency
- **Key Reassignment** - Changed "All Sessions" from 'A' to 'L' key
- **Consistent Terminology** - All menus now use "Abort" for cancellation

### Bug Fixes

#### Fixed Cursor Jumping During Workflows
- **Removed Cursor Positioning** - Eliminated cursor positioning code from all dialog functions
- **Natural Flow** - Dialogs now flow naturally down the screen during workflows
- **Fixed Model Selection** - Model selection no longer appears above name entry during new session creation
- **10 Functions Fixed:**
  - Get-ModelChoice
  - Get-TrustedSessionChoice
  - Get-ForkOrContinue
  - Get-SessionManagementChoice
  - Get-RegenerateImageChoice
  - Show-DebugToggle
  - Show-CostAnalysis
  - Enable-GlobalBypassPermissions
  - Disable-GlobalBypassPermissions
  - Start-NewSession

### Changes

**Menu Format:**
- Converted 8 menus from multi-line to single-line format
- Removed all trailing colons after "Abort"
- All menu options include descriptions inline

**Input Handling:**
- Removed all "Invalid choice" error messages
- Removed sleep delays after invalid input
- Default switch cases now silently continue loop
- Win Terminal Config 'A' key triggers Abort
- Win Terminal Config 'L' key triggers "aLl Sessions"

**Navigation:**
- Arrow symbols use `[char]0x25B2` (▲) and `[char]0x25BC` (▼)
- Changed from Cyan UP/DOWN to Yellow ▲▼
- Changed [Enter] from Green to Yellow
- Updated in 3 menu contexts (Main Menu normal, Main Menu with unnamed, Win Terminal Config)

**Technical:**
- Cursor positioning code removed from 10 dialog functions
- `$Global:PromptEndY` no longer used by dialog functions for positioning

---

## [1.6.0] - 2026-01-21

### Major Features

#### Uniform Menu System
- **Consistent Format** - All menus use consistent prompt format with highlighted key letters in yellow
- **Single-Keypress Input** - No Enter key needed throughout menus
- **13+ Menus Updated** - Debug, Session Management, Model Selection, Permission Modes, Confirmations, etc.
- **Example Format** - `Continue | Fork | Delete | Rename | Abort` (keys in yellow)

#### Universal Escape Key Support
- **Esc Key Works Everywhere** - Works as Abort/Cancel/No in all menus
- **Silent Feature** - Not advertised in prompts but always available
- **Consistent Behavior** - Esc = back one level throughout entire application

#### Unified Background Image Generation
- **Single Function** - `New-UniformBackgroundImage()` replaces three separate implementations
- **Consistent 6-Line Format:**
  1. Session Name (48pt bold)
  2. "Forked from: [parent]" (32pt italic, optional)
  3. COMPUTER:USERNAME (32pt italic)
  4. "branch: [branch]" (32pt italic, optional)
  5. "model: [model]" (32pt italic, optional)
  6. Full directory path (32pt italic)
- **Consistent Styling** - 1920x1080 PNG, semi-transparent dark blue background (ARGB: 180,20,20,40)

#### Fixed "Last Command" Display Clearing
- **Correct Cursor Position** - Captured BEFORE "Last command" display (not after)
- **Proper Clearing** - Menu actions properly clear the command display and reposition cursor
- **ANSI Escape Sequence** - Uses `[0J` to clear from cursor down
- **Clean Dialogs** - Dialogs appear immediately below sub-menu without blank space

### Bug Fixes

#### Unnamed Session Launch Fixed
- **Windows Terminal Launch** - Unnamed sessions now launch in Windows Terminal (not broken inline mode)
- **Command Changed** - From `Start-Process -NoNewWindow -Wait` to `wt.exe -d "$dir" -- "$claudePath" --resume $sessionId`
- **7 Locations Fixed** - All session launch points updated
- **Sessions Work** - Sessions without profiles now work correctly

### Changes

**Menu Prompts:**
- All menus converted to single-keypress with highlighted keys
- Replaced `Read-Host` with `$host.UI.RawUI.ReadKey()`
- Added Esc key handling (virtual key code 27)
- Key echo displays immediately after press

**Background Images:**
- Created wrapper functions calling unified core
- All wrappers pass ProjectPath parameter for Line 6 display

**Last Command Fix:**
- `$Global:PromptEndY` captured at correct position
- Clearing code in `Get-ArrowKeyNavigation`
- Removed cursor positioning from individual dialog functions

---

## [1.5.0] - 2026-01-21

### Major Features

#### Dynamic Menu Pagination
- **Screen-Aware Height Calculation** - Menu automatically adjusts to terminal height with 5-line buffer below sub-menu
- **Page Navigation** - Navigate large session lists with PgUp/PgDn keys
- **Page Indicator** - Shows "pg 1/x" in top-right corner when multiple pages exist
- **Automatic Pagination** - Calculates available rows: window height - 17 (title, headers, borders, prompts, buffer)
- **Smart Page Resets** - Returns to page 1 when changing sort order

#### Session Rename Feature
- **Rename Sessions** - Press **[M]** to rename any session directly from the main menu
- **Complete Updates** - Renames in all locations:
  - Claude's `sessions-index.json` (updates `customTitle`)
  - Windows Terminal profile name (from `Claude-OldName` to `Claude-NewName`)
  - Session mapping file (updates `wtProfileName` and adds `updated` timestamp)
- **Simple Workflow** - Enter new name or press Enter to cancel
- **Character Sanitization** - Automatically replaces invalid filesystem characters
- **Instant Refresh** - Menu updates immediately to show new name

#### Tracked Name Recognition
- **Bracket Sessions Fixed** - Sessions shown in `[brackets]` (tracked names) now properly recognized
- **Profile Detection** - Correctly finds Windows Terminal profiles for sessions with tracked names
- **No Duplicate Prompts** - Sessions like `[Random]` no longer ask to create profiles if they already have them
- **Display Name Priority** - Uses `customTitle` → `trackedName` → `sessionId` throughout the application
- **Fork Support** - Properly displays tracked names when forking sessions

#### Simplified Mode Switching
- **Clean Prompts** - Quiet/Chatty mode switching now shows simple 3-option prompt:
  - **[Y]** Enable mode directly
  - **[I]** Show detailed information before proceeding
  - **[N]** Cancel operation
- **Hide Information** - All detailed explanations hidden until user presses [I]
- **Faster Workflow** - Common case (just switching modes) takes one keypress

### Changes

**Navigation:**
- Added PgUp/PgDn key handlers (virtual key codes 33 and 34)
- Sub-menu shows "PgUp | PgDn" options when multiple pages exist
- Menu displays current page slice while maintaining full sort across all data

**Session Rename (M key):**
- Added `Rename-ClaudeSession()` function with complete metadata updates
- Integrated into main loop with automatic menu refresh
- Added "renaMe" to all three sub-menu prompt variations

**Tracked Name Support:**
- Modified `Start-ContinueSession()` to check both `customTitle` and `trackedName`
- Updated `Show-SessionMenu()` to pass tracked names to `Get-WTProfileName()`
- Fixed `Start-ForkSession()` to display tracked names correctly
- Enhanced display name resolution in 4+ locations

**Mode Switching:**
- Simplified `Enable-GlobalBypassPermissions()` with [Y/I/N] prompt
- Simplified `Disable-GlobalBypassPermissions()` with [Y/I/N] prompt
- Detailed information only shown when user requests it with [I]

### Technical Details

**New Functions:**
- `Rename-ClaudeSession()` - Handles complete session rename workflow with all updates

**Modified Functions:**
- `Show-SessionMenu()` - Added pagination logic with page calculation and row slicing
- `Get-ArrowKeyNavigation()` - Added PgUp/PgDn handlers, added `$TotalPages` parameter
- `Start-ContinueSession()` - Checks both `customTitle` and `trackedName` for named sessions
- `Start-ForkSession()` - Enhanced display name resolution with tracked names
- `Enable-GlobalBypassPermissions()` - Redesigned with [Y/I/N] prompt structure
- `Disable-GlobalBypassPermissions()` - Redesigned with [Y/I/N] prompt structure
- Main loop - Added PageUp/PageDown/Rename handlers

**New Global Variables:**
- `$Global:CurrentPage` - Tracks current page for pagination

**Pagination Logic:**
1. Calculate available rows based on window height
2. Determine if pagination needed (total rows > available rows)
3. Calculate total pages and validate current page
4. Slice sorted data for current page display
5. Show page indicator when multiple pages exist
6. Reset to page 1 on sort changes

**Return Values Enhanced:**
- `Show-SessionMenu()` now returns `TotalPages`, `CurrentPage`, and `AllRows`
- Enables main loop to handle pagination without reloading sessions

### Bug Fixes

- Fixed sessions with tracked names asking to create profiles they already have
- Fixed display name inconsistencies across continue/fork workflows
- Fixed mode switching headers (now say "ENABLING" instead of "YOU ARE IN")

---

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
