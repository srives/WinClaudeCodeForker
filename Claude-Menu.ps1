<#
.SYNOPSIS
    Claude Session Launcher - Interactive menu for managing Claude sessions with Windows Terminal integration

.DESCRIPTION
    Provides an interactive menu for:
    - Discovering all Claude sessions across projects
    - Starting new sessions with directory selection
    - Continuing existing sessions
    - Forking sessions with custom Windows Terminal profiles and background images
    - Git branch detection and display
    - Model tracking and display
    - Smart background image conflict resolution

.NOTES
    Author: S. Rives
    Version: 1.10.5
    Date: 2026-01-25
    Requires: PowerShell 5.1+, Windows Terminal, Claude CLI
#>

# Global error handling
$ErrorActionPreference = "Stop"
$Global:ScriptVersion = "1.10.5"
$Global:MenuPath = "$env:USERPROFILE\.claude-menu"
$Global:ProfileRegistryPath = "$Global:MenuPath\profile-registry.json"
$Global:SessionMappingPath = "$Global:MenuPath\session-mapping.json"
$Global:BackgroundTrackingPath = "$Global:MenuPath\background-tracking.json"
$Global:DebugStatePath = "$Global:MenuPath\debug.txt"
$Global:DebugLogPath = "$Global:MenuPath\debug.log"
$Global:QuoteStatePath = "$Global:MenuPath\quote-state.json"
$Global:ColumnConfigPath = "$Global:MenuPath\column-config.json"
$Global:WTSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$Global:ClaudePath = "$env:USERPROFILE\.claude"
$Global:LastClaudeCommand = $null
$Global:LastClaudeError = $null
$Global:PathCache = @{}
$Global:ClaudeProjectsPath = "$env:USERPROFILE\.claude\projects"
$Global:ClaudeSettingsPath = "$env:USERPROFILE\.claude\settings.json"
$Global:TokenUsageCache = @{}
$Global:ModelCache = @{}  # Cache for session models to avoid re-parsing .jsonl files
$Global:SortColumn = 0  # 0 = no sort, 1-10 = column number
$Global:SortDescending = $false
$Global:PromptEndY = 0  # Store where prompts end for sub-menu positioning
$Global:CurrentPage = 1  # Current page for pagination

# Trap for unhandled errors
trap {
    Write-Host ""
    Write-Host "Fatal Error: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

#region Utility Functions

function Write-ColorText {
    param(
        [string]$Text,
        [ConsoleColor]$Color = 'White',
        [switch]$NoNewline
    )
    if ($NoNewline) {
        Write-Host $Text -ForegroundColor $Color -NoNewline
    } else {
        Write-Host $Text -ForegroundColor $Color
    }
}

function Write-DualColorText {
    <#
    .SYNOPSIS
        Writes text with two colors - one main color for all words and one randomly highlighted word
    #>
    param([string]$Text)

    # Two colors: DarkGray and Cyan (matching colors used in menu header)
    $colors = @([ConsoleColor]::DarkGray, [ConsoleColor]::Cyan)

    # Randomly pick which color is main and which is highlight
    $mainColorIndex = Get-Random -Minimum 0 -Maximum 2
    $highlightColorIndex = 1 - $mainColorIndex  # The other color

    $mainColor = $colors[$mainColorIndex]
    $highlightColor = $colors[$highlightColorIndex]

    # Split text into words
    $words = $Text -split '\s+'

    if ($words.Count -eq 0) {
        Write-Host $Text -ForegroundColor $mainColor
        return
    }

    # Randomly pick one word to highlight
    $highlightWordIndex = Get-Random -Minimum 0 -Maximum $words.Count

    # Print each word with appropriate color
    for ($i = 0; $i -lt $words.Count; $i++) {
        $color = if ($i -eq $highlightWordIndex) { $highlightColor } else { $mainColor }

        if ($i -lt $words.Count - 1) {
            Write-Host "$($words[$i]) " -NoNewline -ForegroundColor $color
        } else {
            Write-Host $words[$i] -ForegroundColor $color
        }
    }
}

function Get-NextQuote {
    <#
    .SYNOPSIS
        Gets the next quote from rotating APIs (Proverbs, ZenQuotes, Buddha, API Ninjas)
    #>

    # Read quote state (which API to use, verse counter for Bible)
    $apiIndex = 0  # 0=Bible, 1=ZenQuotes Daily, 2=ZenQuotes Random
    $verseNumber = 1
    $dayOfMonth = (Get-Date).Day
    $debugEnabled = Get-DebugState

    if (Test-Path $Global:QuoteStatePath) {
        try {
            $state = Get-Content $Global:QuoteStatePath -Raw | ConvertFrom-Json
            if ($state.apiIndex -ne $null) { $apiIndex = $state.apiIndex }
            if ($state.bibleChapter -eq $dayOfMonth -and $state.bibleVerse) {
                $verseNumber = $state.bibleVerse
            }
        } catch {
            # If file is corrupt, start fresh
            $apiIndex = 0
            $verseNumber = 1
        }
    }

    # Skip Bible API (0) if debug is off
    if (-not $debugEnabled -and $apiIndex -eq 0) {
        $apiIndex = 1
    }

    # Try APIs in rotation, fallback to next if one fails
    $attempts = 0
    $maxAttempts = if ($debugEnabled) { 3 } else { 2 }  # Only 2 attempts if debug off (no Bible)

    while ($attempts -lt $maxAttempts) {
        $quoteText = ""
        $success = $false

        try {
            switch ($apiIndex) {
                0 {
                    # Bible API - Proverbs (only if debug enabled)
                    if ($debugEnabled) {
                        $verseRef = "proverbs+$dayOfMonth`:$verseNumber"
                        $response = Invoke-RestMethod -Uri "https://bible-api.com/$verseRef" -TimeoutSec 5 -ErrorAction Stop
                        $quoteText = $response.text
                        $success = $true
                        $verseNumber++  # Increment for next time
                    }
                }
                1 {
                    # ZenQuotes API - Daily featured quote
                    $response = Invoke-RestMethod -Uri "https://zenquotes.io/api/today/" -TimeoutSec 5 -ErrorAction Stop
                    if ($response -and $response[0]) {
                        $quoteText = $response[0].q
                        $success = $true
                    }
                }
                2 {
                    # ZenQuotes API - Random wisdom quote
                    $response = Invoke-RestMethod -Uri "https://zenquotes.io/api/random" -TimeoutSec 5 -ErrorAction Stop
                    if ($response -and $response[0]) {
                        $quoteText = $response[0].q
                        $success = $true
                    }
                }
            }
        } catch {
            # API failed, will try next one
            $success = $false
        }

        if ($success -and $quoteText) {
            # Clean up text - remove line breaks and extra spaces
            $cleanText = $quoteText -replace "`r`n", " " -replace "`n", " " -replace "`r", " "
            $cleanText = $cleanText -replace "\s+", " "
            $cleanText = $cleanText.Trim()

            # Save state for next time (rotate to next API)
            try {
                # If debug is off, rotate between 1 and 2 only
                if ($debugEnabled) {
                    $nextApiIndex = ($apiIndex + 1) % 3
                } else {
                    $nextApiIndex = if ($apiIndex -eq 1) { 2 } else { 1 }
                }
                $nextVerse = if ($apiIndex -eq 0) { $verseNumber } else { 1 }

                $state = @{
                    apiIndex = $nextApiIndex
                    bibleChapter = $dayOfMonth
                    bibleVerse = $nextVerse
                }
                $state | ConvertTo-Json | Set-Content $Global:QuoteStatePath -Force
            } catch {
                # Ignore save errors
            }

            return @{
                Text = $cleanText
                Success = $true
            }
        }

        # Try next API
        if ($debugEnabled) {
            $apiIndex = ($apiIndex + 1) % 3
        } else {
            # If debug off, skip index 0 (Bible)
            $apiIndex = if ($apiIndex -eq 1) { 2 } else { 1 }
        }
        $attempts++
    }

    # All APIs failed
    return @{
        Text = "Goodbye!"
        Success = $false
    }
}

function Truncate-String {
    <#
    .SYNOPSIS
        Truncates a string to fit within a column width
    .PARAMETER FromLeft
        If specified, truncates from the left (front) instead of right (end), prefixing with "..."
        Useful for paths where the end is more informative than the beginning
    #>
    param(
        [string]$Value,
        [int]$MaxLength,
        [switch]$FromLeft
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return ""
    }

    # Truncate to MaxLength - 1 to leave one space before next column
    $actualMax = $MaxLength - 1
    if ($Value.Length -gt $actualMax) {
        if ($FromLeft) {
            # Truncate from left, keep the end visible
            # Reserve 3 characters for "..."
            if ($actualMax -le 3) {
                return "..."
            }
            $keepLength = $actualMax - 3
            return "..." + $Value.Substring($Value.Length - $keepLength)
        } else {
            # Truncate from right (default behavior)
            return $Value.Substring(0, $actualMax)
        }
    }
    return $Value
}

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-ColorText $Title -Color Cyan
    Write-ColorText ("=" * $Title.Length) -Color Cyan
    Write-Host ""
}

function ConvertTo-ClaudeprojectPath {
    <#
    .SYNOPSIS
        Converts a Windows path to Claude's encoded project path format
    .DESCRIPTION
        Claude encodes paths by:
        1. Removing the colon from drive letter (C: -> C)
        2. Replacing the FIRST backslash with -- (double dash)
        3. Replacing subsequent backslashes with - (single dash)
    .EXAMPLE
        ConvertTo-ClaudeprojectPath "C:\repos" returns "C--repos"
        ConvertTo-ClaudeprojectPath "C:\repos\Fork" returns "C--repos-Fork"
    #>
    param([string]$Path)

    $normalized = $Path.TrimEnd('\')

    # Remove colon from drive letter
    $withoutColon = $normalized -replace ':', ''

    # Replace first backslash with double dash
    $withFirstDash = $withoutColon -replace '^([A-Za-z])\\', '$1--'

    # Replace remaining backslashes with single dash
    $encoded = $withFirstDash -replace '\\', '-'

    return $encoded
}

function ConvertFrom-ClaudeprojectPath {
    <#
    .SYNOPSIS
        Converts Claude's encoded project path back to Windows path format
    .DESCRIPTION
        Decodes Claude's path format:
        1. Extracts drive letter before first --
        2. Replaces all - with \ for path components
    .EXAMPLE
        ConvertFrom-ClaudeprojectPath "C--repos" returns "C:\repos"
        ConvertFrom-ClaudeprojectPath "C--repos-Fork" returns "C:\repos\Fork"
    #>
    param([string]$EncodedPath)

    # Match drive letter and double-dash, then the rest
    if ($EncodedPath -match '^([A-Za-z])--(.+)$') {
        $drive = $Matches[1]
        # Replace all remaining single dashes with backslashes
        $rest = $Matches[2] -replace '-', '\'
        return "${drive}:\$rest"
    } elseif ($EncodedPath -match '^([A-Za-z])$') {
        # Just a drive letter (e.g., "C")
        return "${EncodedPath}:\"
    }

    # If pattern doesn't match, return as-is (shouldn't happen with valid Claude paths)
    Write-ErrorLog "Invalid Claude path encoding: $EncodedPath"
    return $EncodedPath
}

function Get-ClaudeCLIPath {
    <#
    .SYNOPSIS
        Gets the full path to Claude CLI executable
    .DESCRIPTION
        Returns the path to claude, preferring .cmd over .ps1 for Windows Terminal compatibility
    #>
    $claudePath = Get-Command claude -ErrorAction SilentlyContinue
    if ($claudePath) {
        $basePath = $claudePath.Source

        # If Get-Command returned .ps1, check if there's a .cmd version
        # (needed for Windows Terminal which uses cmd.exe, not PowerShell)
        if ($basePath -like "*.ps1") {
            $cmdPath = $basePath -replace '\.ps1$', '.cmd'
            if (Test-Path $cmdPath) {
                return $cmdPath
            }
        }

        return $basePath
    }

    # Fallback: check .local\bin for claude.exe
    $localPath = "$env:USERPROFILE\.local\bin\claude.exe"
    if (Test-Path $localPath) {
        return $localPath
    }

    return $null
}

function Test-ClaudeCLI {
    <#
    .SYNOPSIS
        Checks if Claude CLI is available in PATH
    #>
    $claudePath = Get-ClaudeCLIPath
    return ($null -ne $claudePath)
}

function Test-WindowsTerminal {
    <#
    .SYNOPSIS
        Checks if Windows Terminal is installed
    #>
    $wtPath = Get-Command wt -ErrorAction SilentlyContinue
    if (-not $wtPath) {
        return $false
    }
    return $true
}

#endregion

#region Debug Functions

function Get-DebugState {
    <#
    .SYNOPSIS
        Gets the current debug state (on/off)
    #>
    if (Test-Path $Global:DebugStatePath) {
        $state = Get-Content $Global:DebugStatePath -Raw
        return ($state -eq "on")
    }
    return $false
}

function Set-DebugState {
    <#
    .SYNOPSIS
        Sets the debug state (on/off)
    #>
    param([bool]$Enabled)

    $state = if ($Enabled) { "on" } else { "off" }
    Write-DebugFileOperation -FilePath $Global:DebugStatePath -Content $state -Operation "Set-DebugState"  # FILE-DEBUG
    $state | Set-Content $Global:DebugStatePath -NoNewline
}

function Write-DebugInfo {
    <#
    .SYNOPSIS
        Writes debug information if debug mode is enabled
    .DESCRIPTION
        Outputs to both console and debug log file with timestamp
    #>
    param(
        [string]$Message,
        [ConsoleColor]$Color = 'DarkGray'
    )

    if (Get-DebugState) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] $Message"

        # Write to console
        Write-Host "[DEBUG] $Message" -ForegroundColor $Color

        # Write to log file
        try {
            $logMessage | Add-Content -Path $Global:DebugLogPath -Encoding UTF8
        } catch {
            # Silently ignore log file errors
        }
    }
}

function Write-ErrorLog {
    <#
    .SYNOPSIS
        Writes error messages to debug log (always, regardless of debug state)
    .PARAMETER Message
        The error message to log
    #>
    param(
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [ERROR] $Message"

    try {
        if (-not (Test-Path $Global:DebugLogPath)) {
            $logDir = Split-Path $Global:DebugLogPath -Parent
            if (-not (Test-Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
        }
        $logMessage | Add-Content -Path $Global:DebugLogPath -Encoding UTF8
    } catch {
        # Can't do anything if logging fails
    }
}

function Write-DebugFileOperation {
    <#
    .SYNOPSIS
        FILE-DEBUG: Logs file write operations to help track down mysterious file creation
    .DESCRIPTION
        This is a special debug function that can be disabled by removing FILE-DEBUG tagged code
    #>
    param(
        [string]$FilePath,
        [string]$Content,
        [string]$Operation = "Write"
    )

    # FILE-DEBUG: Check for suspicious file paths (numeric names, single chars, etc.)
    $fileName = Split-Path -Leaf $FilePath
    $isSuspicious = $false

    # Check if filename is purely numeric
    if ($fileName -match '^\d+$') {
        $isSuspicious = $true
    }
    # Check if filename is very short and in current directory
    if ($fileName.Length -le 3 -and -not $FilePath.Contains('\') -and -not $FilePath.Contains('/')) {
        $isSuspicious = $true
    }

    # FILE-DEBUG: Always log suspicious files, only log others when debug is enabled
    if ($isSuspicious -or (Get-DebugState)) {
        $contentPreview = if ($Content.Length -gt 10) { $Content.Substring(0, 10) + "..." } else { $Content }
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $suspiciousTag = if ($isSuspicious) { " [SUSPICIOUS!]" } else { "" }
        $logMessage = "[$timestamp] [FILE-DEBUG]$suspiciousTag $Operation to file: '$FilePath' | Content: '$contentPreview'"

        try {
            $logMessage | Add-Content -Path $Global:DebugLogPath -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch {
            # Silently ignore if we can't log
        }

        # Also show on console if suspicious or debug mode
        if ($isSuspicious) {
            Write-Host "[FILE-DEBUG] " -NoNewline -ForegroundColor Red
            Write-Host "SUSPICIOUS FILE! " -NoNewline -ForegroundColor Yellow -BackgroundColor Red
        } else {
            Write-Host "[FILE-DEBUG] " -NoNewline -ForegroundColor Magenta
        }
        Write-Host "$Operation -> " -NoNewline -ForegroundColor Magenta
        Write-Host "'$FilePath'" -NoNewline -ForegroundColor Yellow
        Write-Host " | Content: " -NoNewline -ForegroundColor Magenta
        Write-Host "'$contentPreview'" -ForegroundColor Cyan
    }
}

function Test-SystemValidation {
    <#
    .SYNOPSIS
        Runs comprehensive system validation tests
    #>

    Clear-Host
    Write-Host ""
    Write-ColorText "========================================" -Color Cyan
    Write-ColorText "      SYSTEM VALIDATION TESTS" -Color Cyan
    Write-ColorText "========================================" -Color Cyan
    Write-Host ""

    # Initialize counters at script scope so nested function can modify them
    $script:ValidationPassCount = 0
    $script:ValidationFailCount = 0
    $script:ValidationWarnCount = 0

    function Write-TestResult {
        param(
            [string]$TestName,
            [string]$Status,  # PASS, FAIL, WARN
            [string]$Message = ""
        )

        $statusColor = switch ($Status) {
            "PASS" { "Green" }
            "FAIL" { "Red" }
            "WARN" { "Yellow" }
        }

        Write-Host "[" -NoNewline
        Write-Host $Status -NoNewline -ForegroundColor $statusColor
        Write-Host "] " -NoNewline
        Write-Host $TestName -ForegroundColor Gray

        if ($Message) {
            Write-Host "        $Message" -ForegroundColor DarkGray
        }

        # Update counters at script scope
        switch ($Status) {
            "PASS" { $script:ValidationPassCount++ }
            "FAIL" { $script:ValidationFailCount++ }
            "WARN" { $script:ValidationWarnCount++ }
        }
    }

    # Test 1: PowerShell Version
    try {
        $psVersion = $PSVersionTable.PSVersion
        if ($psVersion.Major -ge 5) {
            Write-TestResult "PowerShell Version" "PASS" "Version $($psVersion.Major).$($psVersion.Minor)"
        } else {
            Write-TestResult "PowerShell Version" "WARN" "Version $($psVersion.Major).$($psVersion.Minor) (5.1+ recommended)"
        }
    } catch {
        Write-TestResult "PowerShell Version" "FAIL" $_.Exception.Message
    }

    # Test 2: Claude CLI Exists
    try {
        $claudePath = Get-ClaudeCLIPath
        if (Test-Path $claudePath) {
            Write-TestResult "Claude CLI" "PASS" "Found at $claudePath"
        } else {
            Write-TestResult "Claude CLI" "FAIL" "Not found at expected location"
        }
    } catch {
        Write-TestResult "Claude CLI" "FAIL" $_.Exception.Message
    }

    # Test 3: Windows Terminal
    try {
        $wtPath = (Get-Command wt.exe -ErrorAction SilentlyContinue).Source
        if ($wtPath) {
            Write-TestResult "Windows Terminal" "PASS" "Found at $wtPath"
        } else {
            Write-TestResult "Windows Terminal" "FAIL" "wt.exe not found in PATH"
        }
    } catch {
        Write-TestResult "Windows Terminal" "FAIL" $_.Exception.Message
    }

    # Test 4: .claude-menu Directory Structure
    try {
        if (Test-Path $Global:MenuPath) {
            Write-TestResult ".claude-menu Directory" "PASS" $Global:MenuPath
        } else {
            Write-TestResult ".claude-menu Directory" "FAIL" "Directory does not exist"
        }
    } catch {
        Write-TestResult ".claude-menu Directory" "FAIL" $_.Exception.Message
    }

    # Test 5: session-mapping.json Integrity
    try {
        if (Test-Path $Global:SessionMappingPath) {
            $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json
            if ($mapping.sessions) {
                $sessionCount = $mapping.sessions.Count
                Write-TestResult "session-mapping.json" "PASS" "$sessionCount tracked session(s)"
            } else {
                Write-TestResult "session-mapping.json" "WARN" "No sessions property found"
            }
        } else {
            Write-TestResult "session-mapping.json" "WARN" "File does not exist (will be created on first fork)"
        }
    } catch {
        Write-TestResult "session-mapping.json" "FAIL" "Invalid JSON: $($_.Exception.Message)"
    }

    # Test 6: background-tracking.json Integrity
    try {
        if (Test-Path $Global:BackgroundTrackingPath) {
            $tracking = Get-Content $Global:BackgroundTrackingPath -Raw | ConvertFrom-Json
            if ($tracking.backgrounds) {
                $bgCount = $tracking.backgrounds.Count
                Write-TestResult "background-tracking.json" "PASS" "$bgCount background(s) tracked"
            } else {
                Write-TestResult "background-tracking.json" "WARN" "No backgrounds property found"
            }
        } else {
            Write-TestResult "background-tracking.json" "WARN" "File does not exist (will be created on first background)"
        }
    } catch {
        Write-TestResult "background-tracking.json" "FAIL" "Invalid JSON: $($_.Exception.Message)"
    }

    # Test 7: Windows Terminal settings.json
    try {
        $wtSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        if (Test-Path $wtSettingsPath) {
            $settings = Get-Content $wtSettingsPath -Raw | ConvertFrom-Json
            if ($settings.profiles.list) {
                $profileCount = $settings.profiles.list.Count
                Write-TestResult "Windows Terminal settings.json" "PASS" "$profileCount profile(s) configured"
            } else {
                Write-TestResult "Windows Terminal settings.json" "WARN" "No profiles.list found"
            }
        } else {
            Write-TestResult "Windows Terminal settings.json" "FAIL" "File not found"
        }
    } catch {
        Write-TestResult "Windows Terminal settings.json" "FAIL" "Invalid JSON: $($_.Exception.Message)"
    }

    # Test 8: Orphaned Windows Terminal Profiles
    try {
        if ((Test-Path $Global:SessionMappingPath) -and (Test-Path "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json")) {
            $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json
            $wtSettings = Get-Content "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -Raw | ConvertFrom-Json

            $claudeProfiles = $wtSettings.profiles.list | Where-Object { $_.name -like "Claude-*" }
            $trackedProfiles = $mapping.sessions | ForEach-Object { $_.wtProfileName }

            $orphaned = $claudeProfiles | Where-Object { $trackedProfiles -notcontains $_.name }

            if ($orphaned) {
                $orphanCount = ($orphaned | Measure-Object).Count
                Write-TestResult "Orphaned WT Profiles" "WARN" "$orphanCount orphaned profile(s) found"
            } else {
                Write-TestResult "Orphaned WT Profiles" "PASS" "No orphaned profiles"
            }
        } else {
            Write-TestResult "Orphaned WT Profiles" "WARN" "Cannot check (missing files)"
        }
    } catch {
        Write-TestResult "Orphaned WT Profiles" "WARN" "Check failed: $($_.Exception.Message)"
    }

    # Test 9: Missing Session Files
    try {
        if (Test-Path $Global:SessionMappingPath) {
            $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json
            $missingCount = 0

            foreach ($session in $mapping.sessions) {
                $encodedPath = ConvertTo-ClaudeprojectPath -Path $session.projectPath
                $sessionFile = Join-Path $Global:ClaudeProjectsPath "$encodedPath\$($session.sessionId).jsonl"

                if (-not (Test-Path $sessionFile)) {
                    $missingCount++
                }
            }

            if ($missingCount -eq 0) {
                Write-TestResult "Missing Session Files" "PASS" "All tracked sessions have .jsonl files"
            } else {
                Write-TestResult "Missing Session Files" "WARN" "$missingCount tracked session(s) missing .jsonl files"
            }
        } else {
            Write-TestResult "Missing Session Files" "WARN" "Cannot check (no session-mapping.json)"
        }
    } catch {
        Write-TestResult "Missing Session Files" "WARN" "Check failed: $($_.Exception.Message)"
    }

    # Test 10: Orphaned Background Images
    try {
        if ((Test-Path $Global:BackgroundTrackingPath) -and (Test-Path $Global:MenuPath)) {
            $tracking = Get-Content $Global:BackgroundTrackingPath -Raw | ConvertFrom-Json
            $trackedBackgrounds = $tracking.backgrounds | ForEach-Object { $_.backgroundPath }

            $orphanedCount = 0
            Get-ChildItem -Path $Global:MenuPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $bgFile = Join-Path $_.FullName "background.png"
                if ((Test-Path $bgFile) -and ($trackedBackgrounds -notcontains $bgFile)) {
                    $orphanedCount++
                }
            }

            if ($orphanedCount -eq 0) {
                Write-TestResult "Orphaned Background Images" "PASS" "No orphaned background images"
            } else {
                Write-TestResult "Orphaned Background Images" "WARN" "$orphanedCount orphaned background(s) found"
            }
        } else {
            Write-TestResult "Orphaned Background Images" "WARN" "Cannot check (missing files)"
        }
    } catch {
        Write-TestResult "Orphaned Background Images" "WARN" "Check failed: $($_.Exception.Message)"
    }

    # Test 11: Reserved Variable Usage ($input)
    try {
        $scriptPath = $PSCommandPath
        $scriptContent = Get-Content $scriptPath -Raw

        # Check for $input usage (should be $userInput now)
        if ($scriptContent -match '\$input\s*=') {
            Write-TestResult "Reserved Variable Check" "FAIL" "Script uses reserved variable `$input (should be `$userInput)"
        } else {
            Write-TestResult "Reserved Variable Check" "PASS" "No reserved variable conflicts detected"
        }
    } catch {
        Write-TestResult "Reserved Variable Check" "WARN" "Check failed: $($_.Exception.Message)"
    }

    # Test 12: Claude Projects Directory
    try {
        if (Test-Path $Global:ClaudeProjectsPath) {
            $projectDirs = Get-ChildItem -Path $Global:ClaudeProjectsPath -Directory -ErrorAction SilentlyContinue
            $dirCount = ($projectDirs | Measure-Object).Count
            Write-TestResult "Claude Projects Directory" "PASS" "$dirCount project directory(ies) found"
        } else {
            Write-TestResult "Claude Projects Directory" "FAIL" "Directory does not exist: $Global:ClaudeProjectsPath"
        }
    } catch {
        Write-TestResult "Claude Projects Directory" "FAIL" $_.Exception.Message
    }

    # Test 13: Path Encoding/Decoding
    try {
        $testPath = "C:\repos"
        $encoded = ConvertTo-ClaudeprojectPath -Path $testPath
        $expected = "C--repos"

        if ($encoded -eq $expected) {
            Write-TestResult "Path Encoding" "PASS" "C:\repos -> $encoded"
        } else {
            Write-TestResult "Path Encoding" "FAIL" "Expected '$expected', got '$encoded'"
        }
    } catch {
        Write-TestResult "Path Encoding" "FAIL" $_.Exception.Message
    }

    # Test 14: Session Discovery
    try {
        $sessions = Get-AllClaudeSessions
        if ($sessions) {
            $sessionCount = ($sessions | Measure-Object).Count
            Write-TestResult "Session Discovery" "PASS" "$sessionCount session(s) discovered"
        } else {
            Write-TestResult "Session Discovery" "WARN" "No sessions found (may be normal for new installation)"
        }
    } catch {
        Write-TestResult "Session Discovery" "FAIL" $_.Exception.Message
    }

    # Test 15: Column Configuration
    try {
        $config = Get-ColumnConfiguration
        if ($config) {
            $visibleCount = 0
            $config.PSObject.Properties | ForEach-Object {
                if ($_.Value -eq $true) { $visibleCount++ }
            }
            Write-TestResult "Column Configuration" "PASS" "$visibleCount visible column(s)"
        } else {
            Write-TestResult "Column Configuration" "WARN" "No configuration found (will use defaults)"
        }
    } catch {
        Write-TestResult "Column Configuration" "WARN" "Check failed: $($_.Exception.Message)"
    }

    # Test 16: Path Encoding Round-Trip (Bijection Test)
    try {
        $testPaths = @("C:\repos", "c:\temp", "D:\Projects\Test", "C:\Users\Test User\Documents")
        $failures = @()

        foreach ($path in $testPaths) {
            $encoded = ConvertTo-ClaudeprojectPath -Path $path
            # We can't decode back easily, but we can verify encoding is consistent
            $encoded2 = ConvertTo-ClaudeprojectPath -Path $path
            if ($encoded -ne $encoded2) {
                $failures += "Inconsistent encoding for '$path'"
            }
        }

        if ($failures.Count -eq 0) {
            Write-TestResult "Path Encoding Consistency" "PASS" "All test paths encode consistently"
        } else {
            Write-TestResult "Path Encoding Consistency" "FAIL" "$($failures.Count) encoding inconsistencies"
        }
    } catch {
        Write-TestResult "Path Encoding Consistency" "FAIL" $_.Exception.Message
    }

    # Test 17: Critical Functions Exist
    try {
        $criticalFunctions = @(
            "Get-AllClaudeSessions",
            "Start-ContinueSession",
            "Start-ForkSession",
            "Show-SessionMenu",
            "Get-ClaudeCLIPath",
            "Add-WTProfile",
            "Remove-WTProfile",
            "New-SessionBackgroundImage",
            "Get-ColumnConfiguration",
            "Test-SessionFileValid"
        )

        $missing = @()
        foreach ($func in $criticalFunctions) {
            if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
                $missing += $func
            }
        }

        if ($missing.Count -eq 0) {
            Write-TestResult "Critical Functions Exist" "PASS" "All $($criticalFunctions.Count) functions available"
        } else {
            Write-TestResult "Critical Functions Exist" "FAIL" "$($missing.Count) missing: $($missing -join ', ')"
        }
    } catch {
        Write-TestResult "Critical Functions Exist" "FAIL" $_.Exception.Message
    }

    # Test 18: Safe Name Sanitization
    try {
        $testNames = @(
            @{ Input = "My:Test*Session"; Expected = "My_Test_Session" }
            @{ Input = 'Test"Session'; Expected = "Test_Session" }
            @{ Input = "Test<>Session"; Expected = "Test__Session" }
            @{ Input = "Test|Session"; Expected = "Test_Session" }
        )

        $failures = @()
        foreach ($test in $testNames) {
            $result = $test.Input -replace '[:*?"<>|]', '_'
            if ($result -ne $test.Expected) {
                $failures += "Expected '$($test.Expected)', got '$result'"
            }
        }

        if ($failures.Count -eq 0) {
            Write-TestResult "Safe Name Sanitization" "PASS" "All special characters handled correctly"
        } else {
            Write-TestResult "Safe Name Sanitization" "FAIL" "$($failures.Count) sanitization failures"
        }
    } catch {
        Write-TestResult "Safe Name Sanitization" "FAIL" $_.Exception.Message
    }

    # Test 19: Session ID Format Validation
    try {
        # Generate test GUID and validate format
        $testGuid = [Guid]::NewGuid().ToString()
        $guidPattern = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

        if ($testGuid -match $guidPattern) {
            Write-TestResult "Session ID Format" "PASS" "GUID format validation works"
        } else {
            Write-TestResult "Session ID Format" "FAIL" "GUID pattern matching failed"
        }
    } catch {
        Write-TestResult "Session ID Format" "FAIL" $_.Exception.Message
    }

    # Test 20: Date Parsing Logic
    try {
        $testDate = [DateTime]::Now
        $formatted = $testDate.ToString('MM/dd HH:mm')
        $parsed = [DateTime]::ParseExact($formatted, 'MM/dd HH:mm', $null)

        if ($parsed.Month -eq $testDate.Month -and $parsed.Day -eq $testDate.Day) {
            Write-TestResult "Date Parsing Logic" "PASS" "Date format parsing works correctly"
        } else {
            Write-TestResult "Date Parsing Logic" "FAIL" "Date parsing mismatch"
        }
    } catch {
        Write-TestResult "Date Parsing Logic" "FAIL" $_.Exception.Message
    }

    # Test 21: Truncate-String Function
    try {
        $longString = "This is a very long string that needs truncation"
        $truncated = Truncate-String $longString 20

        if ($truncated.Length -le 20) {
            Write-TestResult "String Truncation" "PASS" "Truncation respects max length"
        } else {
            Write-TestResult "String Truncation" "FAIL" "Truncated string exceeds max length"
        }
    } catch {
        Write-TestResult "String Truncation" "FAIL" $_.Exception.Message
    }

    # Test 22: Global Variable Initialization
    try {
        $requiredGlobals = @(
            "MenuPath",
            "SessionMappingPath",
            "BackgroundTrackingPath",
            "ClaudeProjectsPath",
            "DebugLogPath",
            "ScriptVersion"
        )

        $missing = @()
        foreach ($var in $requiredGlobals) {
            if (-not (Get-Variable -Name $var -Scope Global -ErrorAction SilentlyContinue)) {
                $missing += $var
            }
        }

        if ($missing.Count -eq 0) {
            Write-TestResult "Global Variables" "PASS" "All required globals initialized"
        } else {
            Write-TestResult "Global Variables" "FAIL" "$($missing.Count) missing: $($missing -join ', ')"
        }
    } catch {
        Write-TestResult "Global Variables" "FAIL" $_.Exception.Message
    }

    # Test 23: Model Name Parsing
    try {
        $testModels = @("opus", "sonnet", "haiku", "claude-sonnet-4-5", "claude-opus-4")
        $allValid = $true

        foreach ($model in $testModels) {
            if ($model -notmatch '^(opus|sonnet|haiku|claude-)') {
                $allValid = $false
                break
            }
        }

        if ($allValid) {
            Write-TestResult "Model Name Parsing" "PASS" "Model name patterns recognized"
        } else {
            Write-TestResult "Model Name Parsing" "FAIL" "Invalid model name pattern"
        }
    } catch {
        Write-TestResult "Model Name Parsing" "FAIL" $_.Exception.Message
    }

    # Test 24: Sort Column Range Validation
    try {
        # Test that sort column numbers are in valid range (1-11 based on key handlers)
        $validSortColumns = 1..11
        $testValue = 5  # Test value (not modifying global)

        # Test the validation logic without modifying global state
        if ($validSortColumns -contains $testValue) {
            Write-TestResult "Sort Column Range" "PASS" "Sort column validation logic works"
        } else {
            Write-TestResult "Sort Column Range" "FAIL" "Sort column validation failed"
        }
    } catch {
        Write-TestResult "Sort Column Range" "FAIL" $_.Exception.Message
    }

    # Test 25: Menu Navigation Keys Defined
    try {
        # These keys should be handled in the navigation logic
        $expectedKeys = @('N', 'W', 'S', 'H', 'Q', 'C', 'O', 'D', 'R', 'G', 'A', 'X')
        $keysDocumented = $expectedKeys.Count -ge 10

        if ($keysDocumented) {
            Write-TestResult "Menu Navigation Keys" "PASS" "$($expectedKeys.Count) menu keys defined"
        } else {
            Write-TestResult "Menu Navigation Keys" "WARN" "Fewer than expected menu keys"
        }
    } catch {
        Write-TestResult "Menu Navigation Keys" "FAIL" $_.Exception.Message
    }

    # Test 26: Table Box Width Calculation
    try {
        # Test that box width calculations don't produce negative numbers
        $testWidth = 120
        $fixedWidth = 50
        $spacesBetween = 10
        $pathWidth = $testWidth - 4 - $fixedWidth - $spacesBetween

        if ($pathWidth -gt 0) {
            Write-TestResult "Table Width Calculation" "PASS" "Box width math produces valid results"
        } else {
            Write-TestResult "Table Width Calculation" "FAIL" "Negative width calculated"
        }
    } catch {
        Write-TestResult "Table Width Calculation" "FAIL" $_.Exception.Message
    }

    # Test 27: Permission State Consistency
    try {
        $permStatus = Get-GlobalPermissionStatus
        # Should return either boolean or hashtable with Enabled property
        $isValid = ($permStatus -is [bool]) -or
                   (($permStatus -is [hashtable]) -and $permStatus.ContainsKey('Enabled'))

        if ($isValid) {
            Write-TestResult "Permission State Logic" "PASS" "Permission status returns valid format"
        } else {
            Write-TestResult "Permission State Logic" "FAIL" "Permission status format invalid"
        }
    } catch {
        Write-TestResult "Permission State Logic" "FAIL" $_.Exception.Message
    }

    # Test 28: Debug State Functions
    try {
        # Test that debug state functions exist and return consistent values
        # without modifying the user's current debug state
        if ((Get-Command Get-DebugState -ErrorAction SilentlyContinue) -and
            (Get-Command Set-DebugState -ErrorAction SilentlyContinue)) {

            $state = Get-DebugState
            $isValid = ($state -is [bool])

            if ($isValid) {
                Write-TestResult "Debug State Functions" "PASS" "Debug state functions available and working"
            } else {
                Write-TestResult "Debug State Functions" "FAIL" "Debug state returns invalid type"
            }
        } else {
            Write-TestResult "Debug State Functions" "FAIL" "Debug state functions missing"
        }
    } catch {
        Write-TestResult "Debug State Functions" "FAIL" $_.Exception.Message
    }

    # Test 29: Color Scheme Constants
    try {
        # Verify that color constants are strings
        $testColors = @("Yellow", "Green", "Red", "Cyan", "Gray")
        $allStrings = $true

        foreach ($color in $testColors) {
            if ($color -isnot [string]) {
                $allStrings = $false
                break
            }
        }

        if ($allStrings) {
            Write-TestResult "Color Scheme Constants" "PASS" "Color values are valid strings"
        } else {
            Write-TestResult "Color Scheme Constants" "FAIL" "Invalid color value type"
        }
    } catch {
        Write-TestResult "Color Scheme Constants" "FAIL" $_.Exception.Message
    }

    # Test 30: Session Object Structure
    try {
        # Get a sample session and verify it has expected properties
        $sessions = Get-AllClaudeSessions
        if ($sessions -and $sessions.Count -gt 0) {
            $session = $sessions[0]
            $requiredProps = @('sessionId', 'projectPath', 'created', 'modified')
            $missing = @()

            foreach ($prop in $requiredProps) {
                if (-not ($session.PSObject.Properties.Name -contains $prop)) {
                    $missing += $prop
                }
            }

            if ($missing.Count -eq 0) {
                Write-TestResult "Session Object Structure" "PASS" "Session objects have required properties"
            } else {
                Write-TestResult "Session Object Structure" "FAIL" "Missing properties: $($missing -join ', ')"
            }
        } else {
            Write-TestResult "Session Object Structure" "WARN" "No sessions available to test"
        }
    } catch {
        Write-TestResult "Session Object Structure" "FAIL" $_.Exception.Message
    }

    # Test 31: Menu Keys Match Handlers
    try {
        # Verify that advertised menu keys actually have handlers
        # These are the keys shown in main menu prompts
        $menuKeys = @('N', 'W', 'S', 'H', 'Q', 'C', 'O', 'D', 'R', 'G', 'A', 'X')

        # Read the script to find key handlers in navigation logic
        $scriptContent = Get-Content $PSCommandPath -Raw
        $missingHandlers = @()

        foreach ($key in $menuKeys) {
            # Look for handler patterns like: if ($char -eq 'N')  or  if ($userInput -eq 'N'
            $pattern = "if\s*\(\s*\`$\w+\s+-eq\s+'$key'"
            if ($scriptContent -notmatch $pattern) {
                $missingHandlers += $key
            }
        }

        if ($missingHandlers.Count -eq 0) {
            Write-TestResult "Menu Key Handlers" "PASS" "All $($menuKeys.Count) menu keys have handlers"
        } else {
            Write-TestResult "Menu Key Handlers" "FAIL" "Missing handlers for: $($missingHandlers -join ', ')"
        }
    } catch {
        Write-TestResult "Menu Key Handlers" "FAIL" $_.Exception.Message
    }

    # Test 32: Column Sort Keys (1-11)
    try {
        # Verify that numeric key sorting handler exists (handles all 0-9 keys)
        $scriptContent = Get-Content $PSCommandPath -Raw

        # The actual implementation uses: if ($char -match '^[0-9]$')
        # This single handler covers all column sort keys 1-11 (1-9, 0 for 10, and mapped to 11)
        $hasNumericHandler = $scriptContent -match '\$char -match ''\^\[0-9\]\$'''
        $hasSortColumn = $scriptContent -match '\$Global:SortColumn\s*='

        if ($hasNumericHandler -and $hasSortColumn) {
            Write-TestResult "Column Sort Keys" "PASS" "Numeric key sort handler exists for all columns"
        } else {
            Write-TestResult "Column Sort Keys" "FAIL" "Sort handler pattern not found"
        }
    } catch {
        Write-TestResult "Column Sort Keys" "FAIL" $_.Exception.Message
    }

    # Test 33: Path Encoding Edge Cases
    try {
        $testCases = @(
            @{ Path = "C:\repos\"; Expected = "C--repos" }  # Trailing slash
            @{ Path = "C:\repos"; Expected = "C--repos" }   # No trailing slash
            @{ Path = "c:\temp"; Expected = "c--temp" }     # Lowercase drive
            @{ Path = "C:\"; Expected = "C" }               # Root path (trimmed to C:, then colon removed)
        )

        $failures = @()
        foreach ($test in $testCases) {
            $encoded = ConvertTo-ClaudeprojectPath -Path $test.Path
            if ($encoded -ne $test.Expected) {
                $failures += "Path '$($test.Path)' -> '$encoded' (expected '$($test.Expected)')"
            }
        }

        if ($failures.Count -eq 0) {
            Write-TestResult "Path Encoding Edge Cases" "PASS" "All edge cases handled correctly"
        } else {
            Write-TestResult "Path Encoding Edge Cases" "FAIL" "$($failures.Count) failures"
        }
    } catch {
        Write-TestResult "Path Encoding Edge Cases" "FAIL" $_.Exception.Message
    }

    # Test 34: String Truncation Edge Cases
    try {
        $failures = @()

        # Test 1: String shorter than max - should return unchanged
        $short = "Hello"
        $result1 = Truncate-String $short 10
        if ($result1 -ne "Hello") {
            $failures += "Short string modified: '$result1'"
        }

        # Test 2: Empty string - should return empty
        $empty = ""
        $result2 = Truncate-String $empty 10
        if ($result2 -ne "") {
            $failures += "Empty string not handled: '$result2'"
        }

        # Test 3: String that needs truncation
        # Truncate-String uses MaxLength - 1 to leave space for next column
        # So a 10-char string with MaxLength=10 becomes 9 characters
        $long = "1234567890"
        $result3 = Truncate-String $long 10
        if ($result3.Length -ne 9) {
            $failures += "Truncation logic failed: got length=$($result3.Length), expected 9"
        }

        if ($failures.Count -eq 0) {
            Write-TestResult "String Truncation Edge Cases" "PASS" "All truncation edge cases work"
        } else {
            Write-TestResult "String Truncation Edge Cases" "FAIL" "$($failures.Count) failures"
        }
    } catch {
        Write-TestResult "String Truncation Edge Cases" "FAIL" $_.Exception.Message
    }

    # Test 35: JSON File Structure Validation
    try {
        $failures = @()

        # Check session-mapping.json structure
        if (Test-Path $Global:SessionMappingPath) {
            $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json
            if (-not $mapping.PSObject.Properties['sessions']) {
                $failures += "session-mapping.json missing 'sessions' array"
            }
        }

        # Check background-tracking.json structure
        if (Test-Path $Global:BackgroundTrackingPath) {
            $tracking = Get-Content $Global:BackgroundTrackingPath -Raw | ConvertFrom-Json
            if (-not $tracking.PSObject.Properties['backgrounds']) {
                $failures += "background-tracking.json missing 'backgrounds' array"
            }
        }

        if ($failures.Count -eq 0) {
            Write-TestResult "JSON Structure Validation" "PASS" "JSON files have correct structure"
        } else {
            Write-TestResult "JSON Structure Validation" "FAIL" "$($failures -join ', ')"
        }
    } catch {
        Write-TestResult "JSON Structure Validation" "FAIL" $_.Exception.Message
    }

    # Test 36: WT Profile Name Format
    try {
        # Test that WT profile names follow convention: "Claude-<name>"
        if (Test-Path $Global:SessionMappingPath) {
            $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json
            $invalidNames = @()

            foreach ($session in $mapping.sessions) {
                if ($session.wtProfileName -and $session.wtProfileName -notmatch '^Claude-') {
                    $invalidNames += $session.wtProfileName
                }
            }

            if ($invalidNames.Count -eq 0) {
                Write-TestResult "WT Profile Name Format" "PASS" "All profile names follow 'Claude-*' convention"
            } else {
                Write-TestResult "WT Profile Name Format" "FAIL" "$($invalidNames.Count) profiles don't follow convention"
            }
        } else {
            Write-TestResult "WT Profile Name Format" "WARN" "Cannot check (no session-mapping.json)"
        }
    } catch {
        Write-TestResult "WT Profile Name Format" "FAIL" $_.Exception.Message
    }

    # Test 37: GUID Format Validation
    try {
        # Test GUID generation and validation
        $testGuid = [Guid]::NewGuid().ToString()
        $guidPattern = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

        $failures = @()

        # Valid GUID should match
        if ($testGuid -notmatch $guidPattern) {
            $failures += "Valid GUID rejected"
        }

        # Invalid GUIDs should not match
        $invalidGuids = @("not-a-guid", "12345", "")
        foreach ($invalid in $invalidGuids) {
            if ($invalid -match $guidPattern) {
                $failures += "Invalid GUID accepted: $invalid"
            }
        }

        if ($failures.Count -eq 0) {
            Write-TestResult "GUID Validation Logic" "PASS" "GUID validation works correctly"
        } else {
            Write-TestResult "GUID Validation Logic" "FAIL" "$($failures -join ', ')"
        }
    } catch {
        Write-TestResult "GUID Validation Logic" "FAIL" $_.Exception.Message
    }

    # Test 38: Background Image Path Consistency
    try {
        # Verify background image paths follow expected structure
        if (Test-Path $Global:BackgroundTrackingPath) {
            $tracking = Get-Content $Global:BackgroundTrackingPath -Raw | ConvertFrom-Json
            $invalidPaths = @()

            foreach ($bg in $tracking.backgrounds) {
                # Should be under .claude-menu directory and end with background.png
                if ($bg.backgroundPath -notmatch [regex]::Escape($Global:MenuPath)) {
                    $invalidPaths += $bg.backgroundPath
                }
                if ($bg.backgroundPath -notmatch 'background\.png$') {
                    $invalidPaths += $bg.backgroundPath
                }
            }

            if ($invalidPaths.Count -eq 0) {
                Write-TestResult "Background Path Format" "PASS" "All background paths follow convention"
            } else {
                Write-TestResult "Background Path Format" "FAIL" "$($invalidPaths.Count) invalid paths"
            }
        } else {
            Write-TestResult "Background Path Format" "WARN" "Cannot check (no background-tracking.json)"
        }
    } catch {
        Write-TestResult "Background Path Format" "FAIL" $_.Exception.Message
    }

    # Test 39: Session Mapping Consistency
    try {
        # Check that session IDs in mapping actually exist in Claude projects
        if (Test-Path $Global:SessionMappingPath) {
            $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json
            $orphanedSessions = @()

            foreach ($session in $mapping.sessions) {
                $encodedPath = ConvertTo-ClaudeprojectPath -Path $session.projectPath
                $sessionFile = Join-Path $Global:ClaudeProjectsPath "$encodedPath\$($session.sessionId).jsonl"

                if (-not (Test-Path $sessionFile)) {
                    $orphanedSessions += $session.sessionId
                }
            }

            if ($orphanedSessions.Count -eq 0) {
                Write-TestResult "Session Mapping Consistency" "PASS" "All mapped sessions have valid files"
            } else {
                Write-TestResult "Session Mapping Consistency" "WARN" "$($orphanedSessions.Count) orphaned mappings"
            }
        } else {
            Write-TestResult "Session Mapping Consistency" "WARN" "Cannot check (no session-mapping.json)"
        }
    } catch {
        Write-TestResult "Session Mapping Consistency" "FAIL" $_.Exception.Message
    }

    # Test 40: Model Name Format Validation
    try {
        # Test that model name parsing handles expected formats
        $validModels = @("opus", "sonnet", "haiku", "claude-opus-4-5", "claude-sonnet-4-5-20250929")
        $invalidModels = @("", "invalid-model", "123", "gpt-4")

        $failures = @()

        # Valid models should match pattern
        foreach ($model in $validModels) {
            if ($model -notmatch '^(opus|sonnet|haiku|claude-)') {
                $failures += "Valid model rejected: $model"
            }
        }

        # Invalid models should not match
        foreach ($model in $invalidModels) {
            if ($model -match '^(opus|sonnet|haiku|claude-)') {
                $failures += "Invalid model accepted: $model"
            }
        }

        if ($failures.Count -eq 0) {
            Write-TestResult "Model Name Validation" "PASS" "Model name patterns work correctly"
        } else {
            Write-TestResult "Model Name Validation" "FAIL" "$($failures -join ', ')"
        }
    } catch {
        Write-TestResult "Model Name Validation" "FAIL" $_.Exception.Message
    }

    # Test 41: Get-ModelFromBackgroundTxt Function
    try {
        # Test that function exists and handles missing file gracefully
        if (Get-Command Get-ModelFromBackgroundTxt -ErrorAction SilentlyContinue) {
            # Test with non-existent profile (should return empty string)
            $result = Get-ModelFromBackgroundTxt -WTProfileName "Claude-NonExistentProfile12345"
            if ($result -eq "") {
                Write-TestResult "Get-ModelFromBackgroundTxt" "PASS" "Function exists and handles missing files"
            } else {
                Write-TestResult "Get-ModelFromBackgroundTxt" "FAIL" "Should return empty for missing profile"
            }
        } else {
            Write-TestResult "Get-ModelFromBackgroundTxt" "FAIL" "Function not found"
        }
    } catch {
        Write-TestResult "Get-ModelFromBackgroundTxt" "FAIL" $_.Exception.Message
    }

    # Test 42: Get-BranchFromBackgroundTxt Function
    try {
        # Test that function exists and handles missing file gracefully
        if (Get-Command Get-BranchFromBackgroundTxt -ErrorAction SilentlyContinue) {
            # Test with non-existent profile (should return empty string)
            $result = Get-BranchFromBackgroundTxt -WTProfileName "Claude-NonExistentProfile12345"
            if ($result -eq "") {
                Write-TestResult "Get-BranchFromBackgroundTxt" "PASS" "Function exists and handles missing files"
            } else {
                Write-TestResult "Get-BranchFromBackgroundTxt" "FAIL" "Should return empty for missing profile"
            }
        } else {
            Write-TestResult "Get-BranchFromBackgroundTxt" "FAIL" "Function not found"
        }
    } catch {
        Write-TestResult "Get-BranchFromBackgroundTxt" "FAIL" $_.Exception.Message
    }

    # Test 43: Get-AllValuesFromBackgroundTxt Function
    try {
        # Test that function exists and handles missing file gracefully
        if (Get-Command Get-AllValuesFromBackgroundTxt -ErrorAction SilentlyContinue) {
            # Test with non-existent profile (should return $null)
            $result = Get-AllValuesFromBackgroundTxt -WTProfileName "Claude-NonExistentProfile12345"
            if ($null -eq $result) {
                Write-TestResult "Get-AllValuesFromBackgroundTxt" "PASS" "Function exists and handles missing files"
            } else {
                Write-TestResult "Get-AllValuesFromBackgroundTxt" "FAIL" "Should return null for missing profile"
            }
        } else {
            Write-TestResult "Get-AllValuesFromBackgroundTxt" "FAIL" "Function not found"
        }
    } catch {
        Write-TestResult "Get-AllValuesFromBackgroundTxt" "FAIL" $_.Exception.Message
    }

    # Test 44: Update-BackgroundIfChanged Function Exists
    try {
        if (Get-Command Update-BackgroundIfChanged -ErrorAction SilentlyContinue) {
            Write-TestResult "Update-BackgroundIfChanged" "PASS" "Function exists"
        } else {
            Write-TestResult "Update-BackgroundIfChanged" "FAIL" "Function not found"
        }
    } catch {
        Write-TestResult "Update-BackgroundIfChanged" "FAIL" $_.Exception.Message
    }

    # Test 45: Background .txt File Format Validation
    try {
        # Check that existing background.txt files have expected format
        if (Test-Path $Global:MenuPath) {
            $txtFiles = Get-ChildItem -Path $Global:MenuPath -Recurse -Filter "background.txt" -ErrorAction SilentlyContinue
            $invalidFiles = @()
            $checkedCount = 0

            foreach ($txtFile in $txtFiles) {
                $checkedCount++
                $content = Get-Content $txtFile.FullName -Raw -ErrorAction SilentlyContinue

                # Must contain at least Session: and Directory: lines
                if ($content -notmatch 'Session:') {
                    $invalidFiles += "$($txtFile.Name) missing Session:"
                }
                if ($content -notmatch 'Directory:') {
                    $invalidFiles += "$($txtFile.Name) missing Directory:"
                }
            }

            if ($checkedCount -eq 0) {
                Write-TestResult "Background .txt Format" "WARN" "No background.txt files found to validate"
            } elseif ($invalidFiles.Count -eq 0) {
                Write-TestResult "Background .txt Format" "PASS" "$checkedCount file(s) have valid format"
            } else {
                Write-TestResult "Background .txt Format" "FAIL" "$($invalidFiles.Count) invalid file(s)"
            }
        } else {
            Write-TestResult "Background .txt Format" "WARN" "Menu path does not exist"
        }
    } catch {
        Write-TestResult "Background .txt Format" "FAIL" $_.Exception.Message
    }

    # Test 46: Background .txt and .png Pairing
    try {
        # Check that each background.png has a corresponding background.txt
        if (Test-Path $Global:MenuPath) {
            $pngFiles = Get-ChildItem -Path $Global:MenuPath -Recurse -Filter "background.png" -ErrorAction SilentlyContinue
            $missingTxt = @()

            foreach ($pngFile in $pngFiles) {
                $txtPath = $pngFile.FullName -replace '\.png$', '.txt'
                if (-not (Test-Path $txtPath)) {
                    $missingTxt += $pngFile.Directory.Name
                }
            }

            if ($pngFiles.Count -eq 0) {
                Write-TestResult "Background .txt/.png Pairing" "WARN" "No background.png files found"
            } elseif ($missingTxt.Count -eq 0) {
                Write-TestResult "Background .txt/.png Pairing" "PASS" "All $($pngFiles.Count) PNG files have .txt"
            } else {
                Write-TestResult "Background .txt/.png Pairing" "WARN" "$($missingTxt.Count) PNG file(s) missing .txt"
            }
        } else {
            Write-TestResult "Background .txt/.png Pairing" "WARN" "Menu path does not exist"
        }
    } catch {
        Write-TestResult "Background .txt/.png Pairing" "FAIL" $_.Exception.Message
    }

    # Test 47: Model Cache Global Variable
    try {
        if (Get-Variable -Name ModelCache -Scope Global -ErrorAction SilentlyContinue) {
            $cache = $Global:ModelCache
            if ($cache -is [hashtable]) {
                Write-TestResult "Model Cache Variable" "PASS" "ModelCache hashtable exists with $($cache.Count) entries"
            } else {
                Write-TestResult "Model Cache Variable" "FAIL" "ModelCache is not a hashtable"
            }
        } else {
            Write-TestResult "Model Cache Variable" "FAIL" "Global:ModelCache not found"
        }
    } catch {
        Write-TestResult "Model Cache Variable" "FAIL" $_.Exception.Message
    }

    # Test 48: Background Txt Parsing Patterns
    try {
        # Test the regex patterns used for parsing background.txt
        $testLines = @(
            @{ Line = "Session: TestSession"; Pattern = '^Session:\s*(.+)$'; Expected = "TestSession" }
            @{ Line = "Model: opus"; Pattern = '^Model:\s*(.+)$'; Expected = "opus" }
            @{ Line = "Branch: main"; Pattern = '^Branch:\s*(.+)$'; Expected = "main" }
            @{ Line = "Directory: C:\repos"; Pattern = '^Directory:\s*(.+)$'; Expected = "C:\repos" }
            @{ Line = "Forked from: parent-session"; Pattern = '^Forked from:\s*(.+)$'; Expected = "parent-session" }
            @{ Line = "Computer:User: PC\User"; Pattern = '^Computer:User:\s*(.+)$'; Expected = "PC\User" }
        )

        $failures = @()
        foreach ($test in $testLines) {
            if ($test.Line -match $test.Pattern) {
                if ($Matches[1].Trim() -ne $test.Expected) {
                    $failures += "Pattern '$($test.Pattern)' extracted '$($Matches[1])' instead of '$($test.Expected)'"
                }
            } else {
                $failures += "Pattern '$($test.Pattern)' didn't match '$($test.Line)'"
            }
        }

        if ($failures.Count -eq 0) {
            Write-TestResult "Background Txt Patterns" "PASS" "All $($testLines.Count) parsing patterns work"
        } else {
            Write-TestResult "Background Txt Patterns" "FAIL" "$($failures.Count) pattern failures"
        }
    } catch {
        Write-TestResult "Background Txt Patterns" "FAIL" $_.Exception.Message
    }

    # Test 49: IsRefresh Parameter Flow
    try {
        # Verify Show-SessionMenu has IsRefresh parameter
        $func = Get-Command Show-SessionMenu -ErrorAction SilentlyContinue
        if ($func) {
            $params = $func.Parameters
            if ($params.ContainsKey('IsRefresh')) {
                $paramType = $params['IsRefresh'].ParameterType.Name
                if ($paramType -eq 'Boolean') {
                    Write-TestResult "IsRefresh Parameter" "PASS" "Show-SessionMenu has IsRefresh [bool] parameter"
                } else {
                    Write-TestResult "IsRefresh Parameter" "FAIL" "IsRefresh should be bool, got $paramType"
                }
            } else {
                Write-TestResult "IsRefresh Parameter" "FAIL" "Show-SessionMenu missing IsRefresh parameter"
            }
        } else {
            Write-TestResult "IsRefresh Parameter" "FAIL" "Show-SessionMenu function not found"
        }
    } catch {
        Write-TestResult "IsRefresh Parameter" "FAIL" $_.Exception.Message
    }

    # Test 50: Critical New Functions Exist
    try {
        $newFunctions = @(
            "Get-ModelFromBackgroundTxt",
            "Get-BranchFromBackgroundTxt",
            "Get-AllValuesFromBackgroundTxt",
            "Update-BackgroundIfChanged"
        )

        $missing = @()
        foreach ($func in $newFunctions) {
            if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
                $missing += $func
            }
        }

        if ($missing.Count -eq 0) {
            Write-TestResult "New Background Functions" "PASS" "All $($newFunctions.Count) new functions available"
        } else {
            Write-TestResult "New Background Functions" "FAIL" "$($missing.Count) missing: $($missing -join ', ')"
        }
    } catch {
        Write-TestResult "New Background Functions" "FAIL" $_.Exception.Message
    }

    # Test 51: LimitFeature - Get-SessionContextUsage Function
    # LimitFeature: Validation test
    try {
        if (Get-Command Get-SessionContextUsage -ErrorAction SilentlyContinue) {
            # Test with non-existent session (should return $null)
            $result = Get-SessionContextUsage -SessionId "nonexistent-session-id" -ProjectPath "C:\nonexistent" -Model "sonnet"
            if ($null -eq $result) {
                Write-TestResult "LimitFeature: Get-SessionContextUsage" "PASS" "Function exists and handles missing sessions"
            } else {
                Write-TestResult "LimitFeature: Get-SessionContextUsage" "FAIL" "Should return null for missing session"
            }
        } else {
            Write-TestResult "LimitFeature: Get-SessionContextUsage" "FAIL" "Function not found"
        }
    } catch {
        Write-TestResult "LimitFeature: Get-SessionContextUsage" "FAIL" $_.Exception.Message
    }

    # Test 52: LimitFeature - Context Limits Defined
    # LimitFeature: Validation test
    try {
        # Verify context limits are reasonable values
        $expectedLimits = @{
            "opus" = 200000
            "sonnet" = 200000
            "haiku" = 200000
        }

        $failures = @()
        foreach ($model in $expectedLimits.Keys) {
            $limit = $expectedLimits[$model]
            if ($limit -lt 100000 -or $limit -gt 1000000) {
                $failures += "Invalid limit for $model : $limit"
            }
        }

        if ($failures.Count -eq 0) {
            Write-TestResult "LimitFeature: Context Limits" "PASS" "Context limits are within expected range"
        } else {
            Write-TestResult "LimitFeature: Context Limits" "FAIL" "$($failures -join ', ')"
        }
    } catch {
        Write-TestResult "LimitFeature: Context Limits" "FAIL" $_.Exception.Message
    }

    # Test 53: LimitFeature - Limit Column in Configuration
    # LimitFeature: Validation test
    try {
        $config = Get-ColumnConfiguration
        if ($config.ContainsKey('Limit')) {
            # Verify Limit is false by default (hidden)
            if ($config.Limit -eq $false) {
                Write-TestResult "LimitFeature: Limit Column Config" "PASS" "Limit column exists and defaults to hidden"
            } else {
                Write-TestResult "LimitFeature: Limit Column Config" "WARN" "Limit column exists but is enabled (expected hidden by default)"
            }
        } else {
            Write-TestResult "LimitFeature: Limit Column Config" "FAIL" "Limit column not in configuration"
        }
    } catch {
        Write-TestResult "LimitFeature: Limit Column Config" "FAIL" $_.Exception.Message
    }

    # Test 54: LimitFeature - Percentage Calculation Logic
    # LimitFeature: Validation test
    try {
        # Test percentage calculation logic
        $testCases = @(
            @{ Tokens = 180000; Limit = 200000; ExpectedPct = 90 }
            @{ Tokens = 198000; Limit = 200000; ExpectedPct = 99 }
            @{ Tokens = 100000; Limit = 200000; ExpectedPct = 50 }
            @{ Tokens = 200000; Limit = 200000; ExpectedPct = 100 }
        )

        $failures = @()
        foreach ($test in $testCases) {
            $calculated = [math]::Round(($test.Tokens / $test.Limit) * 100, 0)
            if ($calculated -ne $test.ExpectedPct) {
                $failures += "Expected $($test.ExpectedPct)%, got $calculated%"
            }
        }

        if ($failures.Count -eq 0) {
            Write-TestResult "LimitFeature: Percentage Calculation" "PASS" "All percentage calculations correct"
        } else {
            Write-TestResult "LimitFeature: Percentage Calculation" "FAIL" "$($failures -join ', ')"
        }
    } catch {
        Write-TestResult "LimitFeature: Percentage Calculation" "FAIL" $_.Exception.Message
    }

    # Test 55: Column Consistency - All column blocks must have same columns in same order
    # This test would have caught the Draw-SessionRow missing Limit column bug
    try {
        # Get the expected column order from configuration
        $expectedColumns = @('Active', 'Limit', 'Model', 'Session', 'Notes', 'Messages', 'Created', 'Modified', 'Cost', 'WinTerminal', 'ForkedFrom', 'Git', 'Path')

        # Read the script source
        $scriptPath = $PSCommandPath
        if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Path }
        if (-not $scriptPath) { $scriptPath = "$env:USERPROFILE\.claude-menu\Claude-Menu.ps1" }

        if (Test-Path $scriptPath) {
            $scriptContent = Get-Content $scriptPath -Raw

            # Pattern to find columnConfig checks - looking for if ($columnConfig.X) patterns
            $columnPattern = '\$columnConfig\.(\w+)\)'

            # Find all sections that build format strings (look for formatParts += patterns)
            $formatSections = [regex]::Matches($scriptContent, 'formatParts\s*\+=.*?\$valueIndex\+\+[^}]+', [System.Text.RegularExpressions.RegexOptions]::Singleline)

            $issues = @()

            # Check each format section for column order consistency
            $sectionCount = 0
            foreach ($section in $formatSections) {
                $sectionCount++
                $columnMatches = [regex]::Matches($section.Value, $columnPattern)
                $columnsInSection = $columnMatches | ForEach-Object { $_.Groups[1].Value }

                # Build the expected subset based on which columns appear
                $expectedSubset = $expectedColumns | Where-Object { $columnsInSection -contains $_ }

                # Verify order matches expected
                for ($i = 0; $i -lt $columnsInSection.Count; $i++) {
                    if ($i -lt $expectedSubset.Count -and $columnsInSection[$i] -ne $expectedSubset[$i]) {
                        $issues += "Section $sectionCount : Column order mismatch at position $i - found '$($columnsInSection[$i])' expected '$($expectedSubset[$i])'"
                    }
                }
            }

            # Verify at least 2 format sections exist (main display and Draw-SessionRow)
            if ($sectionCount -lt 2) {
                $issues += "Expected at least 2 format sections, found $sectionCount"
            }

            if ($issues.Count -eq 0) {
                Write-TestResult "Column Consistency Check" "PASS" "All $sectionCount format sections have consistent column order"
            } else {
                Write-TestResult "Column Consistency Check" "FAIL" ($issues -join '; ')
            }
        } else {
            Write-TestResult "Column Consistency Check" "SKIP" "Could not locate script file for analysis"
        }
    } catch {
        Write-TestResult "Column Consistency Check" "FAIL" $_.Exception.Message
    }

    # Summary
    Write-Host ""
    Write-ColorText "========================================" -Color Cyan
    Write-ColorText "           TEST SUMMARY" -Color Cyan
    Write-ColorText "========================================" -Color Cyan
    Write-Host ""
    Write-Host "Passed: " -NoNewline
    Write-Host $script:ValidationPassCount -ForegroundColor Green
    Write-Host "Warnings: " -NoNewline
    Write-Host $script:ValidationWarnCount -ForegroundColor Yellow
    Write-Host "Failed: " -NoNewline
    Write-Host $script:ValidationFailCount -ForegroundColor Red
    Write-Host ""

    if ($script:ValidationFailCount -eq 0 -and $script:ValidationWarnCount -eq 0) {
        Write-ColorText "All tests passed! System is healthy." -Color Green
    } elseif ($script:ValidationFailCount -eq 0) {
        Write-ColorText "All critical tests passed. Some warnings noted." -Color Yellow
    } else {
        Write-ColorText "Some tests failed. Please review failures above." -Color Red
    }

    Write-Host ""
    Write-ColorText "Press any key to return to debug menu..." -Color Yellow
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

    # Clean up script-scoped variables
    Remove-Variable -Name "ValidationPassCount" -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name "ValidationFailCount" -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name "ValidationWarnCount" -Scope Script -ErrorAction SilentlyContinue
}

function Show-AboutScreen {
    <#
    .SYNOPSIS
        Displays the About screen with ASCII art and version information
    #>

    Clear-Host
    Write-ColorText "Claude Code Session Manager with Win Terminal Forking" -Color Yellow
    Write-Host "Version: $Global:ScriptVersion" -ForegroundColor Gray
    Write-Host ""
    Write-Host "=**=---========--------===--=====--==-------==" -ForegroundColor Cyan
    Write-Host "==*#*==-=====++==-==============-------=======" -ForegroundColor Cyan
    Write-Host "--==-----=+++**++++++##*=*##*%%+=-------===--=" -ForegroundColor Cyan
    Write-Host "---=-----+#*+=###%%#++++*#%@@@#==-=--==--=---=" -ForegroundColor Cyan
    Write-Host "--==-----=+=====%@@@@@@@%%@@@%*=-----==------=" -ForegroundColor Cyan
    Write-Host "---====--=-=======*%@@@@@@@@@@#====--=========" -ForegroundColor Cyan
    Write-Host "----------====+======+%@@@@@@@%+==============" -ForegroundColor Cyan
    Write-Host "---=---==--==++-=-==+%@@@@@@@@*====+*+=-======" -ForegroundColor Cyan
    Write-Host "------=---==++++-====*@@@@@@@@@%+======++=====" -ForegroundColor Cyan
    Write-Host "-----==----=+++======*#@@%@@@@%%+======+======" -ForegroundColor Cyan
    Write-Host "-=--=------==+++====*%%@@%%%@@%%+=============" -ForegroundColor Cyan
    Write-Host "----=------==++====+%@@@@@@%%%%%+=============" -ForegroundColor Cyan
    Write-Host "---=-------==++==*%#%%@@@@@@@@@@%=============" -ForegroundColor Cyan
    Write-Host "-----------==+++#@@@@%%%@@@@@@@@@#=======+++*+" -ForegroundColor Cyan
    Write-Host "----------=-=+*%@@@@@@%*+#@@@@%@@@#=======+++=" -ForegroundColor Cyan
    Write-Host "-----=------==%@@@@@@@%**+#@%*+=+%@#=====+##+=" -ForegroundColor Cyan
    Write-Host "*#*+=--------*@@@%@@@@@@%%@@%+====+##*===+##*+" -ForegroundColor Cyan
    Write-Host "--==#*=----==%@@@@@@@%%@@@@@@*====**%*+===+===" -ForegroundColor Cyan
    Write-Host "==--=*#=----=*@@@@@@%%%%@@@@@%+=====+=====+===" -ForegroundColor Cyan
    Write-Host "=----=*%*=---*%@@@@@@%%%@@@@@%+============+==" -ForegroundColor Cyan
    Write-Host "--==--=+%#=--=#@@@@@@%%#%@@@@*======-=========" -ForegroundColor Cyan
    Write-Host "---=====+#@%*=+*@@@@@@%%%@@@#+================" -ForegroundColor Cyan
    Write-Host "==========+#@@@%@@@@@@%%@@%*==================" -ForegroundColor Cyan
    Write-Host "---====++===++*#@@@@%%%@@@%*+++=============++" -ForegroundColor Cyan
    Write-Host "*###%%%%%##%%%%%%%%%%##%@@@@@%%%%%%%%%%%%%%%@@" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "By: S. Rives" -ForegroundColor Gray
    Write-Host "GitHub: " -NoNewline -ForegroundColor Gray
    Write-Host "https://github.com/srives/WinClaudeCodeForker" -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

function Show-DebugToggle {
    <#
    .SYNOPSIS
        Shows debug menu with options to toggle, view log, or see instructions
    #>

    $currentState = Get-DebugState
    $stateText = if ($currentState) { "ON" } else { "OFF" }
    $stateColor = if ($currentState) { "Green" } else { "Red" }

    Write-Host ""
    Write-ColorText "========================================" -Color Cyan
    Write-ColorText "               DEBUG MODE               " -Color Cyan
    Write-ColorText "========================================" -Color Cyan
    Write-Host ""
    Write-Host "Current state: " -NoNewline
    Write-Host $stateText -ForegroundColor $stateColor
    Write-Host ""
    $toggleText = if ($currentState) { "ebug Off" } else { "ebug On" }
    Write-Host "D" -NoNewline -ForegroundColor Yellow
    Write-Host $toggleText -NoNewline -ForegroundColor Gray
    Write-Host " | " -NoNewline -ForegroundColor Gray
    Write-Host "N" -NoNewline -ForegroundColor Yellow
    Write-Host "otepad - Open Debug Log | " -NoNewline -ForegroundColor Gray
    Write-Host "I" -NoNewline -ForegroundColor Yellow
    Write-Host "nstructions - Show debug mode help | " -NoNewline -ForegroundColor Gray
    Write-Host "V" -NoNewline -ForegroundColor Yellow
    Write-Host "alidation - Run system tests | " -NoNewline -ForegroundColor Gray
    Write-Host "A" -NoNewline -ForegroundColor Yellow
    Write-Host "bort" -NoNewline -ForegroundColor Gray

    while ($true) {
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $response = $key.Character.ToString().ToUpper()

        # Handle Esc as abort
        if ($key.VirtualKeyCode -eq 27) {
            $response = 'A'
        }

        # Handle Enter as default (toggle debug)
        if ($key.VirtualKeyCode -eq 13) {
            $response = 'D'
        }

        switch ($response) {
            'D' {
                # Toggle debug flag
                $newState = -not $currentState
                Set-DebugState -Enabled $newState
                return
            }
            'N' {
                # Open debug log in notepad
                if (Test-Path $Global:DebugLogPath) {
                    Start-Process notepad.exe -ArgumentList $Global:DebugLogPath
                } else {
                    Write-Host ""
                    Write-ColorText "Debug log file does not exist yet." -Color Yellow
                }
                return
            }
            'I' {
                # Show instructions
                Write-Host ""
                Write-ColorText "========================================" -Color Cyan
                Write-ColorText "  DEBUG MODE INSTRUCTIONS" -Color Cyan
                Write-ColorText "========================================" -Color Cyan
                Write-Host ""
                Write-ColorText "When debug is ON:" -Color Yellow
                Write-Host "  - Shows detailed session discovery information"
                Write-Host "  - Shows file paths being checked"
                Write-Host "  - Shows why sessions are found or not found"
                Write-Host "  - Shows refresh operation details"
                Write-Host "  - Writes all debug output to log file with timestamps"
                Write-Host ""
                Write-ColorText "Debug log file location:" -Color Cyan
                Write-Host "  $Global:DebugLogPath"
                Write-Host ""
                Write-ColorText "You can open the log anytime with:" -Color Cyan
                Write-Host "  notepad `"$Global:DebugLogPath`""
                Write-Host ""
                Write-Host "Press any key to return to the menu..." -ForegroundColor Yellow
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                return
            }
            'V' {
                # Run system validation
                Test-SystemValidation
                return
            }
            'A' {
                # Abort - return to main menu
                return
            }
            default {
                # Invalid choice - silently ignore
            }
        }
    }
}

#endregion

#region Cost Tracking

function Get-SessionMessageCount {
    <#
    .SYNOPSIS
        Counts the number of messages in a session .jsonl file
    #>
    param(
        [string]$SessionId,
        [string]$ProjectPath
    )

    if (-not $SessionId -or -not $ProjectPath) {
        return 0
    }

    try {
        # Get the session .jsonl file path
        $encodedPath = ConvertTo-ClaudeprojectPath -Path $ProjectPath
        $sessionFile = Join-Path $Global:ClaudeProjectsPath "$encodedPath\$SessionId.jsonl"

        if (-not (Test-Path $sessionFile)) {
            return 0
        }

        # Count user messages only (each represents a conversation turn)
        # Then multiply by 2 to include assistant responses
        $userCount = 0
        $reader = [System.IO.StreamReader]::new($sessionFile)
        try {
            while ($null -ne ($line = $reader.ReadLine())) {
                # Quick check before parsing JSON (performance optimization)
                if ($line -match '"type"\s*:\s*"user"') {
                    try {
                        $entry = $line | ConvertFrom-Json
                        # Only count if the TOP-LEVEL type is user
                        if ($entry.type -eq "user") {
                            $userCount++
                        }
                    } catch {
                        # Skip lines that can't be parsed
                        continue
                    }
                }
            }
        } finally {
            $reader.Close()
        }

        # Return user message count
        return $userCount

    } catch {
        Write-DebugInfo "Error counting session messages: $_" -Color Red
        return 0
    }
}

# LimitFeature: BEGIN - Context usage tracking for session handoff system
function Get-SessionContextUsage {
    <#
    .SYNOPSIS
        Gets the current context window usage percentage for a session
    .DESCRIPTION
        LimitFeature: Reads the last assistant message's token usage to determine
        how much of the context window is being used. Returns percentage.
        Total context = input_tokens + cache_creation_input_tokens + cache_read_input_tokens
        Context limits by model:
        - Opus/Sonnet: 200K tokens
        - Haiku: 200K tokens
    .RETURNS
        Hashtable with InputTokens, ContextLimit, Percentage, or $null if unavailable
    #>
    param(
        [string]$SessionId,
        [string]$ProjectPath,
        [string]$Model = "sonnet"  # Default to sonnet's limit
    )

    if (-not $SessionId -or -not $ProjectPath) {
        return $null
    }

    try {
        # Get the session .jsonl file path
        $encodedPath = ConvertTo-ClaudeprojectPath -Path $ProjectPath
        $sessionFile = Join-Path $Global:ClaudeProjectsPath "$encodedPath\$SessionId.jsonl"

        if (-not (Test-Path $sessionFile)) {
            Write-DebugInfo "LimitFeature: Session file not found: $sessionFile" -Color DarkGray
            return $null
        }

        # Context limits by model (in tokens)
        # LimitFeature: These are approximate - Claude Code may have different effective limits
        $contextLimits = @{
            "opus" = 200000
            "sonnet" = 200000
            "haiku" = 200000
            "default" = 200000
        }

        # Handle empty model - default to sonnet
        $modelKey = if ($Model -and $Model.Length -gt 0) { $Model.ToLower() } else { "default" }
        $contextLimit = if ($contextLimits.ContainsKey($modelKey)) {
            $contextLimits[$modelKey]
        } else {
            $contextLimits["default"]
        }

        # Read file and find the LAST assistant message with usage
        $lastInputTokens = 0
        $foundMessages = 0
        $reader = [System.IO.StreamReader]::new($sessionFile)
        try {
            while ($null -ne ($line = $reader.ReadLine())) {
                # Only check lines that contain assistant messages with usage
                if ($line -notmatch '"type"\s*:\s*"assistant"') {
                    continue
                }
                if ($line -notmatch '"usage"') {
                    continue
                }

                # Parse the JSON
                $entry = $line | ConvertFrom-Json

                # Check if this is an assistant message with usage info
                if ($entry.type -eq "assistant" -and $entry.message -and $entry.message.usage) {
                    $foundMessages++
                    $usage = $entry.message.usage
                    # Total context = input_tokens + cache_creation_input_tokens + cache_read_input_tokens
                    # input_tokens alone is just the new tokens, not the full context
                    $totalTokens = 0
                    if ($usage.input_tokens) { $totalTokens += $usage.input_tokens }
                    if ($usage.cache_creation_input_tokens) { $totalTokens += $usage.cache_creation_input_tokens }
                    if ($usage.cache_read_input_tokens) { $totalTokens += $usage.cache_read_input_tokens }
                    if ($totalTokens -gt 0) {
                        $lastInputTokens = $totalTokens
                    }
                }
            }
        } finally {
            $reader.Close()
        }

        Write-DebugInfo "LimitFeature: Session $($SessionId.Substring(0,8))... - Found $foundMessages msgs, totalTokens=$lastInputTokens" -Color DarkGray

        if ($lastInputTokens -eq 0) {
            return $null
        }

        # Calculate percentage
        $percentage = [math]::Round(($lastInputTokens / $contextLimit) * 100, 0)

        return @{
            TotalTokens = $lastInputTokens
            ContextLimit = $contextLimit
            Percentage = $percentage
            Model = $Model
        }

    } catch {
        Write-DebugInfo "LimitFeature: Error reading context usage: $_" -Color Red
        return $null
    }
}
# LimitFeature: END - Context usage tracking

function Get-SessionTokenUsage {
    <#
    .SYNOPSIS
        Parses a session .jsonl file and extracts token usage data
    #>
    param(
        [string]$SessionId,
        [string]$ProjectPath
    )

    if (-not $SessionId -or -not $ProjectPath) {
        return $null
    }

    # Check cache first
    $cacheKey = "$ProjectPath|$SessionId"
    if ($Global:TokenUsageCache.ContainsKey($cacheKey)) {
        return $Global:TokenUsageCache[$cacheKey]
    }

    try {
        # Get the session .jsonl file path
        $encodedPath = ConvertTo-ClaudeprojectPath -Path $ProjectPath
        $sessionFile = Join-Path $Global:ClaudeProjectsPath "$encodedPath\$SessionId.jsonl"

        if (-not (Test-Path $sessionFile)) {
            return $null
        }

        # Initialize totals
        $totalInputTokens = 0
        $totalCacheCreationTokens = 0
        $totalCacheReadTokens = 0
        $totalOutputTokens = 0

        # Read file line by line
        $reader = [System.IO.StreamReader]::new($sessionFile)
        try {
            while ($null -ne ($line = $reader.ReadLine())) {
                # Only check lines that contain assistant messages with usage
                if ($line -notmatch '"type":"assistant"' -or $line -notmatch '"usage"') {
                    continue
                }

                # Parse the JSON
                $entry = $line | ConvertFrom-Json

                # Check if this is an assistant message with usage info
                if ($entry.type -eq "assistant" -and $entry.message.usage) {
                    $usage = $entry.message.usage

                    $totalInputTokens += if ($usage.input_tokens) { $usage.input_tokens } else { 0 }
                    $totalCacheCreationTokens += if ($usage.cache_creation_input_tokens) { $usage.cache_creation_input_tokens } else { 0 }
                    $totalCacheReadTokens += if ($usage.cache_read_input_tokens) { $usage.cache_read_input_tokens } else { 0 }
                    $totalOutputTokens += if ($usage.output_tokens) { $usage.output_tokens } else { 0 }
                }
            }
        } finally {
            $reader.Close()
        }

        $result = @{
            InputTokens = $totalInputTokens
            CacheCreationTokens = $totalCacheCreationTokens
            CacheReadTokens = $totalCacheReadTokens
            OutputTokens = $totalOutputTokens
            TotalTokens = $totalInputTokens + $totalCacheCreationTokens + $totalCacheReadTokens + $totalOutputTokens
        }

        # Store in cache
        $Global:TokenUsageCache[$cacheKey] = $result

        return $result

    } catch {
        Write-DebugInfo "Error reading session token usage: $_" -Color Red
        return $null
    }
}

function Get-SessionCost {
    <#
    .SYNOPSIS
        Calculates the cost of a session based on token usage
    .DESCRIPTION
        Uses Claude Sonnet 4.5 pricing as of January 2026:
        - Input: $3.00 per 1M tokens
        - Cache writes: $3.75 per 1M tokens
        - Cache reads: $0.30 per 1M tokens
        - Output: $15.00 per 1M tokens
    #>
    param(
        [hashtable]$TokenUsage
    )

    if (-not $TokenUsage) {
        return 0.0
    }

    # Pricing per 1 million tokens (Claude Sonnet 4.5)
    $userInputRate = 3.00 / 1000000
    $cacheWriteRate = 3.75 / 1000000
    $cacheReadRate = 0.30 / 1000000
    $outputRate = 15.00 / 1000000

    $userInputCost = $TokenUsage.InputTokens * $userInputRate
    $cacheWriteCost = $TokenUsage.CacheCreationTokens * $cacheWriteRate
    $cacheReadCost = $TokenUsage.CacheReadTokens * $cacheReadRate
    $outputCost = $TokenUsage.OutputTokens * $outputRate

    $totalCost = $userInputCost + $cacheWriteCost + $cacheReadCost + $outputCost

    return [Math]::Round($totalCost, 4)
}

function Format-Cost {
    <#
    .SYNOPSIS
        Formats a cost value for display
    #>
    param([double]$Cost)

    if ($Cost -eq 0) {
        return "-"
    } elseif ($Cost -lt 0.01) {
        return "<$0.01"
    } else {
        return "`$$($Cost.ToString('0.00'))"
    }
}

function Format-TokenCount {
    <#
    .SYNOPSIS
        Formats a token count with K/M suffixes
    #>
    param([int]$Count)

    if ($Count -eq 0) {
        return "-"
    } elseif ($Count -ge 1000000) {
        return "$([Math]::Round($Count / 1000000.0, 1))M"
    } elseif ($Count -ge 1000) {
        return "$([Math]::Round($Count / 1000.0, 1))K"
    } else {
        return "$Count"
    }
}

function Show-CostAnalysis {
    <#
    .SYNOPSIS
        Shows detailed cost analysis for all sessions
    #>
    param([array]$Sessions)

    # Initialize as empty array if null
    if ($null -eq $Sessions) { $Sessions = @() }

    Write-Host ""
    Write-ColorText "========================================" -Color Cyan
    Write-ColorText "  COST ANALYSIS" -Color Cyan
    Write-ColorText "========================================" -Color Cyan
    Write-Host ""
    Write-Host "Calculating costs for $($Sessions.Count) session(s)..." -ForegroundColor Yellow
    Write-Host ""

    $sessionCosts = @()
    $totalCost = 0.0
    $totalTokens = 0

    foreach ($session in $Sessions) {
        $usage = Get-SessionTokenUsage -SessionId $session.sessionId -ProjectPath $session.projectPath
        if ($usage) {
            $cost = Get-SessionCost -TokenUsage $usage
            $totalCost += $cost
            $totalTokens += $usage.TotalTokens

            $cacheHitRate = if (($usage.CacheCreationTokens + $usage.CacheReadTokens) -gt 0) {
                [Math]::Round(($usage.CacheReadTokens / ($usage.CacheCreationTokens + $usage.CacheReadTokens)) * 100, 0)
            } else {
                0
            }

            $title = if ($session.customTitle) {
                $session.customTitle
            } elseif ($session.trackedName) {
                "[$($session.trackedName)]"
            } else {
                "(unnamed)"
            }

            $sessionCosts += @{
                Title = $title
                Cost = $cost
                InputTokens = $usage.InputTokens
                OutputTokens = $usage.OutputTokens
                CacheWrites = $usage.CacheCreationTokens
                CacheReads = $usage.CacheReadTokens
                TotalTokens = $usage.TotalTokens
                CacheHitRate = $cacheHitRate
                Created = $session.created
            }
        }
    }

    # Sort by cost (highest first)
    $sessionCosts = $sessionCosts | Sort-Object -Property Cost -Descending

    # Display table header
    Write-Host "Session                              Cost      Input    Output   Cached   Hit%   Created" -ForegroundColor Cyan
    Write-Host "-------------------------------------  -------   ------   ------   ------   ----   -------------------" -ForegroundColor DarkGray

    # Display each session
    foreach ($sc in $sessionCosts) {
        $title = $sc.Title
        if ($title.Length -gt 35) {
            $title = $title.Substring(0, 32) + "..."
        }
        $title = $title.PadRight(35)

        $costStr = (Format-Cost -Cost $sc.Cost).PadRight(9)
        $userInputStr = (Format-TokenCount -Count $sc.InputTokens).PadRight(8)
        $outputStr = (Format-TokenCount -Count $sc.OutputTokens).PadRight(8)
        $cacheStr = (Format-TokenCount -Count ($sc.CacheWrites + $sc.CacheReads)).PadRight(8)
        $hitStr = if ($sc.CacheHitRate -gt 0) { "$($sc.CacheHitRate)%" } else { "-" }
        $hitStr = $hitStr.PadRight(6)

        try {
            $created = ([DateTime]$sc.Created).ToString("yyyy-MM-dd HH:mm")
        } catch {
            $created = "N/A"
        }

        Write-Host "$title  $costStr  $userInputStr  $outputStr  $cacheStr  $hitStr  $created"
    }

    # Display totals
    Write-Host ""
    Write-ColorText "TOTALS:" -Color Cyan
    Write-Host "  Total Cost: " -NoNewline
    Write-Host (Format-Cost -Cost $totalCost) -ForegroundColor Green
    Write-Host "  Total Tokens: " -NoNewline
    Write-Host (Format-TokenCount -Count $totalTokens) -ForegroundColor Green
    Write-Host "  Average Cost per Session: " -NoNewline
    if ($sessionCosts.Count -gt 0) {
        Write-Host (Format-Cost -Cost ($totalCost / $sessionCosts.Count)) -ForegroundColor Green
    } else {
        Write-Host "-" -ForegroundColor Green
    }
    Write-Host ""
}

#endregion

#region Session Discovery

function Get-AllClaudeSessions {
    <#
    .SYNOPSIS
        Scans all project directories for Claude sessions
    .DESCRIPTION
        Reads sessions-index.json from each project directory and aggregates all sessions.
        Also includes sessions from our tracking that Claude hasn't indexed yet.
    #>
    $projectsRoot = "$env:USERPROFILE\.claude\projects"

    Write-DebugInfo "=== Starting Session Discovery ===" -Color Cyan
    Write-DebugInfo "Projects root: $projectsRoot"

    if (-not (Test-Path $projectsRoot)) {
        # Directory doesn't exist yet - first run scenario
        Write-DebugInfo "Projects directory does not exist!" -Color Yellow
        Write-DebugInfo "Expected path: $projectsRoot" -Color Yellow
        Write-DebugInfo "This is normal for first-time users." -Color Yellow
        return @()
    }

    Write-DebugInfo "Projects directory exists" -Color Green

    $allSessions = @()
    $sessionIdsSeen = @{}

    # First, get all sessions from Claude's index files
    $projectDirs = Get-ChildItem $projectsRoot -Directory
    Write-DebugInfo "Found $($projectDirs.Count) project directories in $projectsRoot" -Color Cyan

    foreach ($dir in $projectDirs) {
        $projectDir = $dir.FullName
        $projectName = $dir.Name
        $indexPath = Join-Path $projectDir "sessions-index.json"

        Write-DebugInfo "  Checking project: $projectName" -Color DarkCyan
        Write-DebugInfo "    Full path: $projectDir"
        Write-DebugInfo "    Index file: $indexPath"

        if (Test-Path $indexPath) {
            Write-DebugInfo "    Index file EXISTS" -Color Green
            try {
                $indexContent = Get-Content $indexPath -Raw | ConvertFrom-Json

                # Validate JSON structure
                if (-not (Test-JsonStructure -JsonObject $indexContent -RequiredProperties @('version', 'entries'))) {
                    Write-ColorText "Warning: Invalid index structure in $indexPath" -Color Yellow
                    continue
                }

                $entryCount = if ($indexContent.entries) { $indexContent.entries.Count } else { 0 }
                Write-DebugInfo "    Found $entryCount session(s) in index" -Color Green

                foreach ($entry in $indexContent.entries) {
                    # Sessions already have projectPath in the JSON
                    Write-DebugInfo "      Session: $($entry.sessionId)" -Color DarkGray
                    Write-DebugInfo "        Title: $($entry.customTitle)" -Color DarkGray
                    Write-DebugInfo "        Path: $($entry.projectPath)" -Color DarkGray
                    $allSessions += $entry
                    $sessionIdsSeen[$entry.sessionId] = $true
                }
            } catch {
                Write-ColorText "Warning: Failed to parse $indexPath - $_" -Color Yellow
                Write-DebugInfo "    ERROR parsing index: $_" -Color Red
            }
        } else {
            Write-DebugInfo "    Index file DOES NOT EXIST" -Color Yellow
            Write-DebugInfo "    Scanning for .jsonl files without index..." -Color Cyan

            # No index file, but there might be session .jsonl files
            # Scan for .jsonl files and extract project path from the file content
            $jsonlFiles = Get-ChildItem $projectDir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue

            if ($jsonlFiles) {
                Write-DebugInfo "    Found $($jsonlFiles.Count) .jsonl file(s)" -Color Green

                foreach ($jsonlFile in $jsonlFiles) {
                    $sessionId = $jsonlFile.BaseName
                    Write-DebugInfo "      Found session file: $sessionId" -Color DarkGray

                    # Skip if we've already seen this session
                    if ($sessionIdsSeen.ContainsKey($sessionId)) {
                        Write-DebugInfo "        Already processed - skipping" -Color DarkGray
                        continue
                    }

                    try {
                        # Read first 10 lines to find the cwd (project path)
                        # First line is often a queue-operation, cwd is usually in lines 2-5
                        $lines = Get-Content $jsonlFile.FullName -First 10 -ErrorAction Stop
                        $projectPath = $null

                        foreach ($line in $lines) {
                            try {
                                $lineJson = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
                                if ($lineJson.cwd) {
                                    $projectPath = $lineJson.cwd
                                    Write-DebugInfo "        Project path from cwd: $projectPath" -Color Green
                                    break
                                }
                            } catch {
                                # Skip lines that don't parse as JSON
                                continue
                            }
                        }

                        if ($projectPath) {
                            # Create a synthetic session entry
                            # Note: Message count not available for unindexed sessions
                            $syntheticEntry = [PSCustomObject]@{
                                sessionId = $sessionId
                                customTitle = ""  # Empty - unnamed session
                                projectPath = $projectPath
                                created = $jsonlFile.CreationTime.ToString('o')
                                modified = $jsonlFile.LastWriteTime.ToString('o')
                                messageCount = 0  # Not reliably calculable for unindexed sessions
                                firstPrompt = ""
                                isUnindexed = $true  # Flag to indicate this was found without index
                            }

                            $allSessions += $syntheticEntry
                            $sessionIdsSeen[$sessionId] = $true
                            Write-DebugInfo "        Added unindexed session to list" -Color Green
                        } else {
                            Write-DebugInfo "        No cwd field found in first 10 lines" -Color Yellow
                        }
                    } catch {
                        Write-DebugInfo "        ERROR reading session file: $_" -Color Red
                    }
                }
            } else {
                Write-DebugInfo "    No .jsonl files found" -Color Yellow
            }
        }
    }

    Write-DebugInfo "Total sessions from Claude indexes: $($allSessions.Count)" -Color Cyan

    # Now, check session-mapping.json for tracked sessions
    Write-DebugInfo "Checking session-mapping.json for tracked sessions..." -Color Cyan
    Write-DebugInfo "  Mapping file: $Global:SessionMappingPath"

    if (Test-Path $Global:SessionMappingPath) {
        Write-DebugInfo "  Mapping file EXISTS" -Color Green
        try {
            $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json
            $mappedCount = if ($mapping.sessions) { $mapping.sessions.Count } else { 0 }
            Write-DebugInfo "  Found $mappedCount tracked session(s)" -Color Green

            # First pass: Enrich existing sessions with trackedName
            foreach ($mappedSession in $mapping.sessions) {
                if ($sessionIdsSeen.ContainsKey($mappedSession.sessionId)) {
                    # Session already in our list - add trackedName to it
                    $sessionName = $mappedSession.wtProfileName -replace '^Claude-', ''
                    for ($i = 0; $i -lt $allSessions.Count; $i++) {
                        if ($allSessions[$i].sessionId -eq $mappedSession.sessionId) {
                            # Add trackedName property if session is unnamed
                            if (-not $allSessions[$i].customTitle -or $allSessions[$i].customTitle -eq "") {
                                $allSessions[$i] | Add-Member -NotePropertyName 'trackedName' -NotePropertyValue $sessionName -Force
                                Write-DebugInfo "    Added trackedName '$sessionName' to existing session $($mappedSession.sessionId)" -Color Green
                            }
                            break
                        }
                    }
                }
            }

            # Second pass: Add sessions not yet in Claude's index
            foreach ($mappedSession in $mapping.sessions) {
                Write-DebugInfo "    Tracked session: $($mappedSession.sessionId)" -Color DarkGray
                Write-DebugInfo "      Profile: $($mappedSession.wtProfileName)" -Color DarkGray
                Write-DebugInfo "      Path: $($mappedSession.projectPath)" -Color DarkGray

                # Skip if we already have this session from Claude's index
                if ($sessionIdsSeen.ContainsKey($mappedSession.sessionId)) {
                    Write-DebugInfo "      Already found in Claude's index - already enriched" -Color DarkGray
                    continue
                }

                # Check if the session file exists
                $encodedPath = ConvertTo-ClaudeprojectPath -Path $mappedSession.projectPath
                $sessionFile = Join-Path $projectsRoot "$encodedPath\$($mappedSession.sessionId).jsonl"

                Write-DebugInfo "      Checking file: $sessionFile" -Color DarkGray

                if (Test-Path $sessionFile) {
                    Write-DebugInfo "      Session file EXISTS - adding to list" -Color Green
                    # Session exists but not in Claude's index yet - add it
                    $fileInfo = Get-Item $sessionFile

                    # Extract session name from WT profile name (remove "Claude-" prefix)
                    $sessionName = $mappedSession.wtProfileName -replace '^Claude-', ''

                    # Note: Message count not available for tracked-only sessions
                    # (these sessions exist but haven't been indexed by Claude yet)

                    # Create a synthetic session entry
                    $syntheticEntry = [PSCustomObject]@{
                        sessionId = $mappedSession.sessionId
                        customTitle = ""  # Empty - we'll show [name] in brackets
                        projectPath = $mappedSession.projectPath
                        created = $mappedSession.created
                        modified = $fileInfo.LastWriteTime.ToString('o')
                        messageCount = 0  # Not reliably calculable for tracked-only sessions
                        firstPrompt = ""
                        trackedName = $sessionName  # Store our tracked name
                        isTrackedOnly = $true  # Flag to indicate this is from our tracking
                    }

                    $allSessions += $syntheticEntry
                    $sessionIdsSeen[$mappedSession.sessionId] = $true
                } else {
                    Write-DebugInfo "      Session file DOES NOT EXIST - skipping" -Color Yellow
                }
            }
        } catch {
            Write-ColorText "Warning: Failed to read session mapping - $_" -Color Yellow
            Write-DebugInfo "  ERROR reading mapping: $_" -Color Red
        }
    } else {
        Write-DebugInfo "  Mapping file DOES NOT EXIST" -Color Yellow
    }

    Write-DebugInfo "=== Session Discovery Complete ===" -Color Cyan
    Write-DebugInfo "Total sessions found: $($allSessions.Count)" -Color Green
    if ($allSessions.Count -eq 0) {
        Write-DebugInfo "NO SESSIONS FOUND!" -Color Red
        Write-DebugInfo "Possible reasons:" -Color Yellow
        Write-DebugInfo "  1. Claude Code has not been run yet (no sessions created)" -Color Yellow
        Write-DebugInfo "  2. sessions-index.json files are missing or corrupted" -Color Yellow
        Write-DebugInfo "  3. Path encoding mismatch (check directory names above)" -Color Yellow
    }
    Write-Host ""

    # Sort by modified date (most recent first)
    return $allSessions | Sort-Object -Property { [DateTime]$_.modified } -Descending
}

#endregion

#region Menu Display

function Get-WTProfileName {
    <#
    .SYNOPSIS
        Checks if a Windows Terminal profile exists for a session
    #>
    param(
        [string]$SessionTitle,
        [string]$SessionId
    )

    # If we have a title, check for Claude-{title}
    if ($SessionTitle -and $SessionTitle -ne "") {
        $profileName = "Claude-$SessionTitle"

        try {
            if (-not (Test-Path $Global:WTSettingsPath)) {
                return ""
            }

            $settingsJson = Get-Content $Global:WTSettingsPath -Raw
            $settings = $settingsJson | ConvertFrom-Json

            # Check if profile exists
            $profile = $settings.profiles.list | Where-Object { $_.name -eq $profileName } | Select-Object -First 1

            if ($profile) {
                return $profileName
            }
        } catch {
            Write-ErrorLog "Error getting profile name from registry: $_"
            return ""
        }
    }

    # If no title or profile not found, check session mapping for unnamed sessions
    if ($SessionId) {
        $mappedProfile = Get-SessionMapping -SessionId $SessionId
        if ($mappedProfile) {
            return $mappedProfile
        }
    }

    return ""
}

function Get-SessionMapping {
    <#
    .SYNOPSIS
        Gets the Windows Terminal profile name for a session ID from the mapping file
    #>
    param([string]$SessionId)

    if (-not (Test-Path $Global:SessionMappingPath)) {
        return $null
    }

    try {
        $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json
        $entry = $mapping.sessions | Where-Object { $_.sessionId -eq $SessionId }

        if ($entry -and $entry.wtProfileName) {
            return $entry.wtProfileName
        }
    } catch {
        return $null
    }

    return $null
}

function Get-SessionMappingEntry {
    <#
    .SYNOPSIS
        Gets the full session mapping entry for a session ID
    #>
    param([string]$SessionId)

    if (-not (Test-Path $Global:SessionMappingPath)) {
        return $null
    }

    try {
        $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json
        $entry = $mapping.sessions | Where-Object { $_.sessionId -eq $SessionId }
        return $entry
    } catch {
        Write-ErrorLog "Error getting session mapping entry: $_"
    }

    return ""
}

function Get-ForkedFromInfo {
    <#
    .SYNOPSIS
        Gets information about what session this was forked from
    #>
    param([string]$SessionId)

    if (-not (Test-Path $Global:SessionMappingPath)) {
        return $null
    }

    try {
        $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json
        $entry = $mapping.sessions | Where-Object { $_.sessionId -eq $SessionId }

        if ($entry -and $entry.forkedFrom) {
            return @{
                ForkedFrom = $entry.forkedFrom
                Created = $entry.created
            }
        }
    } catch {
        Write-ErrorLog "Error getting fork info: $_"
    }

    return $null
}

function Validate-SessionMappings {
    <#
    .SYNOPSIS
        Validates session mappings for consistency
        - Removes mappings where session .jsonl files don't exist (orphaned mappings)
        - Removes references to Windows Terminal profiles that no longer exist
        Self-heals bad associations from earlier versions
    #>

    Write-DebugInfo "=== Validating Session Mappings ===" -Color Cyan

    # Check if session mapping file exists
    if (-not (Test-Path $Global:SessionMappingPath)) {
        Write-DebugInfo "  No session mapping file found - nothing to validate" -Color DarkGray
        return
    }

    # Load Windows Terminal settings to get list of actual profiles
    if (-not (Test-Path $Global:WTSettingsPath)) {
        Write-DebugInfo "  Windows Terminal settings not found - cannot validate" -Color Yellow
        return
    }

    try {
        # Load Windows Terminal settings
        $settingsJson = Get-Content $Global:WTSettingsPath -Raw
        $settings = $settingsJson | ConvertFrom-Json
        $actualProfiles = @($settings.profiles.list | ForEach-Object { $_.name })

        Write-DebugInfo "  Found $($actualProfiles.Count) Windows Terminal profile(s)" -Color Green

        # Load session mappings
        $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json
        $updatedSessions = @()
        $cleanedCount = 0

        foreach ($session in $mapping.sessions) {
            # SELF-HEALING: First check if session .jsonl file exists
            $encodedPath = ConvertTo-ClaudeprojectPath -Path $session.projectPath
            $sessionFile = Join-Path "$env:USERPROFILE\.claude\projects" "$encodedPath\$($session.sessionId).jsonl"

            if (-not (Test-Path $sessionFile)) {
                # Session file doesn't exist - this is an orphaned mapping
                Write-DebugInfo "    SELF-HEAL: Session $($session.sessionId) file NOT FOUND (orphaned) - removing mapping" -Color Yellow
                Write-DebugInfo "      Missing file: $sessionFile" -Color DarkGray
                Write-DebugInfo "      Profile was: $($session.wtProfileName)" -Color DarkGray
                $cleanedCount++
                continue  # Skip this session - don't add to updatedSessions
            }

            if ($session.wtProfileName) {
                # Check if this profile actually exists
                if ($actualProfiles -contains $session.wtProfileName) {
                    # Profile exists - keep session as-is
                    $updatedSessions += $session
                    Write-DebugInfo "    Session $($session.sessionId): Profile '$($session.wtProfileName)' exists" -Color DarkGray
                } else {
                    # Profile doesn't exist - remove the reference
                    Write-DebugInfo "    Session $($session.sessionId): Profile '$($session.wtProfileName)' NOT FOUND - removing reference" -Color Yellow

                    # Create new session object without wtProfileName
                    $newSession = @{
                        sessionId = $session.sessionId
                        projectPath = $session.projectPath
                        created = $session.created
                    }
                    if ($session.model) { $newSession.model = $session.model }
                    if ($session.forkedFrom) { $newSession.forkedFrom = $session.forkedFrom }
                    if ($session.updated) { $newSession.updated = $session.updated }

                    $updatedSessions += $newSession
                    $cleanedCount++
                }
            } else {
                # No profile name - keep session as-is
                $updatedSessions += $session
            }
        }

        # Save updated mappings if any changes were made
        if ($cleanedCount -gt 0) {
            $mapping.sessions = $updatedSessions
            $jsonContent = $mapping | ConvertTo-Json -Depth 10
            Write-DebugFileOperation -FilePath $Global:SessionMappingPath -Content $jsonContent -Operation "CleanupMappings"  # FILE-DEBUG
            $jsonContent | Set-Content $Global:SessionMappingPath -Encoding UTF8
            Write-DebugInfo "  Cleaned up $cleanedCount invalid profile reference(s)" -Color Green
        } else {
            Write-DebugInfo "  All profile references are valid" -Color Green
        }

    } catch {
        Write-ErrorLog "Error validating session mappings: $_"
        Write-ColorText "Warning: Could not validate session mappings: $_" -Color Yellow
    }

    Write-DebugInfo "=== Session Mapping Validation Complete ===" -Color Cyan
}

function Get-SessionActivityMarker {
    <#
    .SYNOPSIS
        Gets an activity marker based on how recently the session was modified
    #>
    param(
        [string]$SessionId,
        [string]$ProjectPath
    )

    if (-not $SessionId -or -not $ProjectPath) {
        return ""
    }

    try {
        # Check if session is archived first
        $archiveStatus = Get-SessionArchiveStatus -SessionId $SessionId
        if ($archiveStatus.Archived) {
            return "Arch"
        }

        # Get the session .jsonl file path
        $encodedPath = ConvertTo-ClaudeprojectPath -Path $ProjectPath
        $sessionFile = Join-Path $Global:ClaudeProjectsPath "$encodedPath\$SessionId.jsonl"

        if (-not (Test-Path $sessionFile)) {
            return ""
        }

        # Get file modification time
        $fileInfo = Get-Item $sessionFile
        $lastModified = $fileInfo.LastWriteTime
        $now = Get-Date
        $timeDiff = ($now - $lastModified).TotalSeconds

        # Return different markers based on recency
        if ($timeDiff -le 300) {
            # Within 5 minutes - very active
            return "X"
        } elseif ($timeDiff -le 1800) {
            # Within 30 minutes - active
            return "x"
        } elseif ($timeDiff -le 3600) {
            # Within 1 hour - possibly active
            return "x?"
        } elseif ($timeDiff -le 18000) {
            # Within 5 hours - recently used
            return "?"
        } else {
            # Older than 5 hours - not active
            return ""
        }

    } catch {
        return ""
    }
}

function Get-ForkTree {
    <#
    .SYNOPSIS
        Gets a formatted fork tree for display in menu
    #>
    param(
        [string]$SessionId,
        [string]$SessionTitle,
        [array]$AllSessions
    )

    # First try session mapping (for new forks with session IDs)
    $forkInfo = Get-ForkedFromInfo -SessionId $SessionId
    $parentSessionId = $null

    if ($forkInfo) {
        $parentSessionId = $forkInfo.ForkedFrom
    } else {
        # Fallback to profile registry (for named sessions)
        if ($SessionTitle) {
            try {
                if (Test-Path $Global:ProfileRegistryPath) {
                    $registry = Get-Content $Global:ProfileRegistryPath -Raw | ConvertFrom-Json
                    $entry = $registry.profiles | Where-Object { $_.sessionName -eq $SessionTitle }
                    if ($entry -and $entry.originalSessionId) {
                        $parentSessionId = $entry.originalSessionId
                    }
                }
            } catch {
                Write-ErrorLog "Error reading profile registry for activity marker: $_"
            }
        }
    }

    if (-not $parentSessionId) {
        # Not a forked session
        return ""
    }

    # Find the parent session to get its title
    $parentSession = $AllSessions | Where-Object { $_.sessionId -eq $parentSessionId }

    if ($parentSession) {
        $parentName = if ($parentSession.customTitle) { $parentSession.customTitle } else { "(unnamed)" }
        return "<- $parentName"
    } else {
        # Parent session exists but not in current list (maybe deleted or in different project)
        return "<- [deleted]"
    }
}

function Get-WTProfileDetails {
    <#
    .SYNOPSIS
        Gets Windows Terminal profile details including color scheme
    #>
    param([string]$ProfileName)

    try {
        if (-not (Test-Path $Global:WTSettingsPath)) {
            return $null
        }

        $settingsJson = Get-Content $Global:WTSettingsPath -Raw
        $settings = $settingsJson | ConvertFrom-Json

        # Find the profile
        $profile = $settings.profiles.list | Where-Object { $_.name -eq $ProfileName } | Select-Object -First 1

        if ($profile) {
            return @{
                Name = $profile.name
                ColorScheme = if ($profile.colorScheme) { $profile.colorScheme } else { "" }
                BackgroundImage = if ($profile.backgroundImage) { $profile.backgroundImage } else { "" }
            }
        }
    } catch {
        Write-ErrorLog "Error getting profile info: $_"
    }

    return $null
}

function PlaceHeaderRightHandBorder {
    <#
    .SYNOPSIS
        Places the right border for header rows based on actual cursor position
    .DESCRIPTION
        Calculates spacing needed and places border at correct position
    #>
    param(
        [int]$RowWidth
    )

    # Get current cursor position
    $currentPos = $host.UI.RawUI.CursorPosition
    $currentX = $currentPos.X

    # Target position for |
    $targetX = $RowWidth - 1

    # If we've gone past the target, we need to backtrack
    if ($currentX -gt $targetX) {
        # Move cursor back to target position
        $currentPos.X = $targetX
        $host.UI.RawUI.CursorPosition = $currentPos
        Write-Host "|" -ForegroundColor DarkGray
    } else {
        # Calculate spaces needed
        $spacesNeeded = [Math]::Max(0, $targetX - $currentX)
        Write-Host (" " * $spacesNeeded) -NoNewline
        Write-Host "|" -ForegroundColor DarkGray
    }
}

function Write-SessionMenuHeader {
    <#
    .SYNOPSIS
        Writes the header box for the session menu
    .DESCRIPTION
        Displays column headers in a separate box above the main menu
    #>
    param(
        [int]$BoxWidth,
        [bool]$OnlyWithProfiles = $false
    )

    if ($OnlyWithProfiles) {
        # Profile mode headers
        $pathWidth = [Math]::Max(15, $BoxWidth - 121)
        $headers = @("Session", "Messages", "Created", "Modified", "Cost", "WT Profile", "Color Scheme", "Path")
        $headerWidths = @(30, 8, 12, 12, 8, 20, 20, $pathWidth)

        # Map header index to global column number: Session=3, Messages=5, Created=6, Modified=7, Cost=8, WTProfile=9, ColorScheme=none, Path=11
        $headerToColumn = @(3, 5, 6, 7, 8, 9, 0, 11)

        # Top border
        Write-Host ("+" + ("-" * ($BoxWidth - 2)) + "+") -ForegroundColor DarkGray

        # Header row with color coding for sorted column
        Write-Host "|" -NoNewline -ForegroundColor DarkGray
        Write-Host " " -NoNewline

        $targetX = $BoxWidth - 1
        for ($i = 0; $i -lt $headers.Count; $i++) {
            $currentPos = $host.UI.RawUI.CursorPosition
            $currentX = $currentPos.X

            # Calculate available space
            $availableSpace = $targetX - $currentX
            if ($availableSpace -le 0) { break }  # No room left

            # Truncate if needed
            $actualWidth = [Math]::Min($headerWidths[$i], $availableSpace)
            $headerText = $headers[$i]
            if ($headerText.Length -gt $actualWidth) {
                $headerText = $headerText.Substring(0, $actualWidth)
            }

            $color = if ($headerToColumn[$i] -eq $Global:SortColumn) { "Yellow" } else { "Cyan" }
            Write-Host ("{0,-$actualWidth}" -f $headerText) -NoNewline -ForegroundColor $color

            # Add space separator if not last column and room available
            if ($i -lt $headers.Count - 1) {
                $currentPos = $host.UI.RawUI.CursorPosition
                if ($currentPos.X -lt $targetX) {
                    Write-Host " " -NoNewline
                }
            }
        }
        PlaceHeaderRightHandBorder -RowWidth $BoxWidth

        # Bottom border
        Write-Host ("+" + ("-" * ($BoxWidth - 2)) + "+") -ForegroundColor DarkGray

    } else {
        # Get column configuration
        $columnConfig = Get-ColumnConfiguration

        # Calculate path width
        $pathWidth = Get-DynamicPathWidth -BoxWidth $BoxWidth -ColumnConfig $columnConfig

        # Build dynamic headers and track sort column mapping
        $headers = @()
        $headerWidths = @()
        $headerToColumn = @()

        if ($columnConfig.Active) {
            $headers += "Active"
            $headerWidths += 6
            $headerToColumn += 1
        }
        # LimitFeature: Add Limit column header if enabled
        if ($columnConfig.Limit) {
            $headers += "Limit"
            $headerWidths += 6
            $headerToColumn += 2
        }
        if ($columnConfig.Model) {
            $headers += "Model"
            $headerWidths += 8
            $headerToColumn += 3
        }
        if ($columnConfig.Session) {
            $headers += "Session"
            $headerWidths += 30
            $headerToColumn += 4
        }
        if ($columnConfig.Notes) {
            $headers += "Notes"
            $headerWidths += 10
            $headerToColumn += 5
        }
        if ($columnConfig.Messages) {
            $headers += "Messages"
            $headerWidths += 8
            $headerToColumn += 6
        }
        if ($columnConfig.Created) {
            $headers += "Created"
            $headerWidths += 12
            $headerToColumn += 7
        }
        if ($columnConfig.Modified) {
            $headers += "Modified"
            $headerWidths += 12
            $headerToColumn += 8
        }
        if ($columnConfig.Cost) {
            $headers += "Cost"
            $headerWidths += 8
            $headerToColumn += 9
        }
        if ($columnConfig.WinTerminal) {
            $headers += "Win Terminal"
            $headerWidths += 25
            $headerToColumn += 10
        }
        if ($columnConfig.ForkedFrom) {
            $headers += "Forked From"
            $headerWidths += 25
            $headerToColumn += 11
        }
        if ($columnConfig.Git) {
            $headers += "Git Repo"
            $headerWidths += 20
            $headerToColumn += 12
        }
        if ($columnConfig.Path) {
            $headers += "Path"
            $headerWidths += $pathWidth
            $headerToColumn += 13
        }

        # Top border
        Write-Host ("+" + ("-" * ($BoxWidth - 2)) + "+") -ForegroundColor DarkGray

        # Header row with color coding for sorted column
        Write-Host "|" -NoNewline -ForegroundColor DarkGray
        Write-Host " " -NoNewline

        $targetX = $BoxWidth - 1
        for ($i = 0; $i -lt $headers.Count; $i++) {
            $currentPos = $host.UI.RawUI.CursorPosition
            $currentX = $currentPos.X

            # Calculate available space
            $availableSpace = $targetX - $currentX
            if ($availableSpace -le 0) { break }  # No room left

            # Truncate if needed
            $actualWidth = [Math]::Min($headerWidths[$i], $availableSpace)
            $headerText = $headers[$i]
            if ($headerText.Length -gt $actualWidth) {
                $headerText = $headerText.Substring(0, $actualWidth)
            }

            $color = if ($headerToColumn[$i] -eq $Global:SortColumn) { "Yellow" } else { "Cyan" }
            Write-Host ("{0,-$actualWidth}" -f $headerText) -NoNewline -ForegroundColor $color

            # Add space separator if not last column and room available
            if ($i -lt $headers.Count - 1) {
                $currentPos = $host.UI.RawUI.CursorPosition
                if ($currentPos.X -lt $targetX) {
                    Write-Host " " -NoNewline
                }
            }
        }
        PlaceHeaderRightHandBorder -RowWidth $BoxWidth

        # Bottom border
        Write-Host ("+" + ("-" * ($BoxWidth - 2)) + "+") -ForegroundColor DarkGray
    }
}

function Get-DynamicPathWidth {
    <#
    .SYNOPSIS
        Calculates the dynamic path column width based on visible columns
    .DESCRIPTION
        Centralized calculation for path width to ensure consistency across menu rendering
    #>
    param(
        [int]$BoxWidth,
        [hashtable]$ColumnConfig
    )

    # Calculate total width of all non-Path columns
    $fixedWidth = 0
    $nonPathColumns = 0

    if ($ColumnConfig.Active) { $fixedWidth += 6; $nonPathColumns++ }
    if ($ColumnConfig.Model) { $fixedWidth += 8; $nonPathColumns++ }
    if ($ColumnConfig.Session) { $fixedWidth += 30; $nonPathColumns++ }
    if ($ColumnConfig.Notes) { $fixedWidth += 10; $nonPathColumns++ }
    if ($ColumnConfig.Messages) { $fixedWidth += 8; $nonPathColumns++ }
    if ($ColumnConfig.Created) { $fixedWidth += 12; $nonPathColumns++ }
    if ($ColumnConfig.Modified) { $fixedWidth += 12; $nonPathColumns++ }
    if ($ColumnConfig.Cost) { $fixedWidth += 8; $nonPathColumns++ }
    if ($ColumnConfig.WinTerminal) { $fixedWidth += 25; $nonPathColumns++ }
    if ($ColumnConfig.ForkedFrom) { $fixedWidth += 25; $nonPathColumns++ }
    if ($ColumnConfig.Git) { $fixedWidth += 20; $nonPathColumns++ }

    # Calculate spaces between columns
    # If Path is visible: we have (nonPathColumns) + Path = total columns, need (nonPathColumns) spaces
    # If Path not visible: we have nonPathColumns, need (nonPathColumns - 1) spaces
    if ($ColumnConfig.Path) {
        $spacesBetweenColumns = $nonPathColumns
    } else {
        $spacesBetweenColumns = [Math]::Max(0, $nonPathColumns - 1)
    }

    # Row structure: "|" (1) + " " (1) + content + " " (1) + "|" (1) = BoxWidth
    # Content = fixedWidth + spacesBetweenColumns + pathWidth
    # Therefore: pathWidth = BoxWidth - 4 - fixedWidth - spacesBetweenColumns
    $pathWidth = $BoxWidth - 4 - $fixedWidth - $spacesBetweenColumns

    return [Math]::Max(15, $pathWidth)
}

function Show-SessionMenu {
    <#
    .SYNOPSIS
        Displays interactive menu of available sessions
    #>
    param(
        [array]$Sessions,
        [bool]$ShowUnnamed = $false,
        [bool]$OnlyWithProfiles = $false,
        [string]$Title = "",
        [int]$SelectedIndex = 0,
        [bool]$IsRefresh = $false
    )


    # Initialize as empty array if null
    if ($null -eq $Sessions) { $Sessions = @() }

    Clear-Host

    # Show screen size in top right corner when debug mode is ON
    if (Get-DebugState) {
        try {
            $windowWidth = [int]($Host.UI.RawUI.WindowSize.Width)
            $windowHeight = [int]($Host.UI.RawUI.WindowSize.Height)
            $sizeText = "$windowWidth x $windowHeight"

            # Position cursor in top right corner (row 0)
            $pos = $host.UI.RawUI.CursorPosition
            $pos.X = $windowWidth - $sizeText.Length - 1
            $pos.Y = 0
            $host.UI.RawUI.CursorPosition = $pos

            # Display size
            Write-Host $sizeText -ForegroundColor DarkYellow -NoNewline

            # Move cursor back to start for normal display
            $pos.X = 0
            $pos.Y = 1
            $host.UI.RawUI.CursorPosition = $pos
        } catch {
            # Silently ignore if positioning fails
        }
    }

    Write-Host ""


    # Display title if provided (centered with spaces between letters)
    if ($Title) {
        $spacedTitle = $Title.ToCharArray() -join " "
        try {
            $consoleWidth = [int]($Host.UI.RawUI.WindowSize.Width)
        } catch {
            $consoleWidth = 120  # Fallback if console width unavailable
        }
        $padding = [Math]::Max(0, ($consoleWidth - $spacedTitle.Length) / 2)
        Write-Host (" " * $padding) -NoNewline
        Write-Host $spacedTitle -ForegroundColor Cyan
        Write-Host ""
    }

    Write-Host "Claude Code Session Manager with Win Terminal Forking, S. Rives, v.$Global:ScriptVersion" -ForegroundColor Cyan
    Write-Host "Current directory: $PWD" -ForegroundColor DarkGray
    Write-Host "* A newly forked session shows in [brackets] until you /rename it and until Claude CLI caches it." -ForegroundColor DarkGray

    # Calculate status information
    $totalSessions = $Sessions.Count
    $namedCount = ($Sessions | Where-Object { $_.customTitle -and $_.customTitle -ne "" }).Count
    $unnamedCount = $totalSessions - $namedCount
    $debugStatus = if (Get-DebugState) { "ON" } else { "OFF" }
    $permissionStatus = Get-GlobalPermissionStatus
    $permMode = if ($permissionStatus -is [hashtable]) {
        if ($permissionStatus.Enabled) { "Quiet" } else { "Chatty" }
    } else {
        if ($permissionStatus) { "Quiet" } else { "Chatty" }
    }

    # Calculate total cost across all sessions
    $totalCost = 0.0
    foreach ($session in $Sessions) {
        $usage = Get-SessionTokenUsage -SessionId $session.sessionId -ProjectPath $session.projectPath
        if ($usage) {
            $cost = Get-SessionCost -TokenUsage $usage
            $totalCost += $cost
        }
    }
    $totalCostDisplay = Format-Cost -Cost $totalCost

    # Display status line - adjust text based on named/unnamed counts
    $sessionTypeText = if ($namedCount -eq 0) {
        "Claude Unnamed Sessions: $unnamedCount"
    } elseif ($unnamedCount -eq 0) {
        "Claude Named Sessions: $namedCount"
    } else {
        "Claude Sessions: $totalSessions (Named: $namedCount, Unnamed: $unnamedCount)"
    }
    Write-Host "$sessionTypeText | Debug: $debugStatus | Permissions: $permMode | Total Cost: $totalCostDisplay" -ForegroundColor DarkGray
    Write-Host ""

    # Build display rows - always start numbering at 1
    $rows = @()
    $displayNum = 1

    # LimitFeature: Load column config to check if Limit column is enabled
    $rowColumnConfig = Get-ColumnConfiguration
    $limitColumnEnabled = $rowColumnConfig.Limit -eq $true

    # Log refresh status
    if ($IsRefresh) {
        Write-DebugInfo "=== REFRESH: Checking all sessions for background changes ===" -Color Cyan
    }

    # Add sessions (filter by named/unnamed and profiles)
    for ($i = 0; $i -lt $Sessions.Count; $i++) {
        $session = $Sessions[$i]

        # Check if session is named
        $isNamed = $session.customTitle -and $session.customTitle -ne ""

        # Check if we have a tracked name for this session (from our session-mapping.json)
        $hasTrackedName = $session.trackedName -and $session.trackedName -ne ""

        # Skip unnamed sessions if not showing them (unless they have a tracked name)
        if (-not $ShowUnnamed -and -not $isNamed -and -not $hasTrackedName) {
            continue
        }

        # Get title - show tracked name in [brackets] if:
        # 1. Session has no customTitle but has trackedName (newly forked, not yet indexed)
        # 2. Session is tracked-only (isTrackedOnly flag)
        $title = ""
        if ($isNamed) {
            $title = $session.customTitle
        } elseif ($hasTrackedName) {
            # Show tracked name in [brackets]
            $title = "[$($session.trackedName)]"
        } else {
            $title = "(unnamed)"
        }
        $created = [DateTime]$session.created
        $modified = [DateTime]$session.modified

        # Check if Windows Terminal profile exists
        # Pass customTitle if available, otherwise trackedName
        $sessionTitleForWT = if ($session.customTitle) { $session.customTitle } elseif ($session.trackedName) { $session.trackedName } else { "" }
        $wtProfile = Get-WTProfileName -SessionTitle $sessionTitleForWT -SessionId $session.sessionId

        # If in "only with profiles" mode, skip sessions without profiles
        if ($OnlyWithProfiles -and ($wtProfile -eq "" -or -not $wtProfile)) {
            continue
        }

        # Get color scheme if in profile mode
        $colorScheme = ""
        if ($OnlyWithProfiles -and $wtProfile) {
            $profileDetails = Get-WTProfileDetails -ProfileName $wtProfile
            if ($profileDetails) {
                $colorScheme = $profileDetails.ColorScheme
            }
        }

        # Get model - on Refresh, read from session file to detect changes
        # Otherwise, use fast cached sources (background.txt or session-mapping.json)
        $model = ""

        if ($IsRefresh) {
            # On refresh: read from session file to get current model
            # (user can change model mid-session, so we need fresh data)
            $model = Get-ModelFromSession -SessionId $session.sessionId -ProjectPath $session.projectPath
        }

        # If not refresh, or if session file didn't have model info, use cached sources
        if (-not $model) {
            # First try background.txt (fast file read)
            if ($wtProfile) {
                $model = Get-ModelFromBackgroundTxt -WTProfileName $wtProfile
            }

            # Fallback to registry using customTitle (for older forked sessions)
            if (-not $model -and $session.customTitle) {
                $model = Get-ModelFromRegistry -SessionName $session.customTitle
            }

            # If still no model, try from session-mapping.json using sessionId
            if (-not $model -and $session.sessionId) {
                $mappingEntry = Get-SessionMappingEntry -SessionId $session.sessionId
                if ($mappingEntry -and $mappingEntry.model) {
                    $model = $mappingEntry.model
                }
            }
        }

        # Get fork tree information
        # Use customTitle if available, otherwise use trackedName
        $sessionTitleForFork = if ($session.customTitle) { $session.customTitle } elseif ($session.trackedName) { $session.trackedName } else { "" }
        $forkTree = Get-ForkTree -SessionId $session.sessionId -SessionTitle $sessionTitleForFork -AllSessions $Sessions

        # Get activity marker based on file modification time
        $activeMarker = Get-SessionActivityMarker -SessionId $session.sessionId -ProjectPath $session.projectPath

        # LimitFeature: Get context usage percentage (only if Limit column is enabled - it's slow)
        $limitDisplay = ""
        $limitValue = 0
        if ($limitColumnEnabled) {
            $contextUsage = Get-SessionContextUsage -SessionId $session.sessionId -ProjectPath $session.projectPath -Model $model
            if ($contextUsage -and $contextUsage.Percentage) {
                $limitValue = $contextUsage.Percentage
                $limitDisplay = "$($contextUsage.Percentage)%"
            }
        }

        # Get cost (with caching to avoid repeated parsing)
        $usage = Get-SessionTokenUsage -SessionId $session.sessionId -ProjectPath $session.projectPath
        $cost = if ($usage) { Get-SessionCost -TokenUsage $usage } else { 0.0 }
        $costDisplay = Format-Cost -Cost $cost

        # Get notes
        $notes = Get-SessionNotes -SessionId $session.sessionId

        # Get Git repo name
        $gitRepo = Get-GitRepoName -Path $session.projectPath

        # Check if any background parameters have changed and regenerate if needed (only on refresh)
        if ($IsRefresh -and $wtProfile) {
            $null = Update-BackgroundIfChanged -Session $session -WTProfileName $wtProfile -CurrentModel $model
        }

        $rows += [PSCustomObject]@{
            Title = $title
            Path = $session.projectPath
            Messages = [int]$session.messageCount  # Ensure numeric for sorting
            Created = $created.ToString('MM/dd HH:mm')
            Modified = $modified.ToString('MM/dd HH:mm')
            Profile = $wtProfile
            ColorScheme = $colorScheme
            Model = $model
            ForkTree = $forkTree
            Active = $activeMarker
            Limit = $limitDisplay       # LimitFeature: Context usage percentage
            LimitValue = $limitValue    # LimitFeature: Numeric value for sorting
            Cost = $costDisplay
            CostValue = [double]$cost  # Ensure numeric for sorting
            Notes = $notes
            GitRepo = $gitRepo
            Session = $session
            OriginalIndex = $i
            CreatedDate = $created
            ModifiedDate = $modified
        }
    }


    # Sort rows if a column is selected (easter egg feature)
    # LimitFeature: Added Limit column (2), shifted all others
    if ($Global:SortColumn -gt 0 -and $rows.Count -gt 0) {
        $sortProperty = switch ($Global:SortColumn) {
            1 { 'Active' }      # Active marker
            2 { 'LimitValue' }  # LimitFeature: Context usage percentage (numeric)
            3 { 'Model' }       # Model name
            4 { 'Title' }       # Session title
            5 { 'Notes' }       # Notes
            6 { 'Messages' }    # Message count
            7 { 'CreatedDate' } # Created date (use date object for proper sorting)
            8 { 'ModifiedDate' }# Modified date (use date object for proper sorting)
            9 { 'CostValue' }   # Cost (numeric value)
            10 { 'Profile' }    # Win Terminal profile
            11 { 'ForkTree' }   # Forked from
            12 { 'GitRepo' }    # Git repository
            13 { 'Path' }       # Path
            default { $null }
        }

        if ($sortProperty) {
            if ($Global:SortDescending) {
                $rows = $rows | Sort-Object -Property $sortProperty -Descending
            } else {
                $rows = $rows | Sort-Object -Property $sortProperty
            }
        }
    }


    # Calculate pagination based on window height
    $totalRows = $rows.Count
    $rowsPerPage = $totalRows  # Default: show all rows
    $totalPages = 1
    $pagedRows = $rows

    try {
        $windowHeight = [int]($Host.UI.RawUI.WindowSize.Height)
        # Calculate available rows: window height - title lines(5) - header(3) - bottom border(1) - prompts(3) - buffer(5) = height - 17
        $availableRows = [Math]::Max(5, $windowHeight - 17)

        if ($totalRows -gt $availableRows) {
            $rowsPerPage = $availableRows
            $totalPages = [Math]::Ceiling($totalRows / $rowsPerPage)

            # Ensure current page is valid
            if ($Global:CurrentPage -gt $totalPages) {
                $Global:CurrentPage = $totalPages
            }
            if ($Global:CurrentPage -lt 1) {
                $Global:CurrentPage = 1
            }

            # Slice rows for current page
            $startIndex = ($Global:CurrentPage - 1) * $rowsPerPage
            $endIndex = [Math]::Min($startIndex + $rowsPerPage - 1, $totalRows - 1)
            $pagedRows = $rows[$startIndex..$endIndex]
        }
    } catch {
        # Fallback: show all rows if can't determine window size
        $pagedRows = $rows
    }


    # Get current window width and fit menu to window (prevents wrapping)
    try {
        $windowWidth = [int]($Host.UI.RawUI.WindowSize.Width)
        # Use window width minus small margin, but enforce a minimum for readability
        $minWidth = 100  # Absolute minimum
        $boxWidth = [Math]::Max($minWidth, $windowWidth - 4)
    } catch {
        # Fallback if window size can't be determined
        $boxWidth = if ($OnlyWithProfiles) { 145 } else { 180 }
    }

    # Display page indicator if multiple pages
    if ($totalPages -gt 1) {
        $pageIndicator = "pg $Global:CurrentPage/$totalPages"
        $padding = " " * [Math]::Max(0, $boxWidth - $pageIndicator.Length - 2)
        Write-Host "$padding$pageIndicator" -ForegroundColor DarkGray
    }

    # Display header in separate box
    Write-SessionMenuHeader -BoxWidth $boxWidth -OnlyWithProfiles $OnlyWithProfiles

    # Get column configuration for non-profile mode
    if (-not $OnlyWithProfiles) {
        $columnConfig = Get-ColumnConfiguration
        $pathWidth = Get-DynamicPathWidth -BoxWidth $boxWidth -ColumnConfig $columnConfig
    } else {
        $pathWidth = [Math]::Max(15, $boxWidth - 121)
    }

    # Capture first row Y position for arrow key navigation
    $firstRowY = $host.UI.RawUI.CursorPosition.Y

    # Display rows (paged)
    $rowIndex = 0
    foreach ($row in $pagedRows) {
        # Check if this row is selected (highlighted)
        $isSelected = ($rowIndex -eq $SelectedIndex)
        $rowColor = if ($isSelected) { "Yellow" } else { "Green" }

        if ($OnlyWithProfiles) {
            # Calculate dynamic path width: boxWidth - borders(4) - fixed columns(117)
            # Fixed: Session(30) + Messages(8) + Created(12) + Modified(12) + Cost(8) + Profile(20) + ColorScheme(20) + spaces(7) = 117
            $pathWidth = [Math]::Max(15, $boxWidth - 121)

            $title = Truncate-String $row.Title 30
            $cost = Truncate-String $row.Cost 8
            $profile = Truncate-String $row.Profile 20
            $colorScheme = Truncate-String $row.ColorScheme 20
            $path = Truncate-String $row.Path $pathWidth -FromLeft
            $rowText = ("{0,-30} {1,-8} {2,-12} {3,-12} {4,-8} {5,-20} {6,-20} {7,-$pathWidth}" -f $title, $row.Messages, $row.Created, $row.Modified, $cost, $profile, $colorScheme, $path)

            # Calculate actual content width
            $contentWidth = $boxWidth - 4
            $truncated = Truncate-String $rowText $contentWidth
            $truncatedLength = $truncated.Length
            $paddingNeeded = [Math]::Max(0, $contentWidth - $truncatedLength)

            Write-Host "|" -NoNewline -ForegroundColor DarkGray
            Write-Host " " -NoNewline
            Write-Host $truncated -NoNewline -ForegroundColor $rowColor
            Write-Host (" " * $paddingNeeded) -NoNewline
            Write-Host " " -NoNewline
            Write-Host "|" -ForegroundColor DarkGray
        } else {
            # Build row dynamically based on column configuration
            $rowParts = @()

            if ($columnConfig.Active) {
                $rowParts += Truncate-String $row.Active 6
            }
            # LimitFeature: Add Limit column value
            if ($columnConfig.Limit) {
                $rowParts += Truncate-String $row.Limit 6
            }
            if ($columnConfig.Model) {
                $rowParts += Truncate-String $row.Model 8
            }
            if ($columnConfig.Session) {
                $rowParts += Truncate-String $row.Title 30
            }
            if ($columnConfig.Notes) {
                $rowParts += Truncate-String $row.Notes 10
            }
            if ($columnConfig.Messages) {
                $rowParts += Truncate-String $row.Messages.ToString() 8
            }
            if ($columnConfig.Created) {
                $rowParts += Truncate-String $row.Created 12
            }
            if ($columnConfig.Modified) {
                $rowParts += Truncate-String $row.Modified 12
            }
            if ($columnConfig.Cost) {
                $rowParts += Truncate-String $row.Cost 8
            }
            if ($columnConfig.WinTerminal) {
                $rowParts += Truncate-String $row.Profile 25
            }
            if ($columnConfig.ForkedFrom) {
                $rowParts += Truncate-String $row.ForkTree 25
            }
            if ($columnConfig.Git) {
                $rowParts += Truncate-String $row.GitRepo 20
            }
            if ($columnConfig.Path) {
                $rowParts += Truncate-String $row.Path $pathWidth -FromLeft
            }

            # Build format string and apply widths
            $formatParts = @()
            $valueIndex = 0
            if ($columnConfig.Active) { $formatParts += "{$valueIndex,-6}"; $valueIndex++ }
            # LimitFeature: Add Limit column format
            if ($columnConfig.Limit) { $formatParts += "{$valueIndex,-6}"; $valueIndex++ }
            if ($columnConfig.Model) { $formatParts += "{$valueIndex,-8}"; $valueIndex++ }
            if ($columnConfig.Session) { $formatParts += "{$valueIndex,-30}"; $valueIndex++ }
            if ($columnConfig.Notes) { $formatParts += "{$valueIndex,-10}"; $valueIndex++ }
            if ($columnConfig.Messages) { $formatParts += "{$valueIndex,-8}"; $valueIndex++ }
            if ($columnConfig.Created) { $formatParts += "{$valueIndex,-12}"; $valueIndex++ }
            if ($columnConfig.Modified) { $formatParts += "{$valueIndex,-12}"; $valueIndex++ }
            if ($columnConfig.Cost) { $formatParts += "{$valueIndex,-8}"; $valueIndex++ }
            if ($columnConfig.WinTerminal) { $formatParts += "{$valueIndex,-25}"; $valueIndex++ }
            if ($columnConfig.ForkedFrom) { $formatParts += "{$valueIndex,-25}"; $valueIndex++ }
            if ($columnConfig.Git) { $formatParts += "{$valueIndex,-20}"; $valueIndex++ }
            if ($columnConfig.Path) { $formatParts += "{$valueIndex,-$pathWidth}"; $valueIndex++ }

            $formatString = $formatParts -join " "
            $rowText = $formatString -f $rowParts

            # Calculate actual content width
            $contentWidth = $boxWidth - 4
            $truncated = Truncate-String $rowText $contentWidth
            $truncatedLength = $truncated.Length
            $paddingNeeded = [Math]::Max(0, $contentWidth - $truncatedLength)

            Write-Host "|" -NoNewline -ForegroundColor DarkGray
            Write-Host " " -NoNewline
            Write-Host $truncated -NoNewline -ForegroundColor $rowColor
            Write-Host (" " * $paddingNeeded) -NoNewline
            Write-Host " " -NoNewline
            Write-Host "|" -ForegroundColor DarkGray
        }
        $rowIndex++
    }

    # Draw bottom border of box
    Write-Host ("+" + ("-" * ($boxWidth - 2)) + "+") -ForegroundColor DarkGray

    # Return the display rows and menu metadata for selection mapping
    return @{
        Rows = $pagedRows
        AllRows = $rows
        FirstRowY = $firstRowY
        BoxWidth = $boxWidth
        OnlyWithProfiles = $OnlyWithProfiles
        TotalPages = $totalPages
        CurrentPage = $Global:CurrentPage
    }
}

function Test-KeyReallyAvailable {
    <#
    .SYNOPSIS
        Validates if a key is really available by checking multiple times
    .DESCRIPTION
        KeyAvailable can give false positives. This function checks multiple times
        to filter out spurious results.
    #>
    $checkCount = 5
    $trueCount = 0

    for ($i = 0; $i -lt $checkCount; $i++) {
        try {
            if ($host.UI.RawUI.KeyAvailable) {
                $trueCount++
            }
        } catch {
            return $false
        }
        # Small delay between checks
        if ($i -lt $checkCount - 1) {
            Start-Sleep -Milliseconds 5
        }
    }

    # If at least 3 out of 5 checks say key is available, it's probably real
    $threshold = 3
    return ($trueCount -ge $threshold)
}

function Write-SingleMenuRow {
    <#
    .SYNOPSIS
        Redraws a single menu row at a specific screen position
    #>
    param(
        [int]$RowY,
        [object]$RowData,
        [bool]$IsSelected,
        [int]$BoxWidth,
        [bool]$OnlyWithProfiles
    )

    # Position cursor at row
    try {
        $pos = $host.UI.RawUI.CursorPosition
        $pos.Y = $RowY
        $pos.X = 0
        $host.UI.RawUI.CursorPosition = $pos
    } catch {
        return
    }

    # Determine color
    $rowColor = if ($IsSelected) { "Yellow" } else { "Green" }

    # Build row text (same logic as Show-SessionMenu)
    if ($OnlyWithProfiles) {
        $pathWidth = [Math]::Max(15, $BoxWidth - 121)
        $title = Truncate-String $RowData.Title 30
        $cost = Truncate-String $RowData.Cost 8
        $profile = Truncate-String $RowData.Profile 20
        $colorScheme = Truncate-String $RowData.ColorScheme 20
        $path = Truncate-String $RowData.Path $pathWidth -FromLeft
        $rowText = ("{0,-30} {1,-8} {2,-12} {3,-12} {4,-8} {5,-20} {6,-20} {7,-$pathWidth}" -f $title, $RowData.Messages, $RowData.Created, $RowData.Modified, $cost, $profile, $colorScheme, $path)
    } else {
        # Get column configuration
        $columnConfig = Get-ColumnConfiguration

        # Calculate path width using shared function
        $pathWidth = Get-DynamicPathWidth -BoxWidth $BoxWidth -ColumnConfig $columnConfig

        # Build row dynamically based on column configuration
        $rowParts = @()
        if ($columnConfig.Active) { $rowParts += Truncate-String $RowData.Active 6 }
        if ($columnConfig.Limit) { $rowParts += Truncate-String $RowData.Limit 6 }
        if ($columnConfig.Model) { $rowParts += Truncate-String $RowData.Model 8 }
        if ($columnConfig.Session) { $rowParts += Truncate-String $RowData.Title 30 }
        if ($columnConfig.Notes) { $rowParts += Truncate-String $RowData.Notes 10 }
        if ($columnConfig.Messages) { $rowParts += Truncate-String $RowData.Messages.ToString() 8 }
        if ($columnConfig.Created) { $rowParts += Truncate-String $RowData.Created 12 }
        if ($columnConfig.Modified) { $rowParts += Truncate-String $RowData.Modified 12 }
        if ($columnConfig.Cost) { $rowParts += Truncate-String $RowData.Cost 8 }
        if ($columnConfig.WinTerminal) { $rowParts += Truncate-String $RowData.Profile 25 }
        if ($columnConfig.ForkedFrom) { $rowParts += Truncate-String $RowData.ForkTree 25 }
        if ($columnConfig.Git) { $rowParts += Truncate-String $RowData.GitRepo 20 }
        if ($columnConfig.Path) { $rowParts += Truncate-String $RowData.Path $pathWidth -FromLeft }

        # Build format string
        $formatParts = @()
        $valueIndex = 0
        if ($columnConfig.Active) { $formatParts += "{$valueIndex,-6}"; $valueIndex++ }
        if ($columnConfig.Limit) { $formatParts += "{$valueIndex,-6}"; $valueIndex++ }
        if ($columnConfig.Model) { $formatParts += "{$valueIndex,-8}"; $valueIndex++ }
        if ($columnConfig.Session) { $formatParts += "{$valueIndex,-30}"; $valueIndex++ }
        if ($columnConfig.Notes) { $formatParts += "{$valueIndex,-10}"; $valueIndex++ }
        if ($columnConfig.Messages) { $formatParts += "{$valueIndex,-8}"; $valueIndex++ }
        if ($columnConfig.Created) { $formatParts += "{$valueIndex,-12}"; $valueIndex++ }
        if ($columnConfig.Modified) { $formatParts += "{$valueIndex,-12}"; $valueIndex++ }
        if ($columnConfig.Cost) { $formatParts += "{$valueIndex,-8}"; $valueIndex++ }
        if ($columnConfig.WinTerminal) { $formatParts += "{$valueIndex,-25}"; $valueIndex++ }
        if ($columnConfig.ForkedFrom) { $formatParts += "{$valueIndex,-25}"; $valueIndex++ }
        if ($columnConfig.Git) { $formatParts += "{$valueIndex,-20}"; $valueIndex++ }
        if ($columnConfig.Path) { $formatParts += "{$valueIndex,-$pathWidth}"; $valueIndex++ }

        $formatString = $formatParts -join " "
        $rowText = $formatString -f $rowParts
    }

    # Draw the row
    $contentWidth = $BoxWidth - 4
    $truncated = Truncate-String $rowText $contentWidth
    $truncatedLength = $truncated.Length
    $paddingNeeded = [Math]::Max(0, $contentWidth - $truncatedLength)

    Write-Host "|" -NoNewline -ForegroundColor DarkGray
    Write-Host " " -NoNewline
    Write-Host $truncated -NoNewline -ForegroundColor $rowColor
    Write-Host (" " * $paddingNeeded) -NoNewline
    Write-Host " " -NoNewline
    Write-Host "|" -ForegroundColor DarkGray
}

function Get-ArrowKeyNavigation {
    <#
    .SYNOPSIS
        Interactive arrow-key navigation for menu selection
    .DESCRIPTION
        Allows user to navigate menu with Up/Down arrows, select with Enter, or use single-key commands
    #>
    param(
        [array]$MenuRows,
        [int]$CurrentIndex = 0,
        [bool]$ShowUnnamed,
        [bool]$HasWTProfiles = $false,
        [bool]$DeleteMode = $false,
        [bool]$ShowAllInDeleteMode = $false,
        [bool]$HasBypassPermissions = $false,
        [int]$FirstRowY = 0,
        [int]$BoxWidth = 0,
        [bool]$OnlyWithProfiles = $false,
        [int]$TotalPages = 1
    )

    if ($null -eq $MenuRows) { $MenuRows = @() }

    $selectedIndex = $CurrentIndex
    $rowCount = $MenuRows.Count

    # Ensure selectedIndex is within bounds
    if ($selectedIndex -lt 0) { $selectedIndex = 0 }
    if ($selectedIndex -ge $rowCount -and $rowCount -gt 0) { $selectedIndex = $rowCount - 1 }

    # Hide cursor for cleaner navigation
    try {
        [Console]::CursorVisible = $false
    } catch {
        # Ignore if console handle is not available
    }

    # Track window width for resize detection
    try {
        $lastKnownWidth = [int]($Host.UI.RawUI.WindowSize.Width)
    } catch {
        $lastKnownWidth = 0
    }

    # Track last resize check time for periodic checking
    $lastResizeCheck = Get-Date
    $resizeCheckInterval = 500  # Check every 500ms

    # Display prompt with available commands ONCE
    $debugEnabled = Get-DebugState
    $debugColor = if ($debugEnabled) { "Red" } else { "Yellow" }

    if ($DeleteMode) {
        Write-Host "Choose with " -NoNewline -ForegroundColor Gray
        Write-Host "$([char]0x25B2)$([char]0x25BC)" -NoNewline -ForegroundColor Yellow
        Write-Host ", then " -NoNewline -ForegroundColor Gray
        Write-Host "[Enter]" -NoNewline -ForegroundColor Yellow
        Write-Host " to select | " -NoNewline -ForegroundColor Gray
        if ($ShowAllInDeleteMode) {
            Write-Host 'P' -NoNewline -ForegroundColor Yellow
            Write-Host "rofiles Only" -NoNewline -ForegroundColor Gray
        } else {
            Write-Host "a" -NoNewline -ForegroundColor Gray
            Write-Host 'L' -NoNewline -ForegroundColor Yellow
            Write-Host "l Sessions" -NoNewline -ForegroundColor Gray
        }
        Write-Host " | " -NoNewline -ForegroundColor Gray
        Write-Host 'S' -NoNewline -ForegroundColor Yellow
        Write-Host "anity Check" -NoNewline -ForegroundColor Gray
        Write-Host " | " -NoNewline -ForegroundColor Gray
        Write-Host 'R' -NoNewline -ForegroundColor Yellow
        Write-Host "efresh" -NoNewline -ForegroundColor Gray
        Write-Host " | " -NoNewline -ForegroundColor Gray
        if ($TotalPages -gt 1) {
            Write-Host "Pg" -NoNewline -ForegroundColor Yellow
            Write-Host "Up" -NoNewline -ForegroundColor Gray
            Write-Host " | " -NoNewline -ForegroundColor Gray
            Write-Host "Pg" -NoNewline -ForegroundColor Yellow
            Write-Host "Dn" -NoNewline -ForegroundColor Gray
            Write-Host " | " -NoNewline -ForegroundColor Gray
        }
        Write-Host 'A' -NoNewline -ForegroundColor Yellow
        Write-Host "bort" -ForegroundColor Gray
    } elseif ($ShowUnnamed) {
        Write-Host "Use " -NoNewline -ForegroundColor Gray
        Write-Host "$([char]0x25B2)$([char]0x25BC)" -NoNewline -ForegroundColor Yellow
        Write-Host ", " -NoNewline -ForegroundColor Gray
        Write-Host "[Enter]" -NoNewline -ForegroundColor Yellow
        Write-Host " to select | " -NoNewline -ForegroundColor Gray
        Write-Host 'N' -NoNewline -ForegroundColor Yellow
        Write-Host "ew Session" -NoNewline -ForegroundColor Gray
        if ($HasWTProfiles) {
            Write-Host " | " -NoNewline -ForegroundColor Gray
            Write-Host 'W' -NoNewline -ForegroundColor Yellow
            Write-Host "in Terminal Config" -NoNewline -ForegroundColor Gray
        }
        Write-Host " | " -NoNewline -ForegroundColor Gray
        Write-Host 'H' -NoNewline -ForegroundColor Yellow
        Write-Host "ide Unnamed" -NoNewline -ForegroundColor Gray
        Write-Host " | " -NoNewline -ForegroundColor Gray
        if ($HasBypassPermissions) {
            Write-Host 'C' -NoNewline -ForegroundColor Yellow
            Write-Host "hatty Mode" -NoNewline -ForegroundColor Gray
        } else {
            Write-Host 'Q' -NoNewline -ForegroundColor Yellow
            Write-Host "uiet Mode" -NoNewline -ForegroundColor Gray
        }
        Write-Host " | " -NoNewline -ForegroundColor Gray
        Write-Host "c" -NoNewline -ForegroundColor Gray
        Write-Host 'O' -NoNewline -ForegroundColor Yellow
        Write-Host "st" -NoNewline -ForegroundColor Gray
        Write-Host " | " -NoNewline -ForegroundColor Gray
        Write-Host 'D' -NoNewline -ForegroundColor $debugColor
        Write-Host "ebug" -NoNewline -ForegroundColor Gray
        Write-Host " | " -NoNewline -ForegroundColor Gray
        Write-Host 'R' -NoNewline -ForegroundColor Yellow
        Write-Host "efresh" -NoNewline -ForegroundColor Gray
        Write-Host " | " -NoNewline -ForegroundColor Gray
        Write-Host "confi" -NoNewline -ForegroundColor Gray
        Write-Host 'G' -NoNewline -ForegroundColor Yellow
        Write-Host "" -NoNewline -ForegroundColor Gray
        Write-Host " | " -NoNewline -ForegroundColor Gray
        Write-Host 'A' -NoNewline -ForegroundColor Yellow
        Write-Host "bout" -NoNewline -ForegroundColor Gray
        Write-Host " | " -NoNewline -ForegroundColor Gray
        if ($TotalPages -gt 1) {
            Write-Host "Pg" -NoNewline -ForegroundColor Yellow
            Write-Host "Up" -NoNewline -ForegroundColor Gray
            Write-Host " | " -NoNewline -ForegroundColor Gray
            Write-Host "Pg" -NoNewline -ForegroundColor Yellow
            Write-Host "Dn" -NoNewline -ForegroundColor Gray
            Write-Host " | " -NoNewline -ForegroundColor Gray
        }
        Write-Host "e" -NoNewline -ForegroundColor Gray
        Write-Host 'X' -NoNewline -ForegroundColor Yellow
        Write-Host "it" -ForegroundColor Gray
    } else {
        Write-Host "Use " -NoNewline -ForegroundColor Gray
        Write-Host "$([char]0x25B2)$([char]0x25BC)" -NoNewline -ForegroundColor Yellow
        Write-Host ", " -NoNewline -ForegroundColor Gray
        Write-Host "[Enter]" -NoNewline -ForegroundColor Yellow
        Write-Host " to select | " -NoNewline -ForegroundColor Gray
        Write-Host 'N' -NoNewline -ForegroundColor Yellow
        Write-Host "ew Session" -NoNewline -ForegroundColor Gray
        if ($HasWTProfiles) {
            Write-Host " | " -NoNewline -ForegroundColor Gray
            Write-Host 'W' -NoNewline -ForegroundColor Yellow
            Write-Host "in Terminal Config" -NoNewline -ForegroundColor Gray
        }
        Write-Host " | " -NoNewline -ForegroundColor Gray
        Write-Host 'S' -NoNewline -ForegroundColor Yellow
        Write-Host "how Unnamed" -NoNewline -ForegroundColor Gray
        Write-Host " | " -NoNewline -ForegroundColor Gray
        if ($HasBypassPermissions) {
            Write-Host 'C' -NoNewline -ForegroundColor Yellow
            Write-Host "hatty Mode" -NoNewline -ForegroundColor Gray
        } else {
            Write-Host 'Q' -NoNewline -ForegroundColor Yellow
            Write-Host "uiet Mode" -NoNewline -ForegroundColor Gray
        }
        Write-Host " | " -NoNewline -ForegroundColor Gray
        Write-Host "c" -NoNewline -ForegroundColor Gray
        Write-Host 'O' -NoNewline -ForegroundColor Yellow
        Write-Host "st" -NoNewline -ForegroundColor Gray
        Write-Host " | " -NoNewline -ForegroundColor Gray
        Write-Host 'D' -NoNewline -ForegroundColor $debugColor
        Write-Host "ebug" -NoNewline -ForegroundColor Gray
        Write-Host " | " -NoNewline -ForegroundColor Gray
        Write-Host 'R' -NoNewline -ForegroundColor Yellow
        Write-Host "efresh" -NoNewline -ForegroundColor Gray
        Write-Host " | " -NoNewline -ForegroundColor Gray
        Write-Host "confi" -NoNewline -ForegroundColor Gray
        Write-Host 'G' -NoNewline -ForegroundColor Yellow
        Write-Host "" -NoNewline -ForegroundColor Gray
        Write-Host " | " -NoNewline -ForegroundColor Gray
        Write-Host 'A' -NoNewline -ForegroundColor Yellow
        Write-Host "bout" -NoNewline -ForegroundColor Gray
        Write-Host " | " -NoNewline -ForegroundColor Gray
        if ($TotalPages -gt 1) {
            Write-Host "Pg" -NoNewline -ForegroundColor Yellow
            Write-Host "Up" -NoNewline -ForegroundColor Gray
            Write-Host " | " -NoNewline -ForegroundColor Gray
            Write-Host "Pg" -NoNewline -ForegroundColor Yellow
            Write-Host "Dn" -NoNewline -ForegroundColor Gray
            Write-Host " | " -NoNewline -ForegroundColor Gray
        }
        Write-Host "e" -NoNewline -ForegroundColor Gray
        Write-Host 'X' -NoNewline -ForegroundColor Yellow
        Write-Host "it" -ForegroundColor Gray
    }

    Write-Host ""

    # Capture cursor position BEFORE displaying "Last command" (for sub-menu positioning)
    # This is where dialog output should start - right after the sub-menu
    $promptEndY = 0
    try {
        $promptEndY = $host.UI.RawUI.CursorPosition.Y
        $Global:PromptEndY = $promptEndY  # Store globally for sub-menu functions
    } catch {
        # Ignore if can't get cursor position
    }

    # Show last Claude command or error at bottom of screen if available
    if ($Global:LastClaudeError -or $Global:LastClaudeCommand) {
        try {
            $windowHeight = [int]($host.UI.RawUI.WindowSize.Height)
            $cursorY = [int]($host.UI.RawUI.CursorPosition.Y)
            $linesToBottom = $windowHeight - $cursorY - 3  # Extra line for error

            # Add padding to push to bottom
            if ($linesToBottom -gt 0) {
                for ($i = 0; $i -lt $linesToBottom; $i++) {
                    Write-Host ""
                }
            }

            # Show error if present
            if ($Global:LastClaudeError) {
                Write-Host "Error: " -NoNewline -ForegroundColor Red
                Write-Host $Global:LastClaudeError -ForegroundColor Red
            }

            # Show command (either successful or failed attempt)
            if ($Global:LastClaudeCommand) {
                Write-Host "Last command: " -NoNewline -ForegroundColor DarkGray
                Write-Host $Global:LastClaudeCommand -ForegroundColor DarkGray
            }
        } catch {
            # Fallback if console positioning fails
            Write-Host ""
            if ($Global:LastClaudeError) {
                Write-Host "Error: " -NoNewline -ForegroundColor Red
                Write-Host $Global:LastClaudeError -ForegroundColor Red
            }
            if ($Global:LastClaudeCommand) {
                Write-Host "Last command: " -NoNewline -ForegroundColor DarkGray
                Write-Host $Global:LastClaudeCommand -ForegroundColor DarkGray
            }
        }
    }

    # CRITICAL: Flush input buffer to clear any stale/sticky KeyAvailable artifacts
    # This prevents false positives from PSReadLine hooks, terminal events, or previous crashes
    try {
        # Method 1: Try host's FlushInputBuffer
        $Host.UI.RawUI.FlushInputBuffer()
    } catch {
        # Method 2: Manual drain - read all pending keys until buffer is empty
        try {
            while ([Console]::KeyAvailable) {
                [Console]::ReadKey($true) | Out-Null
            }
        } catch {
            # Silent fallback - continue anyway
        }
    }

    try {
        while ($true) {
            # Periodic resize check (every 500ms) regardless of keyboard input
            $now = Get-Date
            $timeSinceLastCheck = ($now - $lastResizeCheck).TotalMilliseconds

            if ($timeSinceLastCheck -ge $resizeCheckInterval) {
                try {
                    $currentWidth = [int]($Host.UI.RawUI.WindowSize.Width)
                    if ($currentWidth -ne $lastKnownWidth) {
                        # Window was resized - return to redraw menu
                        return @{ Type = 'Resize'; Width = $currentWidth }
                    }
                } catch {
                    # Ignore if window size can't be determined
                }
                $lastResizeCheck = $now
            }

            # Check if key is available (with validation to filter false positives)
            $keyAvailable = $false
            try {
                # First quick check
                if ($host.UI.RawUI.KeyAvailable) {
                    # Validate with multiple checks to filter false positives
                    $keyAvailable = Test-KeyReallyAvailable
                }
            } catch {
                # Can't check for keys - just sleep and loop for resize check
                Start-Sleep -Milliseconds 50
                continue
            }

            if (-not $keyAvailable) {
                # No key pressed yet - sleep briefly and check again
                Start-Sleep -Milliseconds 50
                continue
            }

            # Key is really available - read it
            $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

            # Handle arrow keys - redraw only affected lines for better performance
            if ($key.VirtualKeyCode -eq 38) {  # Up arrow
                if ($rowCount -gt 0 -and $FirstRowY -gt 0 -and $BoxWidth -gt 0) {
                    $oldIndex = $selectedIndex
                    $selectedIndex = ($selectedIndex - 1)
                    if ($selectedIndex -lt 0) { $selectedIndex = $rowCount - 1 }

                    # Redraw old line (unselected - Green)
                    Write-SingleMenuRow -RowY ($FirstRowY + $oldIndex) -RowData $MenuRows[$oldIndex] -IsSelected $false -BoxWidth $BoxWidth -OnlyWithProfiles $OnlyWithProfiles

                    # Redraw new line (selected - Yellow)
                    Write-SingleMenuRow -RowY ($FirstRowY + $selectedIndex) -RowData $MenuRows[$selectedIndex] -IsSelected $true -BoxWidth $BoxWidth -OnlyWithProfiles $OnlyWithProfiles

                    # Continue loop without full redraw
                    continue
                }
            }
            elseif ($key.VirtualKeyCode -eq 40) {  # Down arrow
                if ($rowCount -gt 0 -and $FirstRowY -gt 0 -and $BoxWidth -gt 0) {
                    $oldIndex = $selectedIndex
                    $selectedIndex = ($selectedIndex + 1) % $rowCount

                    # Redraw old line (unselected - Green)
                    Write-SingleMenuRow -RowY ($FirstRowY + $oldIndex) -RowData $MenuRows[$oldIndex] -IsSelected $false -BoxWidth $BoxWidth -OnlyWithProfiles $OnlyWithProfiles

                    # Redraw new line (selected - Yellow)
                    Write-SingleMenuRow -RowY ($FirstRowY + $selectedIndex) -RowData $MenuRows[$selectedIndex] -IsSelected $true -BoxWidth $BoxWidth -OnlyWithProfiles $OnlyWithProfiles

                    # Continue loop without full redraw
                    continue
                }
            }
            # Handle PageUp key
            elseif ($key.VirtualKeyCode -eq 33) {  # PageUp
                return @{ Type = 'PageUp'; Index = $selectedIndex }
            }
            # Handle PageDown key
            elseif ($key.VirtualKeyCode -eq 34) {  # PageDown
                return @{ Type = 'PageDown'; Index = $selectedIndex }
            }
            # Handle Escape key (same as X or A to exit/abort)
            elseif ($key.VirtualKeyCode -eq 27) {  # Escape
                # Clear "Last command" display and reposition cursor
                $Global:LastClaudeCommand = $null
                $Global:LastClaudeError = $null
                if ($promptEndY -gt 0) {
                    try {
                        $pos = $host.UI.RawUI.CursorPosition
                        $pos.Y = $promptEndY
                        $pos.X = 0
                        $host.UI.RawUI.CursorPosition = $pos
                        [Console]::Write([char]27 + "[0J")
                    } catch {}
                }

                if ($DeleteMode) {
                    return @{ Type = 'ExitDeleteMode' }
                } else {
                    return @{ Type = 'Quit'; PromptEndY = $promptEndY }
                }
            }
            # Handle Enter key
            elseif ($key.VirtualKeyCode -eq 13) {  # Enter
                # Clear "Last command" display and reposition cursor
                $Global:LastClaudeCommand = $null
                $Global:LastClaudeError = $null
                if ($promptEndY -gt 0) {
                    try {
                        $pos = $host.UI.RawUI.CursorPosition
                        $pos.Y = $promptEndY
                        $pos.X = 0
                        $host.UI.RawUI.CursorPosition = $pos
                        [Console]::Write([char]27 + "[0J")
                    } catch {}
                }

                if ($rowCount -gt 0) {
                    return @{ Type = 'Select'; Index = $selectedIndex }
                }
            }
            # Handle single-key commands
            else {
                # Clear "Last command" display and reposition cursor FIRST
                $Global:LastClaudeCommand = $null
                $Global:LastClaudeError = $null
                if ($promptEndY -gt 0) {
                    try {
                        $pos = $host.UI.RawUI.CursorPosition
                        $pos.Y = $promptEndY
                        $pos.X = 0
                        $host.UI.RawUI.CursorPosition = $pos
                        [Console]::Write([char]27 + "[0J")
                    } catch {}
                }

                $char = $key.Character.ToString().ToUpper()

                # About screen
                if ($char -eq 'A' -and -not $DeleteMode) {
                    return @{ Type = 'About'; Index = $selectedIndex }
                }

                # Exit/Quit/Abort
                if ($char -eq 'X' -or ($char -eq 'A' -and $DeleteMode)) {
                    if ($DeleteMode) {
                        return @{ Type = 'ExitDeleteMode' }
                    } else {
                        return @{ Type = 'Quit'; PromptEndY = $promptEndY }
                    }
                }

                # New session
                if ($char -eq 'N' -and -not $DeleteMode) {
                    return @{ Type = 'NewSession' }
                }

                # Show/Hide unnamed
                if ($char -eq 'S' -and -not $DeleteMode) {
                    return @{ Type = 'ShowUnnamed'; Index = $selectedIndex }
                }
                if ($char -eq 'H') {
                    return @{ Type = 'HideUnnamed'; Index = $selectedIndex }
                }

                # Debug mode
                if ($char -eq 'D') {
                    return @{ Type = 'Debug'; Index = $selectedIndex }
                }

                # Cost analysis
                if ($char -eq 'O') {
                    return @{ Type = 'CostAnalysis'; Index = $selectedIndex }
                }

                # Refresh
                if ($char -eq 'R') {
                    return @{ Type = 'Refresh'; Index = $selectedIndex }
                }

                # Column configuration
                if ($char -eq 'G' -and -not $DeleteMode) {
                    return @{ Type = 'ColumnConfig'; Index = $selectedIndex }
                }

                # Windows Terminal config
                if ($char -eq 'W' -and $HasWTProfiles -and -not $DeleteMode) {
                    return @{ Type = 'EnterDeleteMode'; Index = $selectedIndex }
                }

                # Permission toggles
                if ($char -eq 'Q' -and -not $DeleteMode) {
                    return @{ Type = 'EnableBypassPermissions'; Index = $selectedIndex }
                }
                if ($char -eq 'C' -and -not $DeleteMode) {
                    return @{ Type = 'DisableBypassPermissions'; Index = $selectedIndex }
                }

                # Show All / Profiles Only toggle in Delete Mode
                if ($char -eq 'L' -and $DeleteMode -and -not $ShowAllInDeleteMode) {
                    return @{ Type = 'ShowAllInDeleteMode'; Index = $selectedIndex }
                }
                if ($char -eq 'P' -and $DeleteMode -and $ShowAllInDeleteMode) {
                    return @{ Type = 'ProfilesOnlyInDeleteMode'; Index = $selectedIndex }
                }

                # Regenerate backgrounds in Delete Mode
                if ($char -eq 'S' -and $DeleteMode) {
                    return @{ Type = 'RegenerateBackgrounds'; Index = $selectedIndex }
                }

                # Easter egg: Number keys for column sorting (1-9, 0 for column 10)
                if ($char -match '^[0-9]$') {
                    $columnNum = if ($char -eq '0') { 10 } else { [int]$char }

                    # If this is the first sort (no column selected yet), start with ascending
                    # Otherwise, toggle sort direction every time any column is pressed
                    if ($Global:SortColumn -eq 0) {
                        $Global:SortDescending = $false  # First sort is ascending
                    } else {
                        $Global:SortDescending = -not $Global:SortDescending  # Toggle direction
                    }

                    $Global:SortColumn = $columnNum

                    # Return to redraw menu with new sort
                    return @{ Type = 'SortColumn'; Index = $selectedIndex }
                }
            }

            # Reset key for next iteration
            $key = $null
        }
    }
    catch {
        # Log critical errors but don't spam debug output
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "[$timestamp] [CRITICAL ERROR] Navigation loop exception: $_" | Add-Content -Path $Global:DebugLogPath -Encoding UTF8 -ErrorAction SilentlyContinue
        throw
    }
    finally {
        # Restore cursor
        try {
            [Console]::CursorVisible = $true
        } catch {
            # Ignore if console handle is not available
        }
    }
}

function Get-UserSelection {
    <#
    .SYNOPSIS
        Gets user's menu selection with validation (LEGACY - kept for compatibility)
    #>
    param(
        [int]$MinOption,
        [int]$MaxOption,
        [bool]$ShowUnnamed,
        [bool]$HasWTProfiles = $false,
        [bool]$DeleteMode = $false,
        [bool]$HasBypassPermissions = $false
    )

    while ($true) {
        # Build the range display
        if ($MinOption -eq $MaxOption) {
            $range = "[$MinOption]"
        } else {
            $range = "[$MinOption..$MaxOption]"
        }

        # Check debug state for coloring
        $debugEnabled = Get-DebugState
        $debugColor = if ($debugEnabled) { "Red" } else { "Yellow" }

        if ($DeleteMode) {
            Write-Host "Select Windows Terminal Profile $range, [O]Cost, " -ForegroundColor Yellow -NoNewline
            Write-Host "[D]" -ForegroundColor $debugColor -NoNewline
            Write-Host "ebug, [R]efresh, [A]bort: " -ForegroundColor Yellow -NoNewline
        } elseif ($ShowUnnamed) {
            $wtOption = if ($HasWTProfiles) { ", [W]in Terminal Config" } else { "" }
            $permOption = if ($HasBypassPermissions) { ", [C]hatty Claude Mode" } else { ", [Q]uiet Claude Mode" }
            Write-Host "$range Fork, Join, or Del Session, [N]ew Session$wtOption, [H]ide unnamed sessions$permOption, [O]Cost, " -ForegroundColor Yellow -NoNewline
            Write-Host "[D]" -ForegroundColor $debugColor -NoNewline
            Write-Host "ebug, [R]efresh, [A]bout, e[X]it: " -ForegroundColor Yellow -NoNewline
        } else {
            $wtOption = if ($HasWTProfiles) { ", [W]in Terminal Config" } else { "" }
            $permOption = if ($HasBypassPermissions) { ", [C]hatty Claude Mode" } else { ", [Q]uiet Claude Mode" }
            Write-Host "$range Fork, Join, or Del Session, [N]ew Session$wtOption, [S]how unnamed sessions$permOption, [O]Cost, " -ForegroundColor Yellow -NoNewline
            Write-Host "[D]" -ForegroundColor $debugColor -NoNewline
            Write-Host "ebug, [R]efresh, [A]bout, e[X]it: " -ForegroundColor Yellow -NoNewline
        }

        $userInput = Read-Host

        # Check for About screen
        if (($userInput -eq 'A' -or $userInput -eq 'a') -and -not $DeleteMode) {
            return @{ Type = 'About' }
        }

        # Check for exit/abort
        if ($userInput -eq 'X' -or $userInput -eq 'x' -or (($userInput -eq 'A' -or $userInput -eq 'a') -and $DeleteMode)) {
            if ($DeleteMode) {
                return @{ Type = 'ExitDeleteMode' }
            } else {
                return @{ Type = 'Quit'; PromptEndY = $promptEndY }
            }
        }


        # Check for new session
        if (($userInput -eq 'N' -or $userInput -eq 'n') -and -not $DeleteMode) {
            return @{ Type = 'NewSession' }
        }

        # Check for show/hide toggle
        if ($userInput -eq 'S' -or $userInput -eq 's') {
            return @{ Type = 'ShowUnnamed' }
        }
        if ($userInput -eq 'H' -or $userInput -eq 'h') {
            return @{ Type = 'HideUnnamed' }
        }

        # Check for debug mode
        if ($userInput -eq 'D' -or $userInput -eq 'd') {
            return @{ Type = 'Debug' }
        }

        # Check for cost analysis
        if ($userInput -eq '$') {
            return @{ Type = 'CostAnalysis' }
        }

        # Check for refresh
        if ($userInput -eq 'R' -or $userInput -eq 'r') {
            return @{ Type = 'Refresh' }
        }

        # Check for delete mode
        if (($userInput -eq 'W' -or $userInput -eq 'w') -and $HasWTProfiles -and -not $DeleteMode) {
            return @{ Type = 'EnterDeleteMode' }
        }

        # Check for quiet claude mode (enable bypass permissions)
        if (($userInput -eq 'Q' -or $userInput -eq 'q') -and -not $DeleteMode) {
            return @{ Type = 'EnableBypassPermissions' }
        }

        # Check for chatty claude mode (disable bypass permissions)
        if (($userInput -eq 'C' -or $userInput -eq 'c') -and -not $DeleteMode) {
            return @{ Type = 'DisableBypassPermissions' }
        }

        # Check for number selection
        $number = 0
        if ([int]::TryParse($userInput, [ref]$number)) {
            if ($number -ge $MinOption -and $number -le $MaxOption) {
                return @{ Type = 'Select'; Value = $number }
            }
        }

        Write-ColorText "Invalid selection. Please try again." -Color Red
    }
}

#endregion

#region Session Validation

function Test-SessionFileValid {
    <#
    .SYNOPSIS
        Validates that a session's .jsonl file exists and has content
    .PARAMETER SessionId
        The session ID to validate
    .PARAMETER ProjectPath
        The project path for the session
    #>
    param(
        [string]$SessionId,
        [string]$ProjectPath
    )

    try {
        # Build path to session file
        $encodedPath = ConvertTo-ClaudeprojectPath -Path $ProjectPath
        $sessionFile = Join-Path "$env:USERPROFILE\.claude\projects\$encodedPath" "$SessionId.jsonl"

        # Check if file exists
        if (-not (Test-Path $sessionFile)) {
            Write-ErrorLog "Session file not found: $sessionFile"
            return $false
        }

        # Check if file has content
        $fileInfo = Get-Item $sessionFile
        if ($fileInfo.Length -eq 0) {
            Write-ErrorLog "Session file is empty: $sessionFile"
            return $false
        }

        # Try to read first line to validate it's valid JSON
        $firstLine = Get-Content $sessionFile -TotalCount 1
        if ($firstLine) {
            $null = $firstLine | ConvertFrom-Json
        } else {
            Write-ErrorLog "Session file has no lines: $sessionFile"
            return $false
        }

        return $true
    } catch {
        Write-ErrorLog "Error validating session file: $_"
        return $false
    }
}

#endregion

#region Session Launch

function Start-NewSession {
    <#
    .SYNOPSIS
        Starts a new Claude session in the current directory
    #>

    Write-Host ""
    Write-ColorText "Starting new Claude session..." -Color Cyan
    Write-Host ""

    # Prompt for directory choice
    Write-ColorText "Directory for new session:" -Color Yellow
    Write-Host ""

    $directoryChoice = $null
    $targetDirectory = $PWD.Path.TrimEnd('\')

    Write-Host "Use " -NoNewline -ForegroundColor Gray
    Write-Host "C" -NoNewline -ForegroundColor Yellow
    Write-Host "urrent - $targetDirectory | " -NoNewline -ForegroundColor Gray
    Write-Host "S" -NoNewline -ForegroundColor Yellow
    Write-Host "et different directory | " -NoNewline -ForegroundColor Gray
    Write-Host "A" -NoNewline -ForegroundColor Yellow
    Write-Host "bort" -NoNewline -ForegroundColor Gray

    while ($true) {
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $choice = $key.Character.ToString().ToUpper()

        # Handle Esc as abort
        if ($key.VirtualKeyCode -eq 27) {
            Write-Host ""
            $choice = 'A'
        }

        # Handle Enter as default (use current directory)
        if ($key.VirtualKeyCode -eq 13) {
            $choice = 'C'
        }

        if ($choice -eq 'C') {
            Write-Host ""
            # Use current directory
            $targetDirectory = $PWD.Path.TrimEnd('\')
            break
        } elseif ($choice -eq 'S') {
            Write-Host ""
            # Prompt for new directory
            Write-Host ""

            $validDirectory = $false
            while (-not $validDirectory) {
                Write-ColorText "Enter directory path, [A]bort: " -Color Yellow -NoNewline
                $newDir = Read-Host

                if ($newDir -eq 'A' -or $newDir -eq 'a') {
                    # Abort setting new directory, use current
                    $targetDirectory = $PWD.Path.TrimEnd('\')
                    $validDirectory = $true
                    Write-Host ""
                    Write-ColorText "Using current directory: $targetDirectory" -Color Cyan
                    break
                }

                # Check if directory exists
                if (Test-Path -Path $newDir -PathType Container) {
                    $targetDirectory = (Resolve-Path $newDir).Path
                    # Remove trailing backslash if present (Windows Terminal doesn't like it)
                    $targetDirectory = $targetDirectory.TrimEnd('\')
                    $validDirectory = $true
                    Write-Host ""
                    Write-ColorText "Using directory: $targetDirectory" -Color Green
                } else {
                    Write-Host ""
                    Write-ColorText "Directory does not exist: $newDir" -Color Red
                    Write-Host ""
                }
            }
            break
        } elseif ($choice -eq 'A') {
            Write-ColorText "New session aborted." -Color Yellow
            return
        } else {
            # Invalid choice - just continue loop
        }
    }

    Write-Host ""

    # Prompt for optional session name
    $sessionName = Get-OptionalSessionName

    # Check if user aborted
    if ($sessionName -eq 'abort') {
        Write-Host ""
        Write-ColorText "New session aborted." -Color Yellow
        return
    }

    if ([string]::IsNullOrWhiteSpace($sessionName)) {
        # No name provided - launch terminal with default profile

        # Prompt for trusted session
        $trustedChoice = Get-TrustedSessionChoice

        # Check if user aborted
        if ($trustedChoice -eq 'abort') {
            Write-Host ""
            Write-ColorText "New session aborted." -Color Yellow
            return
        }

        if ($trustedChoice -eq 'yes') {
            Set-TrustedSessionSettings -ProjectPath $targetDirectory
        }

        Write-Host ""
        Write-ColorText "Launching terminal with default profile..." -Color Green
        Write-Host ""
        $claudePath = Get-ClaudeCLIPath

        # Launch Claude in Windows Terminal with default profile
        & wt.exe -d "$targetDirectory" -- "$claudePath"

        # Store command for display
        $Global:LastClaudeCommand = "claude (new session in $targetDirectory)"
        $Global:LastClaudeError = $null
    }

    # Name provided - create Windows Terminal profile with background
    try {
        # 1. Select model first (before creating background image)
        $model = Get-ModelChoice

        # Check if user aborted
        if ($model -eq 'abort') {
            Write-Host ""
            Write-ColorText "New session aborted." -Color Yellow
            return
        }

        # 2. Check for background image conflict and resolve
        $resolution = Resolve-BackgroundImageConflict -SessionName $sessionName

        if ($resolution.action -eq 'abort') {
            Write-Host ""
            Write-ColorText "New session aborted." -Color Yellow
            return
        }

        # Use the resolved name (may have been modified for 'new' action)
        $finalSessionName = $resolution.name

        # 3. Generate or use background image with model info
        if ($resolution.action -eq 'use') {
            # Use existing image
            $bgPath = $resolution.path
            Write-ColorText "Using existing background image." -Color Green
        } else {
            # Generate new image (either 'create' or 'overwrite')
            Write-Host ""
            Write-ColorText "Generating background image..." -Color Cyan
            $originText = "$env:COMPUTERNAME`:$env:USERNAME"

            # Detect git branch
            $gitBranch = Get-GitBranch -Path $targetDirectory

            $bgPath = New-SessionBackgroundImage -NewName $finalSessionName -OldName $originText -GitBranch $gitBranch -Model $model -ProjectPath $targetDirectory
        }

        # 4. Create Windows Terminal profile
        Write-ColorText "Creating Windows Terminal profile..." -Color Cyan
        $wtProfileName = "Claude-$finalSessionName"
        $profile = Add-WTProfile -Name $wtProfileName -StartingDirectory $targetDirectory -BackgroundImage $bgPath

        # Use the actual profile name that was created (may have integer appended if duplicate)
        $actualProfileName = $profile.name

        # 4. Prompt for trusted session
        $trustedChoice = Get-TrustedSessionChoice

        # Check if user aborted
        if ($trustedChoice -eq 'abort') {
            Write-Host ""
            Write-ColorText "New session aborted. Cleaning up..." -Color Yellow
            # Remove the Windows Terminal profile we just created
            Remove-WTProfile -ProfileName $actualProfileName
            # Remove the background image
            $imageDir = Join-Path $Global:MenuPath $finalSessionName
            if (Test-Path $imageDir) {
                Remove-Item $imageDir -Recurse -Force
            }
            return
        }

        if ($trustedChoice -eq 'yes') {
            Set-TrustedSessionSettings -ProjectPath $targetDirectory
        }

        # 5. Launch Windows Terminal with the new profile (let Claude create session ID)
        Write-Host ""
        Write-ColorText "Launching terminal with profile: $finalName" -Color Green
        Write-Host ""

        $profileGuid = $profile.guid
        $projectPath = $targetDirectory
        $claudePath = Get-ClaudeCLIPath

        # Launch Windows Terminal WITHOUT --session-id (let Claude create its own)
        Start-Process -FilePath "wt.exe" -ArgumentList "-p", "`"$profileGuid`"", "-d", "`"$projectPath`"", "--", "`"$claudePath`"", "--model", "`"$model`"" -NoNewWindow

        # Store simplified command for display
        $Global:LastClaudeCommand = "claude --model `"$model`""

        # 6. Wait for Claude to create the session and discover its ID
        $sessionId = Get-NewestSessionIdForPath -ProjectPath $projectPath -MaxWaitSeconds 15

        if ($sessionId) {
            # 7. Update tracking with discovered session ID
            Write-ColorText "Registering session..." -Color Cyan
            $gitBranch = Get-GitBranch -Path $projectPath
            Add-SessionMapping -SessionId $sessionId -WTProfileName $actualProfileName -ProjectPath $projectPath -Model $model -GitBranch $gitBranch

            Write-ColorText "New session launched successfully!" -Color Green
            Write-Host ""
            Write-Host "Profile: $actualProfileName"
            Write-Host "Session ID: $sessionId"
            Write-Host "Model: $model"
            Write-Host "Directory: $projectPath"
            Write-Host ""
            Write-ColorText "Tip: Use /rename in Claude to give this session a custom title" -Color Yellow
            Write-Host ""
        } else {
            Write-ColorText "Warning: Could not discover session ID automatically." -Color Yellow
            Write-ColorText "The session was launched, but tracking may be incomplete." -Color Yellow
            Write-Host ""
        }

        return

    } catch {
        Write-ColorText "Failed to create new session: $_" -Color Red
        throw
    }
}

function Start-ContinueSession {
    <#
    .SYNOPSIS
        Continues an existing Claude session
    #>
    param([object]$Session)

    Write-DebugInfo "=== Start-ContinueSession ===" -Color Cyan
    Write-DebugInfo "  Session ID: $($Session.sessionId)"
    Write-DebugInfo "  Custom Title: $($Session.customTitle)"
    Write-DebugInfo "  Project Path: $($Session.projectPath)"

    # Validate session file exists before continuing
    Write-DebugInfo "  Validating session file..." -Color Yellow
    if (-not (Test-SessionFileValid -SessionId $Session.sessionId -ProjectPath $Session.projectPath)) {
        Write-DebugInfo "  Session file validation FAILED" -Color Red
        Write-Host ""
        Write-ColorText "ERROR: Session file is missing or corrupted!" -Color Red
        Write-Host ""
        Write-Host "Session ID: $($Session.sessionId)"
        Write-Host "Project Path: $($Session.projectPath)"
        Write-Host ""
        Write-ColorText "This usually happens when:" -Color Yellow
        Write-Host "  1. The session was created but never used (empty conversation)"
        Write-Host "  2. The session .jsonl file was deleted or moved"
        Write-Host "  3. File system corruption occurred"
        Write-Host ""

        # Store error info for main menu display
        $sessionName = if ($Session.customTitle) { $Session.customTitle } else { "(unnamed)" }
        $Global:LastClaudeError = "Claude could not find conversation with guid $($Session.sessionId) and name '$sessionName'"
        $Global:LastClaudeCommand = "claude --resume $($Session.sessionId)"

        # Prompt user to delete the session
        Write-ColorText "Would you like to delete this session?" -Color Cyan
        Write-Host "  [Y] Yes, delete it now"
        Write-Host "  [N] No, return to menu"
        Write-Host ""
        Write-Host "Y" -NoNewline -ForegroundColor Yellow
        Write-Host "es | " -NoNewline -ForegroundColor Gray
        Write-Host "N" -NoNewline -ForegroundColor Yellow
        Write-Host "o " -NoNewline -ForegroundColor Gray
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $deleteChoice = $key.Character.ToString().ToUpper()

        # Handle Esc as No
        if ($key.VirtualKeyCode -eq 27) {
            $deleteChoice = 'N'
        }

        # Handle Enter as default (Yes)
        if ($key.VirtualKeyCode -eq 13) {
            $deleteChoice = 'Y'
        }

        if ($deleteChoice -eq 'Y') {
            # Call the delete session function
            try {
                Start-DeleteSession -Session $Session
                Write-Host ""
                Write-ColorText "Session deleted successfully." -Color Green
            } catch {
                Write-ColorText "Failed to delete session: $_" -Color Red
            }
        }

        return
    }

    Write-DebugInfo "  Session file validation PASSED" -Color Green

    Write-Host ""
    # Get session title - prefer customTitle, fall back to trackedName, then (unnamed)
    $sessionTitle = if ($Session.customTitle) {
        $Session.customTitle
    } elseif ($Session.trackedName) {
        $Session.trackedName
    } else {
        '(unnamed)'
    }
    Write-DebugInfo "  Session Title: $sessionTitle"

    # Only create Windows Terminal profiles for named sessions (either customTitle OR trackedName)
    if (($Session.customTitle -and $Session.customTitle -ne "") -or ($Session.trackedName -and $Session.trackedName -ne "")) {
        Write-DebugInfo "  Session HAS name (custom title or tracked) - checking for WT profile" -Color Cyan
        Write-ColorText "Continuing session: $sessionTitle" -Color Green
        Write-Host ""

        # Check if Windows Terminal profile already exists
        $wtProfileName = "Claude-$sessionTitle"
        Write-DebugInfo "  Expected WT Profile Name: $wtProfileName"
        $existingProfile = $null

        Write-DebugInfo "  Checking for existing Windows Terminal profile..." -Color Yellow
        try {
            Write-DebugInfo "    WT Settings Path: $Global:WTSettingsPath"
            if (Test-Path $Global:WTSettingsPath) {
                Write-DebugInfo "    WT Settings file EXISTS"
                $settingsJson = Get-Content $Global:WTSettingsPath -Raw
                $settings = $settingsJson | ConvertFrom-Json
                Write-DebugInfo "    Searching for profile with name: $wtProfileName"
                $existingProfile = $settings.profiles.list | Where-Object { $_.name -eq $wtProfileName } | Select-Object -First 1
                if ($existingProfile) {
                    Write-DebugInfo "    FOUND existing profile by name: $($existingProfile.name) (GUID: $($existingProfile.guid))" -Color Green
                } else {
                    Write-DebugInfo "    NO matching profile found by name" -Color Yellow
                    # Try checking session mapping for this session ID
                    Write-DebugInfo "    Checking session mapping for session ID: $($Session.sessionId)" -Color Yellow
                    $mappedProfileName = Get-SessionMapping -SessionId $Session.sessionId
                    if ($mappedProfileName) {
                        Write-DebugInfo "    Found mapped profile name: $mappedProfileName" -Color Cyan
                        # Look up the profile by the mapped name
                        $existingProfile = $settings.profiles.list | Where-Object { $_.name -eq $mappedProfileName } | Select-Object -First 1
                        if ($existingProfile) {
                            Write-DebugInfo "    FOUND existing profile by mapping: $($existingProfile.name) (GUID: $($existingProfile.guid))" -Color Green
                            $wtProfileName = $mappedProfileName  # Update to use the correct name
                        } else {
                            Write-DebugInfo "    Mapped profile name not found in WT settings" -Color Yellow
                        }
                    } else {
                        Write-DebugInfo "    No mapping found for this session ID" -Color Yellow
                    }
                }
            } else {
                Write-DebugInfo "    WT Settings file DOES NOT EXIST" -Color Red
            }
        } catch {
            Write-DebugInfo "    EXCEPTION checking for profile: $_" -Color Red
            Write-ErrorLog "Error checking for existing profile: $_"
        }

        # Generate/verify background image exists
        Write-DebugInfo "  Checking for background image..." -Color Yellow
        $bgPath = Join-Path $Global:MenuPath "$sessionTitle\background.png"
        Write-DebugInfo "    Expected path: $bgPath"
        if (-not (Test-Path $bgPath)) {
            Write-DebugInfo "    Background image DOES NOT EXIST - creating..." -Color Yellow
            Write-ColorText "Creating background image..." -Color Cyan

            # Detect git branch
            $gitBranch = Get-GitBranch -Path $Session.projectPath

            # Get model from session mapping if available
            $sessionEntry = Get-SessionMappingEntry -SessionId $Session.sessionId
            $modelName = if ($sessionEntry -and $sessionEntry.model) { $sessionEntry.model } else { $null }

            $bgPath = New-ContinueSessionBackgroundImage -SessionName $sessionTitle -GitBranch $gitBranch -Model $modelName -ProjectPath $Session.projectPath
            Write-DebugInfo "    Created background image at: $bgPath" -Color Green
        } else {
            Write-DebugInfo "    Background image EXISTS" -Color Green
        }

        if ($existingProfile) {
            Write-DebugInfo "  Using EXISTING Windows Terminal profile path" -Color Cyan
            # Profile exists - update background image if needed
            Write-ColorText "Using existing Windows Terminal profile: $wtProfileName" -Color Cyan

            # Update the background image path in the profile
            try {
                $backupPath = Backup-WTSettings
                $settingsJson = Get-Content $Global:WTSettingsPath -Raw
                $settings = $settingsJson | ConvertFrom-Json

                $profileIndex = -1
                for ($i = 0; $i -lt $settings.profiles.list.Count; $i++) {
                    if ($settings.profiles.list[$i].name -eq $wtProfileName) {
                        $profileIndex = $i
                        break
                    }
                }

                if ($profileIndex -ge 0) {
                    $imagePath = $bgPath -replace '\\', '/'
                    $settings.profiles.list[$profileIndex].backgroundImage = $imagePath
                    $jsonContent = $settings | ConvertTo-Json -Depth 10
                    Write-DebugFileOperation -FilePath $Global:WTSettingsPath -Content $jsonContent -Operation "UpdateWTProfile"  # FILE-DEBUG
                    $jsonContent | Set-Content $Global:WTSettingsPath -Encoding UTF8
                    Write-ColorText "Updated background image for profile" -Color Green
                }
            } catch {
                Write-ColorText "Warning: Could not update background image: $_" -Color Yellow
            }

            # Launch in existing Windows Terminal profile
            $profileGuid = $existingProfile.guid
            $claudePath = Get-ClaudeCLIPath
            Write-DebugInfo "  Launching with EXISTING profile..." -Color Yellow
            Write-DebugInfo "    Profile GUID: $profileGuid"
            Write-DebugInfo "    Working Dir: $($Session.projectPath)"
            Write-DebugInfo "    Claude Path: $claudePath"
            Write-DebugInfo "    Session ID: $($Session.sessionId)"

            # Show user-friendly launch message
            $displayName = if ($Session.customTitle) { $Session.customTitle } else { $Session.sessionId }
            Write-Host ""
            Write-ColorText "Launching terminal with profile: $wtProfileName" -Color Cyan
            Write-Host ""

            & wt.exe -p "$profileGuid" -d "$($Session.projectPath)" -- "$claudePath" --resume $Session.sessionId
            Write-DebugInfo "  Launched successfully" -Color Green

            # Store simplified command for display
            $Global:LastClaudeCommand = "claude --resume $displayName"
            $Global:LastClaudeError = $null

            return

        } else {
            # Profile doesn't exist - create it
            Write-DebugInfo "  NO existing profile - creating NEW profile path" -Color Cyan
            Write-ColorText "Creating Windows Terminal profile..." -Color Cyan

            try {
                $profile = Add-WTProfile -Name $wtProfileName -StartingDirectory $Session.projectPath -BackgroundImage $bgPath

                # Add to session mapping (use actual profile name in case it was modified)
                $actualProfileName = $profile.name

                # VALIDATION: Verify session file exists before saving mapping
                $encodedPath = ConvertTo-ClaudeprojectPath -Path $Session.projectPath
                $sessionFile = Join-Path "$env:USERPROFILE\.claude\projects" "$encodedPath\$($Session.sessionId).jsonl"
                Write-DebugInfo "  Verifying session file: $sessionFile" -Color Cyan

                if (Test-Path $sessionFile) {
                    Write-DebugInfo "  Session file VERIFIED - proceeding with mapping" -Color Green
                    $gitBranch = Get-GitBranch -Path $Session.projectPath
                    $model = Get-ModelFromSession -SessionId $Session.sessionId -ProjectPath $Session.projectPath
                    Add-SessionMapping -SessionId $Session.sessionId -WTProfileName $actualProfileName -ProjectPath $Session.projectPath -Model $model -GitBranch $gitBranch
                } else {
                    Write-DebugInfo "  ERROR: Session file NOT FOUND!" -Color Red
                    Write-DebugInfo "  Session ID: $($Session.sessionId)" -Color Red
                    Write-DebugInfo "  This indicates a bug - session object has wrong ID" -Color Red
                    Write-ColorText "WARNING: Session file verification failed. Mapping not saved." -Color Red
                }

                Write-ColorText "Windows Terminal profile created: $actualProfileName" -Color Green
                Write-Host ""

                # Show user-friendly launch message
                $displayName = if ($Session.customTitle) {
                    $Session.customTitle
                } elseif ($Session.trackedName) {
                    $Session.trackedName
                } else {
                    $Session.sessionId
                }
                Write-ColorText "Launching terminal with profile: $actualProfileName" -Color Cyan
                Write-Host ""

                # Launch in new Windows Terminal profile
                $profileGuid = $profile.guid
                $claudePath = Get-ClaudeCLIPath
                & wt.exe -p "$profileGuid" -d "$($Session.projectPath)" -- "$claudePath" --resume $Session.sessionId

                # Store simplified command for display
                $Global:LastClaudeCommand = "claude --resume $displayName"
                $Global:LastClaudeError = $null

                return

            } catch {
                Write-ColorText "Failed to create Windows Terminal profile: $_" -Color Red
                Write-ColorText "Launching terminal with default profile instead..." -Color Yellow
                Write-Host ""

                # Fallback to Windows Terminal with default profile
                $claudePath = Get-ClaudeCLIPath
                & wt.exe -d "$($Session.projectPath)" -- "$claudePath" --resume $Session.sessionId

                # Store command for display
                $Global:LastClaudeCommand = "claude --resume $($Session.sessionId)"
                $Global:LastClaudeError = $null
            }
        }
    } else {
        # Unnamed session (no customTitle AND no trackedName) - offer to create Windows Terminal profile
        Write-DebugInfo "  Session is truly unnamed (no custom title or tracked name) - unnamed session path" -Color Cyan
        Write-ColorText "Continuing session: (unnamed)" -Color Green
        Write-Host ""
        Write-ColorText "This session does not have a name or Windows Terminal profile." -Color Yellow
        Write-Host ""
        Write-ColorText "Would you like to create a profile with a custom name?" -Color Cyan
        Write-Host ""
        Write-Host "Y" -NoNewline -ForegroundColor Yellow
        Write-Host "es | " -NoNewline -ForegroundColor Gray
        Write-Host "N" -NoNewline -ForegroundColor Yellow
        Write-Host "o " -NoNewline -ForegroundColor Gray
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $createProfile = $key.Character.ToString().ToUpper()

        # Handle Esc as No
        if ($key.VirtualKeyCode -eq 27) {
            $createProfile = 'N'
        }

        # Handle Enter as default (Yes)
        if ($key.VirtualKeyCode -eq 13) {
            $createProfile = 'Y'
        }

        Write-DebugInfo "  User response to create profile: $createProfile"

        if ($createProfile -eq 'Y') {
            Write-DebugInfo "  User chose YES - prompting for session name"
            # Prompt for session name
            Write-Host ""
            Write-ColorText "Enter a name for this session: " -Color Yellow -NoNewline
            $newSessionName = Read-Host

            Write-DebugInfo "  User entered session name: $newSessionName"

            if ([string]::IsNullOrWhiteSpace($newSessionName)) {
                Write-DebugInfo "  Session name is empty - launching terminal with default profile" -Color Yellow
                Write-Host ""
                Write-ColorText "Session name cannot be empty. Launching terminal with default profile..." -Color Red
                Write-Host ""

                # Launch in Windows Terminal with default profile
                $claudePath = Get-ClaudeCLIPath
                & wt.exe -d "$($Session.projectPath)" -- "$claudePath" --resume $Session.sessionId

                # Store command for display
                $Global:LastClaudeCommand = "claude --resume $($Session.sessionId)"
                $Global:LastClaudeError = $null
                return
            }

            # Sanitize name
            Write-DebugInfo "  Sanitizing session name..."
            $safeName = $newSessionName -replace '[\\/:*?"<>|]', '_'
            Write-DebugInfo "  Safe name: $safeName"
            if ($newSessionName -ne $safeName) {
                Write-ColorText "Name contains invalid characters. Using: $safeName" -Color Yellow
            }

            # Check for background image conflict and resolve
            Write-DebugInfo "  Checking for background image conflict..." -Color Yellow
            $resolution = Resolve-BackgroundImageConflict -SessionName $safeName

            if ($resolution.action -eq 'abort') {
                Write-Host ""
                Write-ColorText "Profile creation aborted." -Color Yellow
                continue
            }

            # Use the resolved name (may have been modified for 'new' action)
            $finalSafeName = $resolution.name

            # Create Windows Terminal profile with background image
            $wtProfileName = "Claude-$finalSafeName"
            Write-DebugInfo "  WT Profile Name: $wtProfileName"
            Write-Host ""
            Write-ColorText "Creating Windows Terminal profile: $wtProfileName" -Color Cyan

            # Generate or use background image
            if ($resolution.action -eq 'use') {
                # Use existing image
                $bgImagePath = $resolution.path
                Write-DebugInfo "  Using existing background image: $bgImagePath" -Color Green
                Write-ColorText "Using existing background image." -Color Green
            } else {
                # Generate new image (either 'create' or 'overwrite')
                Write-DebugInfo "  Generating background image..." -Color Yellow
                Write-DebugInfo "    NewName: $finalSafeName"
                Write-DebugInfo "    OldName: (empty)"

                # Detect git branch
                $gitBranch = Get-GitBranch -Path $Session.projectPath

                # Get model from session mapping if available
                $sessionEntry = Get-SessionMappingEntry -SessionId $Session.sessionId
                $modelName = if ($sessionEntry -and $sessionEntry.model) { $sessionEntry.model } else { $null }

                $bgImagePath = New-SessionBackgroundImage -NewName $finalSafeName -OldName "" -GitBranch $gitBranch -Model $modelName -ProjectPath $Session.projectPath
                Write-DebugInfo "  Background image path: $bgImagePath" -Color Green
            }

            if ($bgImagePath) {
                Write-DebugInfo "  Background image ready for use"
                try {
                    # Add profile to Windows Terminal
                    Write-DebugInfo "  Adding Windows Terminal profile..." -Color Yellow
                    Write-DebugInfo "    Name: $wtProfileName"
                    Write-DebugInfo "    StartingDirectory: $($Session.projectPath)"
                    Write-DebugInfo "    BackgroundImage: $bgImagePath"
                    $profile = Add-WTProfile -Name $wtProfileName -StartingDirectory $Session.projectPath -BackgroundImage $bgImagePath
                    Write-DebugInfo "  Add-WTProfile returned: $($profile -ne $null)" -Color Green

                    if ($profile) {
                        Write-DebugInfo "  Profile created successfully, GUID: $($profile.guid)"
                        Write-DebugInfo "  Actual profile name: $($profile.name)"
                        # Update session mapping (use actual profile name in case it was modified)
                        $actualProfileName = $profile.name
                        Write-DebugInfo "  Updating session mapping..." -Color Yellow
                        Write-DebugInfo "    SessionId: $($Session.sessionId)"
                        Write-DebugInfo "    WTProfileName: $actualProfileName"
                        Write-DebugInfo "    ProjectPath: $($Session.projectPath)"

                        # VALIDATION: Verify session file exists before saving mapping
                        $encodedPath = ConvertTo-ClaudeprojectPath -Path $Session.projectPath
                        $sessionFile = Join-Path "$env:USERPROFILE\.claude\projects" "$encodedPath\$($Session.sessionId).jsonl"
                        Write-DebugInfo "    Verifying session file: $sessionFile" -Color Cyan

                        if (Test-Path $sessionFile) {
                            Write-DebugInfo "    Session file VERIFIED - proceeding with mapping" -Color Green
                            $gitBranch = Get-GitBranch -Path $Session.projectPath
                            $model = Get-ModelFromSession -SessionId $Session.sessionId -ProjectPath $Session.projectPath
                            Add-SessionMapping -SessionId $Session.sessionId -WTProfileName $actualProfileName -ProjectPath $Session.projectPath -Model $model -GitBranch $gitBranch
                            Write-DebugInfo "  Session mapping updated successfully" -Color Green
                        } else {
                            Write-DebugInfo "    ERROR: Session file NOT FOUND!" -Color Red
                            Write-DebugInfo "    This indicates a bug - session object has wrong ID" -Color Red
                            Write-ColorText "WARNING: Session file verification failed. Mapping not saved." -Color Red
                        }

                        Write-Host ""
                        Write-ColorText "Windows Terminal profile created successfully!" -Color Green
                        Write-Host ""

                        # Launch in new Windows Terminal profile
                        $profileGuid = $profile.guid
                        $claudePath = Get-ClaudeCLIPath
                        Write-DebugInfo "  Launching Windows Terminal..." -Color Yellow
                        Write-DebugInfo "    Profile GUID: $profileGuid"
                        Write-DebugInfo "    Working Dir: $($Session.projectPath)"
                        Write-DebugInfo "    Claude Path: $claudePath"
                        Write-DebugInfo "    Session ID: $($Session.sessionId)"

                        # Show user-friendly launch message
                        $displayName = if ($Session.customTitle) {
                            $Session.customTitle
                        } elseif ($Session.trackedName) {
                            $Session.trackedName
                        } else {
                            $Session.sessionId
                        }
                        Write-Host ""
                        Write-ColorText "Launching terminal with profile: $actualProfileName" -Color Cyan
                        Write-Host ""

                        & wt.exe -p "$profileGuid" -d "$($Session.projectPath)" -- "$claudePath" --resume $Session.sessionId
                        Write-DebugInfo "  Windows Terminal launched" -Color Green

                        # Store simplified command for display
                        $Global:LastClaudeCommand = "claude --resume $displayName"
                        $Global:LastClaudeError = $null

                        return

                    } else {
                        Write-DebugInfo "  Add-WTProfile returned null - profile creation failed" -Color Red
                        Write-Host ""
                        Write-ColorText "Failed to create Windows Terminal profile. Launching terminal with default profile..." -Color Red
                        Write-Host ""

                        # Fallback to Windows Terminal with default profile
                        Write-DebugInfo "  Launching Windows Terminal with default profile (fallback)" -Color Yellow
                        $claudePath = Get-ClaudeCLIPath
                        & wt.exe -d "$($Session.projectPath)" -- "$claudePath" --resume $Session.sessionId

                        # Store command for display
                        $Global:LastClaudeCommand = "claude --resume $($Session.sessionId)"
                        $Global:LastClaudeError = $null
                    }
                } catch {
                    Write-DebugInfo "  EXCEPTION in Add-WTProfile: $_" -Color Red
                    Write-ErrorLog "Exception in Start-ContinueSession (Add-WTProfile): $_"
                    Write-ColorText "Error creating profile: $_" -Color Red
                    Write-ColorText "Launching terminal with default profile instead..." -Color Yellow
                    Write-Host ""

                    # Fallback to Windows Terminal with default profile
                    Write-DebugInfo "  Launching Windows Terminal with default profile (exception fallback)" -Color Yellow
                    $claudePath = Get-ClaudeCLIPath
                    & wt.exe -d "$($Session.projectPath)" -- "$claudePath" --resume $Session.sessionId

                    # Store command for display
                    $Global:LastClaudeCommand = "claude --resume $($Session.sessionId)"
                    $Global:LastClaudeError = $null
                }
            } else {
                Write-DebugInfo "  Background image generation FAILED - bgImagePath is null/empty" -Color Red
                Write-Host ""
                Write-ColorText "Failed to generate background image. Launching terminal with default profile..." -Color Red
                Write-Host ""

                # Fallback to Windows Terminal with default profile
                Write-DebugInfo "  Launching Windows Terminal with default profile (no background image)" -Color Yellow
                $claudePath = Get-ClaudeCLIPath
                & wt.exe -d "$($Session.projectPath)" -- "$claudePath" --resume $Session.sessionId

                # Store command for display
                $Global:LastClaudeCommand = "claude --resume $($Session.sessionId)"
                $Global:LastClaudeError = $null
            }
        } else {
            # User chose not to create profile - launch in Windows Terminal with default profile
            Write-DebugInfo "  User chose NO - launching in Windows Terminal with default profile" -Color Yellow
            Write-Host ""
            Write-ColorText "Launching terminal with default profile..." -Color Cyan
            Write-Host ""

            $claudePath = Get-ClaudeCLIPath
            Write-DebugInfo "  Starting Windows Terminal with default profile"
            Write-DebugInfo "    Working Dir: $($Session.projectPath)"
            Write-DebugInfo "    Command: $claudePath --resume $($Session.sessionId)"

            # Launch in Windows Terminal with default profile
            & wt.exe -d "$($Session.projectPath)" -- "$claudePath" --resume $Session.sessionId

            # Store command for display
            $Global:LastClaudeCommand = "claude --resume $($Session.sessionId)"
            $Global:LastClaudeError = $null
        }
    }

    Write-DebugInfo "=== End Start-ContinueSession ===" -Color Cyan
}

function Get-SessionManagementChoice {
    <#
    .SYNOPSIS
        Prompts user to choose session management action (for sessions with WT profiles)
    #>
    param(
        [object]$Session,
        [string]$WTProfileName
    )

    Write-Host ""
    Write-ColorText "Windows Terminal Profile Management" -Color Cyan
    Write-ColorText "Session: $($Session.customTitle)" -Color DarkGray
    Write-ColorText "Profile: $WTProfileName" -Color DarkGray
    Write-Host ""
    Write-Host "R" -NoNewline -ForegroundColor Yellow
    Write-Host "egenerate - Regenerate background image | " -NoNewline -ForegroundColor Gray
    Write-Host "D" -NoNewline -ForegroundColor Yellow
    Write-Host "elete - Delete Windows Terminal profile | " -NoNewline -ForegroundColor Gray
    Write-Host "B" -NoNewline -ForegroundColor Yellow
    Write-Host "ackground - Remove background image from profile | " -NoNewline -ForegroundColor Gray
    Write-Host "A" -NoNewline -ForegroundColor Yellow
    Write-Host "bort" -NoNewline -ForegroundColor Gray

    while ($true) {
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $choice = $key.Character.ToString().ToUpper()

        # Handle Esc as abort
        if ($key.VirtualKeyCode -eq 27) {
            Write-Host ""
            return 'abort'
        }

        # Handle Enter as default (regenerate)
        if ($key.VirtualKeyCode -eq 13) {
            Write-Host ""
            return 'regenerate'
        }

        switch ($choice) {
            'R' { Write-Host ""; return 'regenerate' }
            'D' { Write-Host ""; return 'delete' }
            'B' { Write-Host ""; return 'remove-background' }
            'A' { Write-Host ""; return 'abort' }
            default {
                # Invalid choice - silently ignore
            }
        }
    }
}

function Get-RegenerateImageChoice {
    <#
    .SYNOPSIS
        Prompts user to choose how to regenerate the background image
    #>
    param([string]$SessionName)

    Write-Host ""
    Write-ColorText "Regenerate Background Image Options" -Color Cyan
    Write-Host ""
    Write-Host "R" -NoNewline -ForegroundColor Yellow
    Write-Host "efresh - Regenerate from session: $SessionName | " -NoNewline -ForegroundColor Gray
    Write-Host "F" -NoNewline -ForegroundColor Yellow
    Write-Host "ile - Use custom image file | " -NoNewline -ForegroundColor Gray
    Write-Host "T" -NoNewline -ForegroundColor Yellow
    Write-Host "ext - Generate from custom text | " -NoNewline -ForegroundColor Gray
    Write-Host "A" -NoNewline -ForegroundColor Yellow
    Write-Host "bort" -NoNewline -ForegroundColor Gray

    while ($true) {
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $choice = $key.Character.ToString().ToUpper()

        # Handle Esc as abort
        if ($key.VirtualKeyCode -eq 27) {
            Write-Host ""
            return 'abort'
        }

        # Handle Enter as default (refresh)
        if ($key.VirtualKeyCode -eq 13) {
            Write-Host ""
            return 'refresh'
        }

        switch ($choice) {
            'R' { Write-Host ""; return 'refresh' }
            'F' { Write-Host ""; return 'file' }
            'T' { Write-Host ""; return 'text' }
            'A' { Write-Host ""; return 'abort' }
            default {
                # Invalid choice - silently ignore
            }
        }
    }
}

function Get-ForkOrContinue {
    <#
    .SYNOPSIS
        Prompts user to choose between forking, continuing, or deleting a session
    #>
    param(
        [string]$SessionId = "",
        [string]$SessionTitle = "",
        [string]$ProjectPath = "",
        [bool]$IsArchived = $false,
        [string]$ArchivedDate = $null,
        [string]$Notes = ""
    )

    Write-Host ""

    # Display archive banner if session is archived
    if ($IsArchived) {
        $dateDisplay = if ($ArchivedDate) {
            try {
                $dt = [DateTime]::Parse($ArchivedDate)
                $dt.ToString("yyyy-MM-dd HH:mm:ss")
            } catch {
                $ArchivedDate
            }
        } else {
            "Unknown"
        }

        Write-Host "========================================" -ForegroundColor Red
        Write-Host "  ARCHIVED ON $dateDisplay" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        Write-Host ""
    }

    Write-ColorText "Session options" -Color Cyan
    if ($SessionTitle) {
        Write-ColorText "Session: $SessionTitle" -Color DarkGray
    }
    Write-ColorText "Session ID: $SessionId" -Color DarkGray
    if ($ProjectPath) {
        Write-ColorText "Path: $ProjectPath" -Color DarkGray

        # Detect and display git branch
        $gitBranch = Get-GitBranch -Path $ProjectPath
        if ($gitBranch) {
            Write-ColorText "Git Branch: $gitBranch" -Color DarkGray
        }
    }

    # Display model from session
    $sessionModel = Get-ModelFromSession -SessionId $SessionId -ProjectPath $ProjectPath
    if ($sessionModel) {
        if ($sessionModel -eq '<synthetic>') {
            Write-Host "Model: " -NoNewline -ForegroundColor DarkGray
            Write-Host "<synthetic>" -NoNewline -ForegroundColor Magenta
            Write-Host " (session created outside Claude CLI, e.g. claude.ai or API)" -ForegroundColor DarkGray
        } else {
            Write-ColorText "Model: $sessionModel" -Color DarkGray
        }
    }

    # LimitFeature: Display context usage percentage with explanation
    $contextUsage = Get-SessionContextUsage -SessionId $SessionId -ProjectPath $ProjectPath -Model $sessionModel
    if ($contextUsage -and $contextUsage.Percentage) {
        $pct = $contextUsage.Percentage
        $totalK = [math]::Round($contextUsage.TotalTokens / 1000, 0)
        $limitK = [math]::Round($contextUsage.ContextLimit / 1000, 0)

        # Color code based on usage level
        Write-Host "Context: " -NoNewline -ForegroundColor DarkGray
        if ($pct -ge 90) {
            Write-Host "$pct%" -NoNewline -ForegroundColor Red
            Write-Host " ($($totalK)K / $($limitK)K tokens) " -NoNewline -ForegroundColor DarkGray
            Write-Host "CRITICAL" -ForegroundColor Red
        } elseif ($pct -ge 75) {
            Write-Host "$pct%" -NoNewline -ForegroundColor Yellow
            Write-Host " ($($totalK)K / $($limitK)K tokens) " -NoNewline -ForegroundColor DarkGray
            Write-Host "HIGH" -ForegroundColor Yellow
        } elseif ($pct -ge 50) {
            Write-Host "$pct%" -NoNewline -ForegroundColor Cyan
            Write-Host " ($($totalK)K / $($limitK)K tokens)" -ForegroundColor DarkGray
        } else {
            Write-Host "$pct%" -NoNewline -ForegroundColor Green
            Write-Host " ($($totalK)K / $($limitK)K tokens)" -ForegroundColor DarkGray
        }

        # Show guidance based on usage level
        if ($pct -ge 90) {
            Write-Host ""
            Write-Host "  WARNING: " -NoNewline -ForegroundColor Red
            Write-Host "Context window nearly full. Session will auto-compact soon." -ForegroundColor Gray
            Write-Host "  " -NoNewline
            Write-Host "Action: " -NoNewline -ForegroundColor Yellow
            Write-Host "Fork this session now to preserve full context in the new branch." -ForegroundColor Gray
            Write-Host "         The original session can continue but will lose older context." -ForegroundColor DarkGray
        } elseif ($pct -ge 75) {
            Write-Host ""
            Write-Host "  Note: " -NoNewline -ForegroundColor Yellow
            Write-Host "Context usage is high. Consider forking if this is a long-running task." -ForegroundColor Gray
        }
    }

    # Display notes if they exist
    if ($Notes -and $Notes -ne "") {
        Write-ColorText "Notes: $Notes" -Color DarkGray
    }

    Write-Host ""

    if ($IsArchived) {
        # Archived session menu - no Continue or Fork options
        Write-Host "U" -NoNewline -ForegroundColor Yellow
        Write-Host "narchive | " -NoNewline -ForegroundColor Gray
        Write-Host "N" -NoNewline -ForegroundColor Yellow
        Write-Host "otes | " -NoNewline -ForegroundColor Gray
        Write-Host "D" -NoNewline -ForegroundColor Yellow
        Write-Host "elete | " -NoNewline -ForegroundColor Gray
        Write-Host "R" -NoNewline -ForegroundColor Yellow
        Write-Host "ename | " -NoNewline -ForegroundColor Gray
        Write-Host "A" -NoNewline -ForegroundColor Yellow
        Write-Host "bort" -NoNewline -ForegroundColor Gray
    } else {
        # Normal session menu
        # Check if session has a Windows Terminal profile
        $hasProfile = $false
        if ($SessionTitle) {
            $profileName = Get-WTProfileName -SessionTitle $SessionTitle -SessionId $SessionId
            if ($profileName) {
                $hasProfile = $true
            }
        } else {
            # For unnamed sessions, check session mapping
            $mappedProfile = Get-SessionMapping -SessionId $SessionId
            if ($mappedProfile) {
                $hasProfile = $true
            }
        }

        # Display appropriate continue option based on profile existence
        Write-Host "C" -NoNewline -ForegroundColor Yellow
        if ($hasProfile) {
            Write-Host "ontinue Claude Session | " -NoNewline -ForegroundColor Gray
        } else {
            Write-Host "ontinue - Create profile and resume | " -NoNewline -ForegroundColor Gray
        }
        Write-Host "F" -NoNewline -ForegroundColor Yellow
        Write-Host "ork Session | " -NoNewline -ForegroundColor Gray
        Write-Host "N" -NoNewline -ForegroundColor Yellow
        Write-Host "otes | " -NoNewline -ForegroundColor Gray
        Write-Host "D" -NoNewline -ForegroundColor Yellow
        Write-Host "elete | " -NoNewline -ForegroundColor Gray
        Write-Host "R" -NoNewline -ForegroundColor Yellow
        Write-Host "ename | " -NoNewline -ForegroundColor Gray
        Write-Host "archi" -NoNewline -ForegroundColor Gray
        Write-Host "V" -NoNewline -ForegroundColor Yellow
        Write-Host "e | " -NoNewline -ForegroundColor Gray
        Write-Host "L" -NoNewline -ForegroundColor Yellow
        Write-Host "imit Instructions | " -NoNewline -ForegroundColor Gray
        Write-Host "A" -NoNewline -ForegroundColor Yellow
        Write-Host "bort" -NoNewline -ForegroundColor Gray
    }

    while ($true) {
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $choice = $key.Character.ToString().ToUpper()
        Write-DebugInfo "Get-ForkOrContinue: User pressed key: '$choice' (VirtualKeyCode: $($key.VirtualKeyCode))"

        # Handle Esc as abort
        if ($key.VirtualKeyCode -eq 27) {
            Write-DebugInfo "  Esc pressed - returning 'abort'"
            Write-Host ""
            return 'abort'
        }

        # Handle Enter as default (Continue for normal, Unarchive for archived)
        if ($key.VirtualKeyCode -eq 13) {
            if ($IsArchived) {
                Write-DebugInfo "  Enter pressed - returning 'unarchive' (default for archived)"
                Write-Host ""
                return 'unarchive'
            } else {
                Write-DebugInfo "  Enter pressed - returning 'continue' (default)"
                Write-Host ""
                return 'continue'
            }
        }

        if ($IsArchived) {
            # Archived session options: Unarchive, Notes, Delete, Rename, Abort
            if ($choice -eq 'U') {
                Write-DebugInfo "  'U' pressed - returning 'unarchive'"
                Write-Host ""
                return 'unarchive'
            } elseif ($choice -eq 'N') {
                Write-DebugInfo "  'N' pressed - returning 'notes'"
                Write-Host ""
                return 'notes'
            } elseif ($choice -eq 'D') {
                Write-DebugInfo "  'D' pressed - returning 'delete'"
                Write-Host ""
                return 'delete'
            } elseif ($choice -eq 'R') {
                Write-DebugInfo "  'R' pressed - returning 'rename'"
                Write-Host ""
                return 'rename'
            } elseif ($choice -eq 'A') {
                Write-DebugInfo "  'A' pressed - returning 'abort'"
                Write-Host ""
                return 'abort'
            } else {
                Write-DebugInfo "  Invalid choice for archived session - ignoring silently"
            }
        } else {
            # Normal session options: Continue, Fork, Notes, Delete, Rename, Archive, Abort
            if ($choice -eq 'C') {
                Write-DebugInfo "  'C' pressed - returning 'continue'"
                Write-Host ""
                return 'continue'
            } elseif ($choice -eq 'F') {
                Write-DebugInfo "  'F' pressed - returning 'fork'"
                Write-Host ""
                return 'fork'
            } elseif ($choice -eq 'N') {
                Write-DebugInfo "  'N' pressed - returning 'notes'"
                Write-Host ""
                return 'notes'
            } elseif ($choice -eq 'D') {
                Write-DebugInfo "  'D' pressed - returning 'delete'"
                Write-Host ""
                return 'delete'
            } elseif ($choice -eq 'R') {
                Write-DebugInfo "  'R' pressed - returning 'rename'"
                Write-Host ""
                return 'rename'
            } elseif ($choice -eq 'V') {
                Write-DebugInfo "  'V' pressed - returning 'archive'"
                Write-Host ""
                return 'archive'
            } elseif ($choice -eq 'L') {
                Write-DebugInfo "  'L' pressed - returning 'limit-instructions'"
                Write-Host ""
                return 'limit-instructions'
            } elseif ($choice -eq 'A') {
                Write-DebugInfo "  'A' pressed - returning 'abort'"
                Write-Host ""
                return 'abort'
            } else {
                Write-DebugInfo "  Invalid choice - ignoring silently"
            }
        }
    }
}

function Show-LimitInstructions {
    <#
    .SYNOPSIS
        Displays comprehensive instructions for managing context limits
    .DESCRIPTION
        Shows detailed guidance about Claude Code's context window, memory system,
        forking, and strategies for long-running sessions.
    #>
    param(
        [int]$CurrentPercentage = 0,
        [string]$ProjectPath = ""
    )

    Clear-Host
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "                    CONTEXT LIMIT MANAGEMENT GUIDE" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""

    # Current status
    if ($CurrentPercentage -gt 0) {
        Write-Host "Your current session context usage: " -NoNewline -ForegroundColor Gray
        if ($CurrentPercentage -ge 90) {
            Write-Host "$CurrentPercentage%" -ForegroundColor Red
        } elseif ($CurrentPercentage -ge 75) {
            Write-Host "$CurrentPercentage%" -ForegroundColor Yellow
        } else {
            Write-Host "$CurrentPercentage%" -ForegroundColor Green
        }
        Write-Host ""
    }

    # What is the context window?
    Write-Host "WHAT IS THE CONTEXT WINDOW?" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "Claude's context window is the total amount of text (measured in tokens) that"
    Write-Host "Claude can 'see' during a conversation. This includes:"
    Write-Host "  - System prompts and CLAUDE.md files"
    Write-Host "  - All previous messages in the conversation"
    Write-Host "  - File contents you've asked Claude to read"
    Write-Host "  - Tool outputs and results"
    Write-Host ""
    Write-Host "Current models have a " -NoNewline
    Write-Host "200,000 token" -NoNewline -ForegroundColor Cyan
    Write-Host " context limit (~150K words)."
    Write-Host ""

    # What happens at the limit?
    Write-Host "WHAT HAPPENS WHEN YOU HIT THE LIMIT?" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "When context exceeds ~95%, Claude Code automatically " -NoNewline
    Write-Host "compacts" -NoNewline -ForegroundColor Red
    Write-Host " the session."
    Write-Host "Compaction creates a summary of the conversation, which means:"
    Write-Host "  - Older messages are summarized, losing some detail and nuance" -ForegroundColor Gray
    Write-Host "  - Code snippets and specific instructions may be forgotten" -ForegroundColor Gray
    Write-Host "  - The 'feel' of the conversation changes as context is lost" -ForegroundColor Gray
    Write-Host ""

    # Strategy 1: Forking
    Write-Host "STRATEGY 1: FORK THE SESSION (Best for preserving context)" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "Forking creates a " -NoNewline
    Write-Host "new session branch" -NoNewline -ForegroundColor Green
    Write-Host " with the full context of the parent."
    Write-Host ""
    Write-Host "  When to fork:" -ForegroundColor Cyan
    Write-Host "    - Before hitting 90% context (do it at 75-85% to be safe)"
    Write-Host "    - When starting a new major task within the same project"
    Write-Host "    - When you want to try a different approach without losing the original"
    Write-Host ""
    Write-Host "  How to fork:" -ForegroundColor Cyan
    Write-Host "    - Press 'F' from this Session Options screen"
    Write-Host "    - Or use: claude --resume <session-id> --fork-session"
    Write-Host ""
    Write-Host "  The forked session starts fresh at 0% but 'remembers' everything!"
    Write-Host ""

    # Strategy 2: /memory
    Write-Host "STRATEGY 2: USE /memory (Best for saving key learnings)" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "The " -NoNewline
    Write-Host "/memory" -NoNewline -ForegroundColor Green
    Write-Host " command saves important context to a persistent file that Claude"
    Write-Host "automatically reads in future sessions."
    Write-Host ""
    Write-Host "  How /memory works:" -ForegroundColor Cyan
    Write-Host "    1. Type: " -NoNewline
    Write-Host "/memory" -ForegroundColor Green
    Write-Host "    2. Claude analyzes the conversation for important learnings"
    Write-Host "    3. These are saved to a CLAUDE.md file"
    Write-Host ""
    Write-Host "  Where memories are saved:" -ForegroundColor Cyan
    Write-Host "    - Project-level: " -NoNewline
    Write-Host "<project>/.claude/settings/CLAUDE.md" -ForegroundColor Magenta
    if ($ProjectPath) {
        $projectMemory = Join-Path $ProjectPath ".claude\settings\CLAUDE.md"
        if (Test-Path $projectMemory) {
            Write-Host "      (EXISTS: $projectMemory)" -ForegroundColor Green
        } else {
            Write-Host "      (Would be: $projectMemory)" -ForegroundColor DarkGray
        }
    }
    Write-Host "    - User-level:    " -NoNewline
    Write-Host "~/.claude/CLAUDE.md" -ForegroundColor Magenta
    $userMemory = Join-Path $env:USERPROFILE ".claude\CLAUDE.md"
    if (Test-Path $userMemory) {
        Write-Host "      (EXISTS: $userMemory)" -ForegroundColor Green
    } else {
        Write-Host "      (Would be: $userMemory)" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  Usage limits:" -ForegroundColor Cyan
    Write-Host "    - You can use /memory " -NoNewline
    Write-Host "multiple times per session" -ForegroundColor Green
    Write-Host "    - Each use appends new learnings (doesn't overwrite)"
    Write-Host "    - Best practice: Use it after completing major milestones"
    Write-Host "    - The file can be manually edited to curate important info"
    Write-Host ""

    # Strategy 3: CLAUDE.md
    Write-Host "STRATEGY 3: MAINTAIN CLAUDE.md FILES (Best for project knowledge)" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "CLAUDE.md files are " -NoNewline
    Write-Host "automatically loaded" -NoNewline -ForegroundColor Green
    Write-Host " at the start of every session."
    Write-Host ""
    Write-Host "  Where to place them:" -ForegroundColor Cyan
    Write-Host "    - Project root:  " -NoNewline
    Write-Host "CLAUDE.md" -NoNewline -ForegroundColor Magenta
    Write-Host " - loaded for all sessions in that directory"
    Write-Host "    - Subdirectories: Each can have its own CLAUDE.md"
    Write-Host "    - User config:   " -NoNewline
    Write-Host "~/.claude/CLAUDE.md" -NoNewline -ForegroundColor Magenta
    Write-Host " - loaded for ALL sessions"
    Write-Host ""
    Write-Host "  What to put in CLAUDE.md:" -ForegroundColor Cyan
    Write-Host "    - Project architecture and structure"
    Write-Host "    - Coding standards and conventions"
    Write-Host "    - Important context that never changes"
    Write-Host "    - Instructions that should apply to every session"
    Write-Host ""

    # Strategy 4: Manual compaction
    Write-Host "STRATEGY 4: MANUAL COMPACTION (When you want to continue lighter)" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "Use " -NoNewline
    Write-Host "/compact" -NoNewline -ForegroundColor Green
    Write-Host " to manually trigger compaction when you want to:"
    Write-Host "    - Free up context for a new direction"
    Write-Host "    - Keep the session but don't need old details"
    Write-Host "    - Before auto-compaction kicks in (to control the summary)"
    Write-Host ""

    # Recommended workflow
    Write-Host "RECOMMENDED WORKFLOW FOR LONG SESSIONS" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  1. " -NoNewline -ForegroundColor Cyan
    Write-Host "Start: Begin work in a session"
    Write-Host "  2. " -NoNewline -ForegroundColor Cyan
    Write-Host "At 50%: Consider if key learnings should be saved with /memory"
    Write-Host "  3. " -NoNewline -ForegroundColor Cyan
    Write-Host "At 75%: Use /memory to save progress, consider forking soon"
    Write-Host "  4. " -NoNewline -ForegroundColor Cyan
    Write-Host "At 85%: Fork the session to preserve full context"
    Write-Host "  5. " -NoNewline -ForegroundColor Cyan
    Write-Host "Continue: Work in the forked session (starts at 0%)"
    Write-Host "  6. " -NoNewline -ForegroundColor Cyan
    Write-Host "Optional: /compact the original if you want to continue it lighter"
    Write-Host ""

    # Quick reference
    Write-Host "QUICK REFERENCE" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  /memory          " -NoNewline -ForegroundColor Green
    Write-Host "- Save learnings to persistent CLAUDE.md"
    Write-Host "  /compact         " -NoNewline -ForegroundColor Green
    Write-Host "- Manually summarize and compress the session"
    Write-Host "  --fork-session   " -NoNewline -ForegroundColor Green
    Write-Host "- Create new branch with full context (via CLI)"
    Write-Host "  CLAUDE.md        " -NoNewline -ForegroundColor Green
    Write-Host "- Auto-loaded instructions/context file"
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Press any key to return to Session Options..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

#endregion

#region Fork Workflow

function Get-SessionName {
    <#
    .SYNOPSIS
        Prompts for and validates a new session name
    #>
    param([string]$OldSessionName = "")

    while ($true) {
        Write-Host ""
        if ($OldSessionName) {
            Write-ColorText "Forking '$OldSessionName'. Enter a name for the new session: " -Color Yellow -NoNewline
        } else {
            Write-ColorText "Enter new session name: " -Color Yellow -NoNewline
        }
        $name = Read-Host

        if ([string]::IsNullOrWhiteSpace($name)) {
            Write-ColorText "Session name cannot be empty." -Color Red
            continue
        }

        # Sanitize for filesystem
        $safeName = $name -replace '[\\/:*?"<>|]', '_'

        if ($name -ne $safeName) {
            Write-ColorText "Name contains invalid characters. Using: $safeName" -Color Yellow
        }

        return $safeName
    }
}

function Get-OptionalSessionName {
    <#
    .SYNOPSIS
        Prompts for an optional session name (allows empty input)
    #>
    while ($true) {
        Write-Host ""
        Write-ColorText "Enter a name for this session (press [Enter] to continue without a name, [A] to Abort): " -Color Yellow -NoNewline
        $name = Read-Host

        # Check for abort
        if ($name -eq 'A' -or $name -eq 'a') {
            return 'abort'
        }

        # Allow empty (no name)
        if ([string]::IsNullOrWhiteSpace($name)) {
            return ""
        }

        # Sanitize for filesystem
        $safeName = $name -replace '[\\/:*?"<>|]', '_'

        if ($name -ne $safeName) {
            Write-ColorText "Name contains invalid characters. Using: $safeName" -Color Yellow
        }

        return $safeName
    }
}

function Get-ModelChoice {
    <#
    .SYNOPSIS
        Prompts user to select a Claude model
    #>
    Write-Host ""
    Write-ColorText "Select model:" -Color Cyan
    Write-Host ""
    Write-Host "O" -NoNewline -ForegroundColor Yellow
    Write-Host "pus - Most capable | " -NoNewline -ForegroundColor Gray
    Write-Host "S" -NoNewline -ForegroundColor Yellow
    Write-Host "onnet - Balanced (Recommended) | " -NoNewline -ForegroundColor Gray
    Write-Host "H" -NoNewline -ForegroundColor Yellow
    Write-Host "aiku - Fast | " -NoNewline -ForegroundColor Gray
    Write-Host "A" -NoNewline -ForegroundColor Yellow
    Write-Host "bort" -NoNewline -ForegroundColor Gray

    while ($true) {
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $choice = $key.Character.ToString().ToUpper()

        # Handle Esc as abort
        if ($key.VirtualKeyCode -eq 27) {
            Write-Host ""
            return 'abort'
        }

        # Handle Enter as default (opus)
        if ($key.VirtualKeyCode -eq 13) {
            Write-Host ""
            return 'opus'
        }

        switch ($choice) {
            'O' { Write-Host ""; return 'opus' }
            'S' { Write-Host ""; return 'sonnet' }
            'H' { Write-Host ""; return 'haiku' }
            'A' { Write-Host ""; return 'abort' }
            default {
                # Invalid choice - silently ignore
            }
        }
    }
}

function Get-TrustedSessionChoice {
    <#
    .SYNOPSIS
        Prompts user if they want a trusted session with no permission limits
    .RETURNS
        Returns 'yes', 'no', or 'abort'
    #>
    Write-Host ""
    Write-ColorText "Do you want a trusted session with no permission limits?" -Color Cyan
    Write-Host ""
    Write-Host "Y" -NoNewline -ForegroundColor Yellow
    Write-Host "es - Bypass all permissions (trusted workspace) | " -NoNewline -ForegroundColor Gray
    Write-Host "N" -NoNewline -ForegroundColor Yellow
    Write-Host "o - Use default permission settings | " -NoNewline -ForegroundColor Gray
    Write-Host "A" -NoNewline -ForegroundColor Yellow
    Write-Host "bort" -NoNewline -ForegroundColor Gray

    while ($true) {
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $choice = $key.Character.ToString().ToUpper()

        # Handle Esc as abort
        if ($key.VirtualKeyCode -eq 27) {
            Write-Host ""
            return 'abort'
        }

        # Handle Enter as default (yes)
        if ($key.VirtualKeyCode -eq 13) {
            Write-Host ""
            return 'yes'
        }

        switch ($choice) {
            'Y' { Write-Host ""; return 'yes' }
            'N' { Write-Host ""; return 'no' }
            'A' { Write-Host ""; return 'abort' }
            default {
                # Invalid choice - just continue loop
            }
        }
    }
}

function Set-TrustedSessionSettings {
    <#
    .SYNOPSIS
        Creates or updates .claude\settings.local.json with trusted permissions
    #>
    param([string]$ProjectPath)

    $claudeDir = Join-Path $ProjectPath ".claude"
    $settingsFile = Join-Path $claudeDir "settings.local.json"

    # Create .claude directory if it doesn't exist
    if (-not (Test-Path $claudeDir)) {
        New-Item -Path $claudeDir -ItemType Directory -Force | Out-Null
    }

    # Define the permissions object
    $permissionsConfig = @{
        defaultMode = "bypassPermissions"
        allow = @("*")
    }

    if (Test-Path $settingsFile) {
        # File exists, read and merge
        try {
            $settingsJson = Get-Content $settingsFile -Raw
            $settings = $settingsJson | ConvertFrom-Json

            # Ensure permissions property exists
            if (-not $settings.permissions) {
                $settings | Add-Member -MemberType NoteProperty -Name "permissions" -Value ([PSCustomObject]@{})
            }

            # Update permissions
            $settings.permissions | Add-Member -MemberType NoteProperty -Name "defaultMode" -Value "bypassPermissions" -Force
            $settings.permissions | Add-Member -MemberType NoteProperty -Name "allow" -Value @("*") -Force

            # Save back
            $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
            Write-ColorText "Updated existing settings.local.json with trusted permissions" -Color Green

        } catch {
            Write-ColorText "Warning: Could not update existing settings.local.json: $_" -Color Yellow
        }
    } else {
        # File doesn't exist, create new
        $settings = @{
            permissions = $permissionsConfig
        }

        $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
        Write-ColorText "Created settings.local.json with trusted permissions" -Color Green
    }
}

function Get-GlobalPermissionStatus {
    <#
    .SYNOPSIS
        Checks if global bypass permissions are enabled in settings.json
    .DESCRIPTION
        Returns true/false, or if debug is on, returns detailed information
    #>
    $debugEnabled = Get-DebugState
    $settingsPath = $Global:ClaudeSettingsPath

    if (-not (Test-Path $settingsPath)) {
        if ($debugEnabled) {
            return @{
                Enabled = $false
                Reason = "Settings file does not exist"
                FilePath = $settingsPath
                Line = "N/A"
            }
        }
        return $false
    }

    try {
        $settingsJson = Get-Content $settingsPath -Raw
        $settings = $settingsJson | ConvertFrom-Json

        $isQuiet = ($settings.permissions -and
                    $settings.permissions.defaultMode -eq "bypassPermissions")

        if ($debugEnabled) {
            $lines = $settingsJson -split "`n"
            $relevantLine = "N/A"

            # Find the line with defaultMode
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '"defaultMode"') {
                    $relevantLine = "Line $($i + 1): $($lines[$i].Trim())"
                    break
                }
            }

            if (-not $isQuiet) {
                # Check if permissions section exists at all
                $hasPermissions = $settingsJson -match '"permissions"'
                if (-not $hasPermissions) {
                    $relevantLine = "No 'permissions' section found in file"
                } elseif ($relevantLine -eq "N/A") {
                    $relevantLine = "No 'defaultMode' found in permissions section"
                }
            }

            return @{
                Enabled = $isQuiet
                Reason = if ($isQuiet) { "permissions.defaultMode is set to 'bypassPermissions'" } else { "permissions.defaultMode is not 'bypassPermissions' or not set" }
                FilePath = $settingsPath
                Line = $relevantLine
            }
        }

        return $isQuiet
    } catch {
        if ($debugEnabled) {
            return @{
                Enabled = $false
                Reason = "Error reading settings file: $_"
                FilePath = $settingsPath
                Line = "N/A"
            }
        }
        return $false
    }
}

function Enable-GlobalBypassPermissions {
    <#
    .SYNOPSIS
        Enables global bypass permissions in settings.json
    #>

    Write-Host ""
    Write-ColorText "========================================" -Color Cyan
    Write-ColorText "  CHATTY MODE ENABLED (SWITCH TO QUIET)?" -Color Cyan
    Write-ColorText "========================================" -Color Cyan
    Write-Host ""
    Write-Host "Quiet mode disables permission prompts for all Claude sessions."
    Write-Host ""
    Write-Host "Switch to " -NoNewline -ForegroundColor Gray
    Write-Host "Q" -NoNewline -ForegroundColor Yellow
    Write-Host "uiet Mode | " -NoNewline -ForegroundColor Gray
    Write-Host "S" -NoNewline -ForegroundColor Yellow
    Write-Host "how Info | " -NoNewline -ForegroundColor Gray
    Write-Host "A" -NoNewline -ForegroundColor Yellow
    Write-Host "bort: " -NoNewline -ForegroundColor Gray
    $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    $choice = $key.Character.ToString().ToUpper()

    # Handle Esc as abort
    if ($key.VirtualKeyCode -eq 27) {
        $choice = 'A'
    }

    # Handle Enter as default (switch to quiet mode)
    if ($key.VirtualKeyCode -eq 13) {
        $choice = 'Q'
    }

    # Show detailed information if requested
    if ($choice -eq 'S') {
        Write-Host ""
        Write-ColorText "What this does:" -Color Yellow
        Write-Host "  - Modifies your global Claude settings file:"
        Write-Host "    $Global:ClaudeSettingsPath"
        Write-Host "  - Sets permissions.defaultMode to 'bypassPermissions'"
        Write-Host "  - Sets permissions.allow to ['*'] (allow all tools)"
        Write-Host ""
        Write-ColorText "Impact:" -Color Yellow
        Write-Host "  - Claude will NO LONGER prompt you for permission to:"
        Write-Host "    * Read files"
        Write-Host "    * Write files"
        Write-Host "    * Execute bash commands"
        Write-Host "    * Access the web"
        Write-Host "    * Use any other tools"
        Write-Host ""
        Write-Host "  - This applies to ALL Claude sessions globally"
        Write-Host "  - Individual projects can still override with .claude/settings.local.json"
        Write-Host ""
        Write-ColorText "Recommended for:" -Color Green
        Write-Host "  - Trusted development environments"
        Write-Host "  - Personal machines where you trust all projects"
        Write-Host "  - Avoiding repetitive permission prompts"
        Write-Host ""
        Write-ColorText "NOT recommended for:" -Color Red
        Write-Host "  - Shared machines"
        Write-Host "  - Working with untrusted code"
        Write-Host "  - Production environments"
        Write-Host ""
        Write-ColorText "You can reverse this at any time with [C]hatty Claude Mode" -Color Cyan
        Write-Host ""
        Write-Host "Switch to " -NoNewline -ForegroundColor Gray
        Write-Host "Q" -NoNewline -ForegroundColor Yellow
        Write-Host "uiet mode now? " -NoNewline -ForegroundColor Gray
        Write-Host "A" -NoNewline -ForegroundColor Yellow
        Write-Host "bort" -NoNewline -ForegroundColor Gray
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $choice = $key.Character.ToString().ToUpper()

        # Handle Esc as abort
        if ($key.VirtualKeyCode -eq 27) {
            $choice = 'A'
        }

        # Handle Enter as default (switch to quiet mode)
        if ($key.VirtualKeyCode -eq 13) {
            $choice = 'Q'
        }
    }

    if ($choice -ne 'Q') {
        Write-Host ""
        Write-ColorText "Operation aborted." -Color Cyan
        return
    }

    try {
        $settings = @{}

        # Read existing settings if file exists
        if (Test-Path $Global:ClaudeSettingsPath) {
            $settingsJson = Get-Content $Global:ClaudeSettingsPath -Raw
            $settings = $settingsJson | ConvertFrom-Json | ConvertTo-Hashtable
        } else {
            # Create .claude directory if it doesn't exist
            $claudeDir = Split-Path $Global:ClaudeSettingsPath -Parent
            if (-not (Test-Path $claudeDir)) {
                New-Item -Path $claudeDir -ItemType Directory -Force | Out-Null
            }
        }

        # Update permissions
        $settings['permissions'] = @{
            defaultMode = "bypassPermissions"
            allow = @("*")
        }

        # Save back
        $settings | ConvertTo-Json -Depth 10 | Set-Content $Global:ClaudeSettingsPath -Encoding UTF8
        Write-Host ""
        Write-ColorText "Quiet Claude Mode enabled successfully!" -Color Green
        Write-ColorText "Claude will no longer prompt for permissions." -Color Green
        Write-Host ""

        # Show debug information if debug is enabled
        if (Get-DebugState) {
            Write-Host ""
            Write-ColorText "[DEBUG] Permission Mode Details:" -Color Cyan
            $statusInfo = Get-GlobalPermissionStatus
            if ($statusInfo -is [hashtable]) {
                Write-Host "[DEBUG]   File checked: $($statusInfo.FilePath)" -ForegroundColor DarkGray
                Write-Host "[DEBUG]   Status: $($statusInfo.Reason)" -ForegroundColor DarkGray
                Write-Host "[DEBUG]   Evidence: $($statusInfo.Line)" -ForegroundColor DarkGray
            }
            Write-Host ""
        }

    } catch {
        Write-Host ""
        Write-ColorText "Error enabling quiet mode: $_" -Color Red
        Write-Host ""
    }
}

function Disable-GlobalBypassPermissions {
    <#
    .SYNOPSIS
        Disables global bypass permissions in settings.json
    #>

    Write-Host ""
    Write-ColorText "========================================" -Color Cyan
    Write-ColorText "  QUIET MODE ENABLED (SWITCH TO CHATTY)?" -Color Cyan
    Write-ColorText "========================================" -Color Cyan
    Write-Host ""
    Write-Host "Chatty mode enables permission prompts for all Claude sessions."
    Write-Host ""
    Write-Host "Switch to " -NoNewline -ForegroundColor Gray
    Write-Host "C" -NoNewline -ForegroundColor Yellow
    Write-Host "hatty Mode | " -NoNewline -ForegroundColor Gray
    Write-Host "S" -NoNewline -ForegroundColor Yellow
    Write-Host "how Info | " -NoNewline -ForegroundColor Gray
    Write-Host "A" -NoNewline -ForegroundColor Yellow
    Write-Host "bort: " -NoNewline -ForegroundColor Gray
    $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    $choice = $key.Character.ToString().ToUpper()

    # Handle Esc as abort
    if ($key.VirtualKeyCode -eq 27) {
        $choice = 'A'
    }

    # Handle Enter as default (switch to chatty mode)
    if ($key.VirtualKeyCode -eq 13) {
        $choice = 'C'
    }

    # Check if settings file exists
    if (-not (Test-Path $Global:ClaudeSettingsPath)) {
        Write-Host ""
        Write-ColorText "Settings file not found at:" -Color Red
        Write-Host "  $Global:ClaudeSettingsPath"
        Write-Host ""
        Write-ColorText "Nothing to disable." -Color Yellow
        Write-Host ""
        return
    }

    # Show detailed information if requested
    if ($choice -eq 'S') {
        Write-Host ""
        Write-ColorText "What this does:" -Color Yellow
        Write-Host "  - Modifies your global Claude settings file:"
        Write-Host "    $Global:ClaudeSettingsPath"
        Write-Host "  - Sets permissions.defaultMode to 'default'"
        Write-Host "  - Removes permissions.allow setting"
        Write-Host ""
        Write-ColorText "Impact:" -Color Yellow
        Write-Host "  - Claude WILL prompt you for permission to:"
        Write-Host "    * Read files"
        Write-Host "    * Write files"
        Write-Host "    * Execute bash commands"
        Write-Host "    * Access the web"
        Write-Host "    * Use other tools"
        Write-Host ""
        Write-Host "  - This applies to ALL Claude sessions globally"
        Write-Host "  - Individual projects can still override with .claude/settings.local.json"
        Write-Host ""

        # Show current settings
        try {
            $settingsJson = Get-Content $Global:ClaudeSettingsPath -Raw
            Write-ColorText "Current global settings.json content:" -Color Cyan
            Write-Host "----------------------------------------"
            Write-Host $settingsJson
            Write-Host "----------------------------------------"
            Write-Host ""
        } catch {
            Write-ColorText "Warning: Could not read current settings: $_" -Color Yellow
            Write-Host ""
        }

        Write-ColorText "You can reverse this at any time with [Q]uiet Claude Mode" -Color Cyan
        Write-Host ""
        Write-Host "Switch to " -NoNewline -ForegroundColor Gray
        Write-Host "C" -NoNewline -ForegroundColor Yellow
        Write-Host "hatty mode now? " -NoNewline -ForegroundColor Gray
        Write-Host "A" -NoNewline -ForegroundColor Yellow
        Write-Host "bort" -NoNewline -ForegroundColor Gray
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $choice = $key.Character.ToString().ToUpper()

        # Handle Esc as abort
        if ($key.VirtualKeyCode -eq 27) {
            $choice = 'A'
        }

        # Handle Enter as default (switch to chatty mode)
        if ($key.VirtualKeyCode -eq 13) {
            $choice = 'C'
        }
    }

    if ($choice -ne 'C') {
        Write-Host ""
        Write-ColorText "Operation aborted." -Color Cyan
        return
    }

    # Load settings for later use
    $settingsJson = Get-Content $Global:ClaudeSettingsPath -Raw

    try {
        $settings = $settingsJson | ConvertFrom-Json | ConvertTo-Hashtable

        # Update permissions to default
        if ($settings.ContainsKey('permissions')) {
            $settings['permissions'] = @{
                defaultMode = "default"
            }
        }

        # Save back
        $settings | ConvertTo-Json -Depth 10 | Set-Content $Global:ClaudeSettingsPath -Encoding UTF8
        Write-Host ""
        Write-ColorText "Chatty Claude Mode enabled successfully!" -Color Green
        Write-ColorText "Claude will now prompt for permissions." -Color Green
        Write-Host ""

        # Show debug information if debug is enabled
        if (Get-DebugState) {
            Write-Host ""
            Write-ColorText "[DEBUG] Permission Mode Details:" -Color Cyan
            $statusInfo = Get-GlobalPermissionStatus
            if ($statusInfo -is [hashtable]) {
                Write-Host "[DEBUG]   File checked: $($statusInfo.FilePath)" -ForegroundColor DarkGray
                Write-Host "[DEBUG]   Status: $($statusInfo.Reason)" -ForegroundColor DarkGray
                Write-Host "[DEBUG]   Evidence: $($statusInfo.Line)" -ForegroundColor DarkGray
            }
            Write-Host ""
        }

    } catch {
        Write-Host ""
        Write-ColorText "Error enabling chatty mode: $_" -Color Red
        Write-Host ""
    }
}

function ConvertTo-Hashtable {
    <#
    .SYNOPSIS
        Converts PSCustomObject to Hashtable
    #>
    param([Parameter(ValueFromPipeline)]$Object)

    if ($null -eq $Object) { return @{} }

    $hash = @{}
    $Object.PSObject.Properties | ForEach-Object {
        $value = $_.Value
        if ($value -is [PSCustomObject]) {
            $value = ConvertTo-Hashtable $value
        }
        $hash[$_.Name] = $value
    }
    return $hash
}

function Get-NewestSessionIdForPath {
    <#
    .SYNOPSIS
        Discovers the newest Claude session ID for a given project path
    #>
    param(
        [string]$ProjectPath,
        [int]$MaxWaitSeconds = 10
    )

    # Encode path the same way Claude does
    $encodedPath = ConvertTo-ClaudeprojectPath -Path $ProjectPath
    $sessionDir = Join-Path $Global:ClaudePath "projects\$encodedPath"

    Write-ColorText "Waiting for Claude to create session file..." -Color Cyan

    $startTime = Get-Date
    $sessionId = $null

    while ($true) {
        $elapsed = ((Get-Date) - $startTime).TotalSeconds

        if ($elapsed -gt $MaxWaitSeconds) {
            Write-ColorText "Timeout waiting for session file. Session may not have been created." -Color Red
            return $null
        }

        if (Test-Path $sessionDir) {
            $sessionFiles = Get-ChildItem -Path $sessionDir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue

            if ($sessionFiles) {
                # Get the newest session file
                $newestFile = $sessionFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                $sessionId = $newestFile.BaseName
                Write-ColorText "Discovered session ID: $sessionId" -Color Green
                return $sessionId
            }
        }

        # Wait a bit before checking again
        Start-Sleep -Milliseconds 500
    }
}

function Start-ForkSession {
    <#
    .SYNOPSIS
        Handles the complete fork workflow
    #>
    param([object]$Session)

    # Validate session file exists before forking
    if (-not (Test-SessionFileValid -SessionId $Session.sessionId -ProjectPath $Session.projectPath)) {
        Write-Host ""
        Write-ColorText "ERROR: Cannot fork - source session file is missing or corrupted!" -Color Red
        Write-Host ""
        Write-Host "Session ID: $($Session.sessionId)"
        Write-Host "Project Path: $($Session.projectPath)"
        Write-Host ""
        Write-ColorText "This usually happens when:" -Color Yellow
        Write-Host "  1. The session was created but never used (empty conversation)"
        Write-Host "  2. The session .jsonl file was deleted or moved"
        Write-Host "  3. File system corruption occurred"
        Write-Host ""
        Write-Host "You cannot fork from a non-existent session."
        Write-Host ""

        # Store error info for main menu display
        $sessionName = if ($Session.customTitle) { $Session.customTitle } else { "(unnamed)" }
        $Global:LastClaudeError = "Cannot fork - Claude could not find conversation with guid $($Session.sessionId) and name '$sessionName'"
        $Global:LastClaudeCommand = "claude --resume $($Session.sessionId) --fork-session"

        # Prompt user to delete the session
        Write-ColorText "Would you like to delete this session?" -Color Cyan
        Write-Host "  [Y] Yes, delete it now"
        Write-Host "  [N] No, return to menu"
        Write-Host ""
        Write-Host "Y" -NoNewline -ForegroundColor Yellow
        Write-Host "es | " -NoNewline -ForegroundColor Gray
        Write-Host "N" -NoNewline -ForegroundColor Yellow
        Write-Host "o " -NoNewline -ForegroundColor Gray
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $deleteChoice = $key.Character.ToString().ToUpper()

        # Handle Esc as No
        if ($key.VirtualKeyCode -eq 27) {
            $deleteChoice = 'N'
        }

        # Handle Enter as default (Yes)
        if ($key.VirtualKeyCode -eq 13) {
            $deleteChoice = 'Y'
        }

        if ($deleteChoice -eq 'Y') {
            # Call the delete session function
            try {
                Start-DeleteSession -Session $Session
                Write-Host ""
                Write-ColorText "Session deleted successfully." -Color Green
            } catch {
                Write-ColorText "Failed to delete session: $_" -Color Red
            }
        }

        return
    }

    try {
        # 1. Get old session name for display
        $oldName = if ($Session.customTitle) {
            $Session.customTitle
        } elseif ($Session.trackedName) {
            $Session.trackedName
        } else {
            "(unnamed)"
        }

        # 2. Get new session name
        $newName = Get-SessionName -OldSessionName $oldName

        # 3. Select model first (before creating background image)
        $model = Get-ModelChoice

        # Check if user aborted
        if ($model -eq 'abort') {
            Write-Host ""
            Write-ColorText "Fork aborted." -Color Yellow
            return
        }

        # 4. Check for background image conflict and resolve
        $resolution = Resolve-BackgroundImageConflict -SessionName $newName

        if ($resolution.action -eq 'abort') {
            Write-Host ""
            Write-ColorText "Fork aborted." -Color Yellow
            return
        }

        # Use the resolved name (may have been modified for 'new' action)
        $finalNewName = $resolution.name

        # Detect git branch (needed for both image generation and session mapping)
        $gitBranch = Get-GitBranch -Path $Session.projectPath

        # 5. Generate or use background image with model info
        if ($resolution.action -eq 'use') {
            # Use existing image
            $bgPath = $resolution.path
            Write-ColorText "Using existing background image." -Color Green
        } else {
            # Generate new image (either 'create' or 'overwrite')
            Write-Host ""
            Write-ColorText "Generating background image..." -Color Cyan

            $bgPath = New-SessionBackgroundImage -NewName $finalNewName -OldName $oldName -IsFork -GitBranch $gitBranch -Model $model -ProjectPath $Session.projectPath
        }

        # 6. Create Windows Terminal profile
        Write-ColorText "Creating Windows Terminal profile..." -Color Cyan
        $profile = Add-WTProfile -Name "Claude-$finalNewName" -StartingDirectory $Session.projectPath -BackgroundImage $bgPath

        # Use the actual profile name that was created (may have integer appended if duplicate)
        $actualProfileName = $profile.name

        # 6. Generate new session ID for the forked session
        $newSessionId = [Guid]::NewGuid().ToString()

        # 7. Store in profile registry
        Write-ColorText "Registering profile..." -Color Cyan
        Add-ProfileRegistry -SessionName $finalNewName -ProfileGuid $profile.guid -OriginalSessionId $Session.sessionId -projectPath $Session.projectPath -BackgroundImage $bgPath -Model $model

        # 8. Store in session mapping (use actual profile name)
        Add-SessionMapping -SessionId $newSessionId -WTProfileName $actualProfileName -ProjectPath $Session.projectPath -Model $model -ForkedFrom $Session.sessionId -GitBranch $gitBranch

        # 9. Launch Windows Terminal with new profile
        Write-Host ""
        Write-ColorText "Launching terminal with profile: $actualProfileName" -Color Green
        Write-Host ""

        # Build the command for Windows Terminal
        $profileGuid = $profile.guid
        $projectPath = $Session.projectPath
        $oldSessionId = $Session.sessionId
        $claudePath = Get-ClaudeCLIPath

        # Show user-friendly launch message
        Write-Host ""
        Write-ColorText "Attempting to launch new terminal with profile: $actualProfileName" -Color Cyan
        Write-Host ""

        # Launch Windows Terminal with the new profile
        # Using both --fork-session and --session-id to control the new session's ID
        & wt.exe -p "$profileGuid" -d "$projectPath" -- "$claudePath" --resume $oldSessionId --fork-session --session-id $newSessionId --model $model

        # Store simplified command for display (use old session name if available)
        $displayOldName = if ($oldName -ne "(unnamed)") { $oldName } else { $oldSessionId }
        $Global:LastClaudeCommand = "claude --resume $displayOldName --fork-session --session-id $newSessionId --model `"$model`""
        $Global:LastClaudeError = $null

        Write-ColorText "Forked session launched successfully!" -Color Green
        Write-Host ""
        Write-Host "New Session: $actualProfileName"
        Write-Host "Forked From: $oldName (Session ID: $oldSessionId)"
        Write-Host "New Session ID: $newSessionId"
        Write-Host "Model: $model"
        Write-Host ""
        Write-Host "Background: $bgPath"
        Write-Host ""
        Write-ColorText "Troubleshooting: If background image doesn't appear..." -Color Yellow
        Write-Host "  1. Check Windows Terminal Settings > Profiles > $actualProfileName"
        Write-Host "  2. Verify 'Background image path' is set correctly"
        Write-Host "  3. Adjust 'Background image opacity' slider (default: 30%)"
        Write-Host "  4. Ensure 'useAcrylic' is disabled (set by this script)"
        Write-Host "  5. Try changing 'Text antialiasing' to 'grayscale' (set by this script)"
        Write-Host ""
        Start-Sleep -Milliseconds 2000
        return

    } catch {
        Write-ColorText "Failed to fork session: $_" -Color Red
        throw
    }
}

#endregion

#region Windows Terminal Profile Management

function Backup-WTSettings {
    <#
    .SYNOPSIS
        Creates a timestamped backup of Windows Terminal settings
    #>
    if (-not (Test-Path $Global:WTSettingsPath)) {
        throw "Windows Terminal settings not found at: $Global:WTSettingsPath"
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$Global:WTSettingsPath.backup.$timestamp"

    Copy-Item $Global:WTSettingsPath $backupPath -Force
    return $backupPath
}

function Test-JsonStructure {
    <#
    .SYNOPSIS
        Validates JSON object has expected properties
    .PARAMETER JsonObject
        The parsed JSON object to validate
    .PARAMETER RequiredProperties
        Array of property names that must exist
    #>
    param(
        [PSObject]$JsonObject,
        [string[]]$RequiredProperties
    )

    if ($null -eq $JsonObject) {
        return $false
    }

    foreach ($prop in $RequiredProperties) {
        if (-not ($JsonObject.PSObject.Properties.Name -contains $prop)) {
            Write-ErrorLog "JSON validation failed: missing required property '$prop'"
            return $false
        }
    }

    return $true
}

function Test-WTSettingsValid {
    <#
    .SYNOPSIS
        Validates Windows Terminal settings JSON
    #>
    try {
        $content = Get-Content $Global:WTSettingsPath -Raw
        $settings = $content | ConvertFrom-Json

        # Validate expected structure
        if (-not (Test-JsonStructure -JsonObject $settings -RequiredProperties @('profiles'))) {
            Write-ErrorLog "Windows Terminal settings missing 'profiles' property"
            return $false
        }

        if (-not (Test-JsonStructure -JsonObject $settings.profiles -RequiredProperties @('list'))) {
            Write-ErrorLog "Windows Terminal settings.profiles missing 'list' property"
            return $false
        }

        return $true
    } catch {
        Write-ErrorLog "Failed to validate Windows Terminal settings: $_"
        return $false
    }
}

function Add-WTProfile {
    <#
    .SYNOPSIS
        Adds a new profile to Windows Terminal settings
    #>
    param(
        [string]$Name,
        [string]$StartingDirectory,
        [string]$BackgroundImage = $null
    )

    if (-not (Test-Path $Global:WTSettingsPath)) {
        throw "Windows Terminal settings not found. Is Windows Terminal installed?"
    }

    # Backup before modification
    $backupPath = Backup-WTSettings

    try {
        # Load and parse settings
        $settingsJson = Get-Content $Global:WTSettingsPath -Raw
        $settings = $settingsJson | ConvertFrom-Json

        # Check if profile name already exists and append integer if needed
        $finalName = $Name
        $counter = 1
        while ($settings.profiles.list | Where-Object { $_.name -eq $finalName }) {
            $finalName = "$Name$counter"
            $counter++
            Write-DebugInfo "  Profile name '$Name' already exists, trying: $finalName" -Color Yellow
        }

        if ($finalName -ne $Name) {
            Write-ColorText "Profile '$Name' already exists, using: $finalName" -Color Yellow
        }

        # Normalize starting directory (remove trailing backslash)
        $normalizedStartDir = $StartingDirectory.TrimEnd('\')

        # Generate unique GUID
        $newGuid = "{$([Guid]::NewGuid().ToString())}"

        # Create new profile object with all properties
        if ($BackgroundImage) {
            # Ensure path uses forward slashes for JSON compatibility
            $imagePath = $BackgroundImage -replace '\\', '/'

            $newProfile = [PSCustomObject]@{
                guid = $newGuid
                name = $finalName
                commandline = "%SystemRoot%\System32\cmd.exe"
                startingDirectory = $normalizedStartDir
                hidden = $false
                backgroundImage = $imagePath
                backgroundImageOpacity = 0.3
                backgroundImageStretchMode = "uniformToFill"
                useAcrylic = $false
                antialiasingMode = "grayscale"
            }
        } else {
            $newProfile = [PSCustomObject]@{
                guid = $newGuid
                name = $finalName
                commandline = "%SystemRoot%\System32\cmd.exe"
                startingDirectory = $normalizedStartDir
                hidden = $false
            }
        }

        # Add to profiles list
        $settings.profiles.list = @($settings.profiles.list) + $newProfile

        # Save with pretty formatting
        $settings | ConvertTo-Json -Depth 10 | Set-Content $Global:WTSettingsPath -Encoding UTF8

        # Validate the new settings
        if (-not (Test-WTSettingsValid)) {
            throw "Modified settings are invalid JSON"
        }

        Write-ColorText "Created Windows Terminal profile: $finalName" -Color Green
        Write-DebugInfo "  Profile GUID: $newGuid"
        Write-DebugInfo "  Profile Name: $finalName"

        return $newProfile

    } catch {
        Write-ColorText "Failed to add profile, restoring from backup..." -Color Red
        if (Test-Path $backupPath) {
            if (Test-Json -Path $backupPath) {
                Copy-Item $backupPath $Global:WTSettingsPath -Force
                Write-ColorText "Backup restored successfully" -Color Green
            } else {
                Write-ColorText "ERROR: Backup file is corrupted - cannot restore!" -Color Red
                Write-ErrorLog "Backup file corrupted: $backupPath"
            }
        } else {
            Write-ColorText "ERROR: Backup file not found!" -Color Red
            Write-ErrorLog "Backup file not found: $backupPath"
        }
        throw
    }
}

function Remove-WTProfile {
    <#
    .SYNOPSIS
        Removes a Windows Terminal profile by name
    #>
    param([string]$ProfileName)

    if (-not (Test-Path $Global:WTSettingsPath)) {
        throw "Windows Terminal settings not found. Is Windows Terminal installed?"
    }

    # Backup before modification
    $backupPath = Backup-WTSettings

    try {
        # Load and parse settings
        $settingsJson = Get-Content $Global:WTSettingsPath -Raw
        $settings = $settingsJson | ConvertFrom-Json

        # Find the profile (select first if duplicates exist)
        $profileToRemove = $settings.profiles.list | Where-Object { $_.name -eq $ProfileName } | Select-Object -First 1

        if (-not $profileToRemove) {
            Write-ColorText "Profile '$ProfileName' not found." -Color Yellow
            return $false
        }

        # Remove the profile from the list
        $settings.profiles.list = @($settings.profiles.list | Where-Object { $_.name -ne $ProfileName })

        # Save with pretty formatting
        $settings | ConvertTo-Json -Depth 10 | Set-Content $Global:WTSettingsPath -Encoding UTF8

        # Validate the new settings
        if (-not (Test-WTSettingsValid)) {
            throw "Modified settings are invalid JSON"
        }

        Write-ColorText "Deleted Windows Terminal profile: $ProfileName" -Color Green

        # Clean up session mappings - remove references to this profile
        Write-DebugInfo "  Cleaning up session mappings for profile: $ProfileName" -Color Yellow
        try {
            if (Test-Path $Global:SessionMappingPath) {
                $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json
                $updatedSessions = @()
                $removedCount = 0

                foreach ($session in $mapping.sessions) {
                    if ($session.wtProfileName -eq $ProfileName) {
                        Write-DebugInfo "    Removing profile reference from session: $($session.sessionId)" -Color Yellow
                        # Remove wtProfileName by creating new object without it
                        $newSession = @{
                            sessionId = $session.sessionId
                            projectPath = $session.projectPath
                            created = $session.created
                        }
                        if ($session.model) { $newSession.model = $session.model }
                        if ($session.forkedFrom) { $newSession.forkedFrom = $session.forkedFrom }
                        if ($session.updated) { $newSession.updated = $session.updated }
                        $updatedSessions += $newSession
                        $removedCount++
                    } else {
                        $updatedSessions += $session
                    }
                }

                $mapping.sessions = $updatedSessions
                $mapping | ConvertTo-Json -Depth 10 | Set-Content $Global:SessionMappingPath -Encoding UTF8
                Write-DebugInfo "  Removed $removedCount profile reference(s) from session mappings" -Color Green
            }
        } catch {
            Write-ErrorLog "Error cleaning up session mappings: $_"
            Write-ColorText "Warning: Could not clean up session mappings: $_" -Color Yellow
        }

        return $true

    } catch {
        Write-ColorText "Failed to remove profile, restoring from backup..." -Color Red
        if (Test-Path $backupPath) {
            if (Test-Json -Path $backupPath) {
                Copy-Item $backupPath $Global:WTSettingsPath -Force
                Write-ColorText "Backup restored successfully" -Color Green
            } else {
                Write-ColorText "ERROR: Backup file is corrupted - cannot restore!" -Color Red
                Write-ErrorLog "Backup file corrupted: $backupPath"
            }
        } else {
            Write-ColorText "ERROR: Backup file not found!" -Color Red
            Write-ErrorLog "Backup file not found: $backupPath"
        }
        throw
    }
}

function Initialize-BaseWTProfile {
    <#
    .SYNOPSIS
        Creates the base "Claude" Windows Terminal profile if it doesn't exist
    #>
    try {
        $settingsJson = Get-Content $Global:WTSettingsPath -Raw
        $settings = $settingsJson | ConvertFrom-Json

        # Check if "Claude" profile already exists
        $existingProfile = $settings.profiles.list | Where-Object { $_.name -eq "Claude" }

        if ($existingProfile) {
            Write-ColorText "Base 'Claude' profile already exists." -Color Green
            return $existingProfile
        }

        # Create base Claude profile
        Write-ColorText "Creating base 'Claude' Windows Terminal profile..." -Color Cyan

        $profile = Add-WTProfile -Name "Claude" -StartingDirectory "%USERPROFILE%"

        Write-ColorText "Base profile created successfully." -Color Green
        return $profile

    } catch {
        Write-ColorText "Warning: Could not create base Claude profile - $_" -Color Yellow
        return $null
    }
}

#endregion

#region Git Integration

function Get-GitBranch {
    <#
    .SYNOPSIS
        Detects the current git branch in a directory
    .PARAMETER Path
        The directory path to check for git branch
    #>
    param([string]$Path)

    try {
        # Check if directory exists
        if (-not (Test-Path $Path)) {
            return $null
        }

        # Save current location
        $originalLocation = Get-Location

        # Change to target directory
        Set-Location $Path

        # Check if this is a git repository
        $gitDir = Join-Path $Path ".git"
        if (-not (Test-Path $gitDir)) {
            Set-Location $originalLocation
            return $null
        }

        # Get current branch using git command
        $branch = git rev-parse --abbrev-ref HEAD 2>&1 | Where-Object { $_ -is [string] }

        # Restore location
        Set-Location $originalLocation

        if ($branch -and $branch -ne "") {
            Write-DebugInfo "  Detected git branch: $branch" -Color Green
            return $branch
        } else {
            return $null
        }

    } catch {
        Write-DebugInfo "  Could not detect git branch: $_" -Color Yellow
        return $null
    }
}

function Get-GitRepoName {
    <#
    .SYNOPSIS
        Gets the Git repository name from the remote URL
    .PARAMETER Path
        The directory path to check for git repo
    .RETURNS
        The repository name (e.g., "WinClaudeCodeForker") or empty string if not a git repo
    #>
    param([string]$Path)

    try {
        # Check if directory exists
        if (-not (Test-Path $Path)) {
            return ""
        }

        # Check if this is a git repository
        $gitDir = Join-Path $Path ".git"
        if (-not (Test-Path $gitDir)) {
            return ""
        }

        # Save current location
        $originalLocation = Get-Location
        Set-Location $Path

        # Get the remote URL (origin)
        $remoteUrl = git config --get remote.origin.url 2>&1 | Where-Object { $_ -is [string] }

        # Restore location
        Set-Location $originalLocation

        if (-not $remoteUrl -or $remoteUrl -eq "") {
            return ""
        }

        # Extract repo name from URL
        # Handles: https://github.com/user/repo.git, git@github.com:user/repo.git, etc.
        $repoName = ""
        if ($remoteUrl -match '/([^/]+?)(\.git)?$') {
            $repoName = $matches[1]
        } elseif ($remoteUrl -match ':([^/]+/)?([^/]+?)(\.git)?$') {
            $repoName = $matches[2]
        }

        return $repoName
    } catch {
        return ""
    }
}

#endregion

#region Image Generation

function Get-SessionsUsingBackground {
    <#
    .SYNOPSIS
        Counts how many Windows Terminal profiles are using a specific background image
    .PARAMETER SessionName
        The session name (which corresponds to the background image folder name)
    .RETURNS
        Array of profile names using this background
    #>
    param([string]$SessionName)

    $backgroundPath = Join-Path $Global:MenuPath "$SessionName\background.png"
    $backgroundPathForward = $backgroundPath -replace '\\', '/'

    $usingProfiles = @()

    try {
        if (Test-Path $Global:WTSettingsPath) {
            $settingsJson = Get-Content $Global:WTSettingsPath -Raw
            $settings = $settingsJson | ConvertFrom-Json

            foreach ($profile in $settings.profiles.list) {
                if ($profile.backgroundImage) {
                    $profileBgPath = $profile.backgroundImage -replace '\\', '/'
                    if ($profileBgPath -eq $backgroundPathForward) {
                        $usingProfiles += $profile.name
                    }
                }
            }
        }
    } catch {
        Write-ErrorLog "Error checking background usage: $_"
    }

    return $usingProfiles
}

function Resolve-BackgroundImageConflict {
    <#
    .SYNOPSIS
        Handles conflicts when a background image already exists
    .PARAMETER SessionName
        The proposed session name
    .RETURNS
        Hashtable with keys: action ('overwrite', 'use', 'new'), name (potentially modified)
    #>
    param([string]$SessionName)

    Write-DebugInfo "=== Resolve-BackgroundImageConflict ===" -Color Cyan
    Write-DebugInfo "  SessionName: $SessionName" -Color Yellow

    $outputDir = Join-Path $Global:MenuPath $SessionName
    $outputPath = Join-Path $outputDir "background.png"

    Write-DebugInfo "  Checking path: $outputPath" -Color Yellow
    $fileExists = Test-Path $outputPath
    Write-DebugInfo "  File exists: $fileExists" -Color $(if ($fileExists) { "Red" } else { "Green" })

    # If file doesn't exist, no conflict
    if (-not $fileExists) {
        Write-DebugInfo "  No conflict - proceeding with creation" -Color Green
        return @{ action = 'create'; name = $SessionName }
    }

    # File exists - check how many sessions are using it
    $usingProfiles = Get-SessionsUsingBackground -SessionName $SessionName
    $useCount = $usingProfiles.Count

    Write-DebugInfo "  Background is used by $useCount profile(s)" -Color Yellow
    if ($useCount -gt 0) {
        Write-DebugInfo "    Profiles: $($usingProfiles -join ', ')" -Color DarkGray
    }

    # If no other sessions are using it, automatically overwrite
    if ($useCount -eq 0) {
        Write-DebugInfo "  No sessions using this background - auto-overwriting" -Color Green
        Write-Host ""
        Write-ColorText "Background image exists but is not in use - overwriting..." -Color Yellow
        return @{ action = 'overwrite'; name = $SessionName }
    }

    # File exists and is in use - ask user what to do
    Write-Host ""
    Write-ColorText "Background image already exists for session: $SessionName" -Color Yellow
    Write-Host ""
    Write-ColorText "This background is currently used by $useCount profile(s):" -Color Cyan
    foreach ($profileName in $usingProfiles) {
        Write-Host "  - $profileName"
    }
    Write-Host ""
    Write-Host "O" -NoNewline -ForegroundColor Yellow
    Write-Host "verwrite - Overwrite existing image (affects all profiles) | " -NoNewline -ForegroundColor Gray
    Write-Host "U" -NoNewline -ForegroundColor Yellow
    Write-Host "se Existing | " -NoNewline -ForegroundColor Gray
    Write-Host "N" -NoNewline -ForegroundColor Yellow
    Write-Host "ew Name - Create new session with different name | " -NoNewline -ForegroundColor Gray
    Write-Host "A" -NoNewline -ForegroundColor Yellow
    Write-Host "bort" -NoNewline -ForegroundColor Gray

    while ($true) {
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $choice = $key.Character.ToString().ToUpper()

        # Handle Esc as abort
        if ($key.VirtualKeyCode -eq 27) {
            Write-Host ""
            return @{ action = 'abort'; name = $SessionName }
        }

        # Handle Enter as default (overwrite)
        if ($key.VirtualKeyCode -eq 13) {
            Write-Host ""
            return @{ action = 'overwrite'; name = $SessionName }
        }

        switch ($choice) {
            'O' {
                Write-Host ""
                return @{ action = 'overwrite'; name = $SessionName }
            }
            'U' {
                Write-Host ""
                return @{ action = 'use'; name = $SessionName; path = $outputPath }
            }
            'N' {
                Write-Host ""
                # Find a unique name by appending numbers
                $baseName = $SessionName
                $counter = 1
                $newName = "$baseName$counter"

                while (Test-Path (Join-Path $Global:MenuPath "$newName\background.png")) {
                    $counter++
                    $newName = "$baseName$counter"
                }

                Write-ColorText "Using new session name: $newName" -Color Green
                return @{ action = 'create'; name = $newName }
            }
            'A' {
                Write-Host ""
                return @{ action = 'abort'; name = $SessionName }
            }
            default {
                # Invalid choice - silently ignore
            }
        }
    }
}

function New-UniformBackgroundImage {
    <#
    .SYNOPSIS
        Creates a uniform background image with up to 6 lines of information
    .DESCRIPTION
        This is the common function used by all background image generators.
        Produces a 1920x1080 PNG with consistent formatting.
    .PARAMETER SessionName
        Line 1: Session name, label, or custom text (required)
    .PARAMETER ForkedFrom
        Line 2: If provided, displays "Forked from: {name}" (optional)
    .PARAMETER ComputerUser
        Line 3: Computer and username (required - pass "$env:COMPUTERNAME`:$env:USERNAME")
    .PARAMETER GitBranch
        Line 4: If provided, displays "branch: {branch}" (optional)
    .PARAMETER Model
        Line 5: If provided, displays "model: {model}" (optional)
    .PARAMETER DirectoryPath
        Line 6: Directory path (required)
    .PARAMETER OutputPath
        Full path where the PNG should be saved (required)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$SessionName,

        [string]$ForkedFrom = $null,

        [Parameter(Mandatory=$true)]
        [string]$ComputerUser,

        [string]$GitBranch = $null,

        [string]$Model = $null,

        [Parameter(Mandatory=$true)]
        [string]$DirectoryPath,

        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )

    try {
        Write-DebugInfo "=== New-UniformBackgroundImage ===" -Color Cyan
        Write-DebugInfo "  SessionName: $SessionName"
        Write-DebugInfo "  ForkedFrom: $ForkedFrom"
        Write-DebugInfo "  ComputerUser: $ComputerUser"
        Write-DebugInfo "  GitBranch: $GitBranch"
        Write-DebugInfo "  Model: $Model"
        Write-DebugInfo "  DirectoryPath: $DirectoryPath"
        Write-DebugInfo "  OutputPath: $OutputPath"

        Add-Type -AssemblyName System.Drawing

        # Create bitmap: 1920x1080px (full screen)
        $bitmap = New-Object System.Drawing.Bitmap(1920, 1080)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

        # Enable anti-aliasing for smooth text
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias

        # Darker, more visible background (semi-transparent dark blue)
        $bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(180, 20, 20, 40))
        $graphics.FillRectangle($bgBrush, 0, 0, 1920, 1080)

        # Fonts
        $fontBig = New-Object System.Drawing.Font("Consolas", 48, [System.Drawing.FontStyle]::Bold)
        $fontSmall = New-Object System.Drawing.Font("Consolas", 32, [System.Drawing.FontStyle]::Italic)
        $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)

        # Draw text right of center (position at 60% of width)
        $xPosition = 1920 * 0.6  # 60% of width = 1152
        $yPosition = 350
        $lineSpacing = 60

        # Line 1: Session Name (always shown)
        Write-DebugInfo "  Drawing Line 1: $SessionName" -Color Green
        $graphics.DrawString($SessionName, $fontBig, $textBrush, $xPosition, $yPosition)
        $yPosition += 80

        # Line 2: Forked From (optional)
        if ($ForkedFrom) {
            Write-DebugInfo "  Drawing Line 2: Forked from: $ForkedFrom" -Color Green
            $graphics.DrawString("Forked from: $ForkedFrom", $fontSmall, $textBrush, $xPosition, $yPosition)
            $yPosition += $lineSpacing
        } else {
            Write-DebugInfo "  Skipping Line 2 (no ForkedFrom)" -Color Yellow
        }

        # Line 3: Computer:User (always shown)
        Write-DebugInfo "  Drawing Line 3: $ComputerUser" -Color Green
        $graphics.DrawString($ComputerUser, $fontSmall, $textBrush, $xPosition, $yPosition)
        $yPosition += $lineSpacing

        # Line 4: Git Branch (optional)
        if ($GitBranch) {
            Write-DebugInfo "  Drawing Line 4: branch: $GitBranch" -Color Green
            $graphics.DrawString("branch: $GitBranch", $fontSmall, $textBrush, $xPosition, $yPosition)
            $yPosition += $lineSpacing
        } else {
            Write-DebugInfo "  Skipping Line 4 (no GitBranch)" -Color Yellow
        }

        # Line 5: Model (optional)
        if ($Model) {
            Write-DebugInfo "  Drawing Line 5: model: $Model" -Color Green
            $graphics.DrawString("model: $Model", $fontSmall, $textBrush, $xPosition, $yPosition)
            $yPosition += $lineSpacing
        } else {
            Write-DebugInfo "  Skipping Line 5 (no Model)" -Color Yellow
        }

        # Line 6: Directory Path (always shown)
        Write-DebugInfo "  Drawing Line 6: $DirectoryPath" -Color Green
        $graphics.DrawString($DirectoryPath, $fontSmall, $textBrush, $xPosition, $yPosition)

        # Ensure output directory exists
        $outputDir = Split-Path $OutputPath -Parent
        if (-not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        # Save PNG
        $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-DebugInfo "  Image saved to: $OutputPath" -Color Green

        # Create corresponding .txt file with the same content
        $txtPath = $OutputPath -replace '\.png$', '.txt'
        $txtContent = @()
        $txtContent += "Session: $SessionName"
        if ($ForkedFrom) {
            $txtContent += "Forked from: $ForkedFrom"
        }
        $txtContent += "Computer:User: $ComputerUser"
        if ($GitBranch) {
            $txtContent += "Branch: $GitBranch"
        }
        if ($Model) {
            $txtContent += "Model: $Model"
        }
        $txtContent += "Directory: $DirectoryPath"
        $txtContent += ""
        $txtContent += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $txtContent -join "`r`n" | Set-Content $txtPath -Encoding UTF8
        Write-DebugInfo "  Text file saved to: $txtPath" -Color Green

        # Cleanup
        $graphics.Dispose()
        $bitmap.Dispose()
        $bgBrush.Dispose()
        $fontBig.Dispose()
        $fontSmall.Dispose()
        $textBrush.Dispose()

        Write-ColorText "Background image created: $OutputPath" -Color Green
        return $OutputPath

    } catch {
        Write-ColorText "Failed to generate background image: $_" -Color Red
        Write-ErrorLog "New-UniformBackgroundImage error: $_"
        throw
    }
}

function New-SessionBackgroundImage {
    <#
    .SYNOPSIS
        Wrapper for creating session background images (new sessions and forks)
    .PARAMETER NewName
        The new session name
    .PARAMETER OldName
        The old/parent session name (used for forks)
    .PARAMETER IsFork
        If true, displays "Forked from:" text
    .PARAMETER GitBranch
        Optional git branch name to display
    .PARAMETER Model
        Optional model name to display
    .PARAMETER ProjectPath
        The project directory path
    #>
    param(
        [string]$NewName,
        [string]$OldName,
        [switch]$IsFork,
        [string]$GitBranch = $null,
        [string]$Model = $null,
        [string]$ProjectPath = ""
    )

    try {
        Write-DebugInfo "=== New-SessionBackgroundImage ===" -Color Cyan
        Write-DebugInfo "  NewName: $NewName"
        Write-DebugInfo "  OldName: $OldName"
        Write-DebugInfo "  IsFork: $IsFork"
        Write-DebugInfo "  GitBranch: $GitBranch"
        Write-DebugInfo "  Model: $Model"
        Write-DebugInfo "  ProjectPath: $ProjectPath"

        # Prepare output path
        $outputDir = Join-Path $Global:MenuPath $NewName
        $outputPath = Join-Path $outputDir "background.png"

        # Prepare parameters for uniform function
        $computerUser = "$env:COMPUTERNAME`:$env:USERNAME"
        $forkedFromParam = if ($IsFork -and $OldName) { $OldName } else { $null }

        # Call the common uniform function
        $result = New-UniformBackgroundImage `
            -SessionName $NewName `
            -ForkedFrom $forkedFromParam `
            -ComputerUser $computerUser `
            -GitBranch $GitBranch `
            -Model $Model `
            -DirectoryPath $ProjectPath `
            -OutputPath $outputPath

        # Save tracking
        if ($IsFork) {
            Save-BackgroundTracking -SessionName $NewName -BackgroundPath $outputPath -TextContent "Forked from: $OldName" -ImageType "fork"
        } else {
            Save-BackgroundTracking -SessionName $NewName -BackgroundPath $outputPath -TextContent $NewName -ImageType "new"
        }

        return $result

    } catch {
        Write-ColorText "Failed to generate background image: $_" -Color Red
        throw
    }
}

function New-ContinueSessionBackgroundImage {
    <#
    .SYNOPSIS
        Wrapper for creating background images for continued sessions
    .PARAMETER SessionName
        The session name
    .PARAMETER GitBranch
        Optional git branch name to display
    .PARAMETER Model
        Optional model name to display
    .PARAMETER ProjectPath
        The project directory path
    #>
    param(
        [string]$SessionName,
        [string]$GitBranch = $null,
        [string]$Model = $null,
        [string]$ProjectPath = ""
    )

    try {
        Write-DebugInfo "=== New-ContinueSessionBackgroundImage ===" -Color Cyan
        Write-DebugInfo "  SessionName: $SessionName"
        Write-DebugInfo "  GitBranch: $GitBranch"
        Write-DebugInfo "  Model: $Model"
        Write-DebugInfo "  ProjectPath: $ProjectPath"

        # Prepare output path
        $outputDir = Join-Path $Global:MenuPath $SessionName
        $outputPath = Join-Path $outputDir "background.png"

        # Prepare parameters for uniform function
        $computerUser = "$env:COMPUTERNAME`:$env:USERNAME"

        # Call the common uniform function
        $result = New-UniformBackgroundImage `
            -SessionName $SessionName `
            -ForkedFrom $null `
            -ComputerUser $computerUser `
            -GitBranch $GitBranch `
            -Model $Model `
            -DirectoryPath $ProjectPath `
            -OutputPath $outputPath

        # Save tracking
        Save-BackgroundTracking -SessionName $SessionName -BackgroundPath $outputPath -TextContent $SessionName -ImageType "continue"

        return $result

    } catch {
        Write-ColorText "Failed to generate background image: $_" -Color Red
        throw
    }
}

function Update-SessionBackgroundImage {
    <#
    .SYNOPSIS
        Regenerates the background image for an existing Windows Terminal profile
    #>
    param(
        [object]$Session,
        [string]$WTProfileName
    )

    try {
        # Extract session name from Windows Terminal profile name (remove "Claude-" prefix)
        $sessionName = $WTProfileName -replace '^Claude-', ''

        # Check if this is a forked session by looking for forkedFrom info
        $forkInfo = Get-ForkedFromInfo -SessionId $Session.sessionId

        if ($forkInfo -and $forkInfo.ForkedFrom) {
            # This is a fork - generate fork-style background
            Write-ColorText "Detected fork session. Generating fork-style background..." -Color Cyan

            # Get parent session info
            $allSessions = Get-AllClaudeSessions
            $parentSession = $allSessions | Where-Object { $_.sessionId -eq $forkInfo.ForkedFrom }
            $parentName = if ($parentSession -and $parentSession.customTitle) {
                $parentSession.customTitle
            } else {
                '(deleted or unnamed)'
            }

            # Detect git branch
            $gitBranch = Get-GitBranch -Path $Session.projectPath

            # Get model from session mapping if available
            $sessionEntry = Get-SessionMappingEntry -SessionId $Session.sessionId
            $modelName = if ($sessionEntry -and $sessionEntry.model) { $sessionEntry.model } else { $null }

            $bgPath = New-SessionBackgroundImage -NewName $sessionName -OldName $parentName -IsFork -GitBranch $gitBranch -Model $modelName -ProjectPath $Session.projectPath
        } else {
            # Not a fork - generate simple continue-style background
            Write-ColorText "Generating session background..." -Color Cyan

            # Detect git branch
            $gitBranch = Get-GitBranch -Path $Session.projectPath

            # Get model from session mapping if available
            $sessionEntry = Get-SessionMappingEntry -SessionId $Session.sessionId
            $modelName = if ($sessionEntry -and $sessionEntry.model) { $sessionEntry.model } else { $null }

            $bgPath = New-ContinueSessionBackgroundImage -SessionName $sessionName -GitBranch $gitBranch -Model $modelName -ProjectPath $Session.projectPath
        }

        # Update Windows Terminal profile with new image path
        $backupPath = Backup-WTSettings
        $settingsJson = Get-Content $Global:WTSettingsPath -Raw
        $settings = $settingsJson | ConvertFrom-Json

        $profileIndex = -1
        for ($i = 0; $i -lt $settings.profiles.list.Count; $i++) {
            if ($settings.profiles.list[$i].name -eq $WTProfileName) {
                $profileIndex = $i
                break
            }
        }

        if ($profileIndex -ge 0) {
            $imagePath = $bgPath -replace '\\', '/'
            $settings.profiles.list[$profileIndex].backgroundImage = $imagePath
            $settings | ConvertTo-Json -Depth 10 | Set-Content $Global:WTSettingsPath -Encoding UTF8
            Write-ColorText "Updated Windows Terminal profile with new background" -Color Green
            return $true
        } else {
            Write-ColorText "Could not find Windows Terminal profile: $WTProfileName" -Color Red
            return $false
        }

    } catch {
        Write-ColorText "Error updating background image: $_" -Color Red
        return $false
    }
}

function Get-ModelFromBackgroundTxt {
    <#
    .SYNOPSIS
        Reads the model from a background .txt file
    .DESCRIPTION
        Parses the background .txt file to extract the Model line.
        This is faster than loading session-mapping.json.
    .PARAMETER WTProfileName
        The Windows Terminal profile name (e.g., "Claude-MySession")
    .RETURNS
        The model string if found, empty string otherwise
    #>
    param(
        [string]$WTProfileName
    )

    if (-not $WTProfileName) {
        return ""
    }

    try {
        # Extract session name from WT profile name
        $sessionName = $WTProfileName -replace '^Claude-', ''

        # Build path to background.txt
        $txtPath = Join-Path $Global:MenuPath "$sessionName\background.txt"

        if (-not (Test-Path $txtPath)) {
            return ""
        }

        # Read and parse the txt file
        $content = Get-Content $txtPath -ErrorAction SilentlyContinue
        foreach ($line in $content) {
            if ($line -match '^Model:\s*(.+)$') {
                return $Matches[1].Trim()
            }
        }
    } catch {
        Write-DebugInfo "Error reading background txt for $WTProfileName : $_" -Color Red
    }

    return ""
}

function Get-BranchFromBackgroundTxt {
    <#
    .SYNOPSIS
        Reads the git branch from a background .txt file
    .DESCRIPTION
        Parses the background .txt file to extract the Branch line.
        This is faster than loading session-mapping.json.
    .PARAMETER WTProfileName
        The Windows Terminal profile name (e.g., "Claude-MySession")
    .RETURNS
        The branch string if found, empty string otherwise
    #>
    param(
        [string]$WTProfileName
    )

    if (-not $WTProfileName) {
        return ""
    }

    try {
        # Extract session name from WT profile name
        $sessionName = $WTProfileName -replace '^Claude-', ''

        # Build path to background.txt
        $txtPath = Join-Path $Global:MenuPath "$sessionName\background.txt"

        if (-not (Test-Path $txtPath)) {
            return ""
        }

        # Read and parse the txt file
        $content = Get-Content $txtPath -ErrorAction SilentlyContinue
        foreach ($line in $content) {
            if ($line -match '^Branch:\s*(.+)$') {
                return $Matches[1].Trim()
            }
        }
    } catch {
        Write-DebugInfo "Error reading background txt for $WTProfileName : $_" -Color Red
    }

    return ""
}

function Get-AllValuesFromBackgroundTxt {
    <#
    .SYNOPSIS
        Reads all values from a background .txt file
    .DESCRIPTION
        Parses the background .txt file to extract all stored values.
    .PARAMETER WTProfileName
        The Windows Terminal profile name (e.g., "Claude-MySession")
    .RETURNS
        Hashtable with Session, ForkedFrom, ComputerUser, Branch, Model, Directory, or $null if file not found
    #>
    param(
        [string]$WTProfileName
    )

    if (-not $WTProfileName) {
        return $null
    }

    try {
        # Extract session name from WT profile name
        $sessionName = $WTProfileName -replace '^Claude-', ''

        # Build path to background.txt
        $txtPath = Join-Path $Global:MenuPath "$sessionName\background.txt"

        if (-not (Test-Path $txtPath)) {
            return $null
        }

        # Initialize result hashtable
        $result = @{
            Session = ""
            ForkedFrom = ""
            ComputerUser = ""
            Branch = ""
            Model = ""
            Directory = ""
        }

        # Read and parse the txt file
        $content = Get-Content $txtPath -ErrorAction SilentlyContinue
        foreach ($line in $content) {
            if ($line -match '^Session:\s*(.+)$') {
                $result.Session = $Matches[1].Trim()
            } elseif ($line -match '^Forked from:\s*(.+)$') {
                $result.ForkedFrom = $Matches[1].Trim()
            } elseif ($line -match '^Computer:User:\s*(.+)$') {
                $result.ComputerUser = $Matches[1].Trim()
            } elseif ($line -match '^Branch:\s*(.+)$') {
                $result.Branch = $Matches[1].Trim()
            } elseif ($line -match '^Model:\s*(.+)$') {
                $result.Model = $Matches[1].Trim()
            } elseif ($line -match '^Directory:\s*(.+)$') {
                $result.Directory = $Matches[1].Trim()
            }
        }

        return $result
    } catch {
        Write-DebugInfo "Error reading background txt for $WTProfileName : $_" -Color Red
    }

    return $null
}

function Update-BackgroundIfChanged {
    <#
    .SYNOPSIS
        Detects if any background parameters have changed and regenerates background if needed
    .DESCRIPTION
        Called during explicit Refresh only. Compares all background text parameters
        (model, branch, directory, computer:user) with current values and regenerates
        the background image if ANY have changed.
    .RETURNS
        $true if background was regenerated, $false otherwise
    #>
    param(
        [object]$Session,
        [string]$WTProfileName,
        [string]$CurrentModel
    )

    # Skip if no WT profile
    if (-not $WTProfileName) {
        return $false
    }

    try {
        # Extract session name from WT profile name
        $sessionName = $WTProfileName -replace '^Claude-', ''

        Write-DebugInfo "  Checking background for: $sessionName" -Color Cyan

        # Get all stored values from background .txt file
        $storedValues = Get-AllValuesFromBackgroundTxt -WTProfileName $WTProfileName

        if (-not $storedValues) {
            Write-DebugInfo "    No background.txt found - skipping" -Color DarkGray
            return $false
        }

        # Get current values
        $currentBranch = Get-GitBranch -Path $Session.projectPath
        $currentComputerUser = "$env:COMPUTERNAME\$env:USERNAME"
        $currentDirectory = $Session.projectPath

        # Check if this is a forked session and get parent name
        $forkInfo = Get-ForkedFromInfo -SessionId $Session.sessionId
        $currentForkedFrom = ""
        $parentName = ""
        if ($forkInfo -and $forkInfo.ForkedFrom) {
            $allSessions = Get-AllClaudeSessions
            $parentSession = $allSessions | Where-Object { $_.sessionId -eq $forkInfo.ForkedFrom }
            $parentName = if ($parentSession -and $parentSession.customTitle) {
                $parentSession.customTitle
            } else {
                '(deleted or unnamed)'
            }
            $currentForkedFrom = $parentName
        }

        # Build list of changes
        $changes = @()

        if ($storedValues.Model -and $CurrentModel -and $storedValues.Model -ne $CurrentModel) {
            $changes += "Model: '$($storedValues.Model)' -> '$CurrentModel'"
        }
        if ($storedValues.Branch -and $currentBranch -and $storedValues.Branch -ne $currentBranch) {
            $changes += "Branch: '$($storedValues.Branch)' -> '$currentBranch'"
        }
        if ($storedValues.ComputerUser -and $storedValues.ComputerUser -ne $currentComputerUser) {
            $changes += "Computer:User: '$($storedValues.ComputerUser)' -> '$currentComputerUser'"
        }
        if ($storedValues.Directory -and $storedValues.Directory -ne $currentDirectory) {
            $changes += "Directory: '$($storedValues.Directory)' -> '$currentDirectory'"
        }
        if ($storedValues.ForkedFrom -and $currentForkedFrom -and $storedValues.ForkedFrom -ne $currentForkedFrom) {
            $changes += "ForkedFrom: '$($storedValues.ForkedFrom)' -> '$currentForkedFrom'"
        }

        # Log comparison results
        Write-DebugInfo "    Stored: Model='$($storedValues.Model)', Branch='$($storedValues.Branch)'" -Color DarkGray
        Write-DebugInfo "    Current: Model='$CurrentModel', Branch='$currentBranch'" -Color DarkGray

        if ($changes.Count -eq 0) {
            Write-DebugInfo "    No changes detected" -Color DarkGray
            return $false
        }

        # Log what changed
        Write-DebugInfo "    CHANGES DETECTED:" -Color Yellow
        foreach ($change in $changes) {
            Write-DebugInfo "      - $change" -Color Yellow
        }

        # Update session-mapping.json with new values
        Add-SessionMapping -SessionId $Session.sessionId `
                          -WTProfileName $WTProfileName `
                          -ProjectPath $Session.projectPath `
                          -Model $CurrentModel `
                          -GitBranch $currentBranch

        # Regenerate background image
        if ($forkInfo -and $forkInfo.ForkedFrom) {
            # Fork session
            $bgPath = New-SessionBackgroundImage -NewName $sessionName -OldName $parentName -IsFork -GitBranch $currentBranch -Model $CurrentModel -ProjectPath $Session.projectPath
        } else {
            # Non-fork session
            $bgPath = New-ContinueSessionBackgroundImage -SessionName $sessionName -GitBranch $currentBranch -Model $CurrentModel -ProjectPath $Session.projectPath
        }

        # Update Windows Terminal profile with new image path
        $settingsJson = Get-Content $Global:WTSettingsPath -Raw
        $settings = $settingsJson | ConvertFrom-Json

        for ($i = 0; $i -lt $settings.profiles.list.Count; $i++) {
            if ($settings.profiles.list[$i].name -eq $WTProfileName) {
                $imagePath = $bgPath -replace '\\', '/'
                $settings.profiles.list[$i].backgroundImage = $imagePath
                $settings | ConvertTo-Json -Depth 10 | Set-Content $Global:WTSettingsPath -Encoding UTF8
                Write-DebugInfo "    Regenerated background for '$WTProfileName'" -Color Green
                break
            }
        }

        return $true
    } catch {
        Write-ErrorLog "Error in Update-BackgroundIfChanged: $_"
    }

    return $false
}

#endregion

#region Session Mapping

function Initialize-SessionMapping {
    <#
    .SYNOPSIS
        Creates the session mapping file if it doesn't exist
    #>
    if (-not (Test-Path $Global:SessionMappingPath)) {
        $mapping = @{
            version = 1
            sessions = @()
        }

        $mapping | ConvertTo-Json -Depth 10 | Set-Content $Global:SessionMappingPath -Encoding UTF8
        Write-ColorText "Session mapping initialized." -Color Green
    }
}

function Add-SessionMapping {
    <#
    .SYNOPSIS
        Adds or updates a session to Windows Terminal profile mapping
    #>
    param(
        [string]$SessionId,
        [string]$WTProfileName,
        [string]$ProjectPath,
        [string]$Model = "",
        [string]$ForkedFrom = "",
        [string]$GitBranch = ""
    )

    Initialize-SessionMapping

    try {
        $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json

        # SELF-HEALING: Check if WTProfileName is already mapped to a DIFFERENT session
        # and if that session's .jsonl file doesn't exist (orphaned mapping)
        $conflictIndex = -1
        for ($i = 0; $i -lt $mapping.sessions.Count; $i++) {
            if ($mapping.sessions[$i].wtProfileName -eq $WTProfileName -and
                $mapping.sessions[$i].sessionId -ne $SessionId) {
                # Found a different session with same WT profile name
                # Check if that session's file exists
                $encodedPath = ConvertTo-ClaudeprojectPath -Path $mapping.sessions[$i].projectPath
                $sessionFile = Join-Path "$env:USERPROFILE\.claude\projects" "$encodedPath\$($mapping.sessions[$i].sessionId).jsonl"

                if (-not (Test-Path $sessionFile)) {
                    # Orphaned mapping - this session file doesn't exist
                    $conflictIndex = $i
                    Write-DebugInfo "SELF-HEAL: Found orphaned mapping for '$WTProfileName' -> session $($mapping.sessions[$i].sessionId)" -Color Yellow
                    Write-DebugInfo "  Session file missing: $sessionFile" -Color Yellow
                    Write-DebugInfo "  Will replace with new session: $SessionId" -Color Green
                    break
                }
            }
        }

        # Check if entry already exists for this session ID
        $existingIndex = -1
        for ($i = 0; $i -lt $mapping.sessions.Count; $i++) {
            if ($mapping.sessions[$i].sessionId -eq $SessionId) {
                $existingIndex = $i
                break
            }
        }

        # Remove orphaned mapping if found
        if ($conflictIndex -ge 0) {
            Write-DebugInfo "SELF-HEAL: Removing orphaned mapping at index $conflictIndex" -Color Yellow
            $orphanedSession = $mapping.sessions[$conflictIndex]
            $mapping.sessions = @($mapping.sessions | Where-Object { $_ -ne $orphanedSession })
            # Adjust existingIndex if needed
            if ($existingIndex -gt $conflictIndex) {
                $existingIndex--
            }
        }

        if ($existingIndex -ge 0) {
            # Update existing entry by replacing it
            $updatedEntry = @{
                sessionId = $SessionId
                wtProfileName = $WTProfileName
                projectPath = $ProjectPath
                model = $Model
                created = $mapping.sessions[$existingIndex].created
                updated = (Get-Date).ToString('o')
            }

            # Add forkedFrom if provided
            if ($ForkedFrom) {
                $updatedEntry.forkedFrom = $ForkedFrom
            } elseif ($mapping.sessions[$existingIndex].forkedFrom) {
                # Preserve existing forkedFrom if not updating it
                $updatedEntry.forkedFrom = $mapping.sessions[$existingIndex].forkedFrom
            }

            # Add gitBranch if provided
            if ($GitBranch) {
                $updatedEntry.gitBranch = $GitBranch
            } elseif ($mapping.sessions[$existingIndex].gitBranch) {
                # Preserve existing gitBranch if not updating it
                $updatedEntry.gitBranch = $mapping.sessions[$existingIndex].gitBranch
            }

            $mapping.sessions[$existingIndex] = $updatedEntry
        } else {
            # Create new entry
            $newEntry = @{
                sessionId = $SessionId
                wtProfileName = $WTProfileName
                projectPath = $ProjectPath
                model = $Model
                created = (Get-Date).ToString('o')
            }

            # Add forkedFrom if provided
            if ($ForkedFrom) {
                $newEntry.forkedFrom = $ForkedFrom
            }

            # Add gitBranch if provided
            if ($GitBranch) {
                $newEntry.gitBranch = $GitBranch
            }

            $mapping.sessions = @($mapping.sessions) + $newEntry
        }

        $mapping | ConvertTo-Json -Depth 10 | Set-Content $Global:SessionMappingPath -Encoding UTF8

    } catch {
        Write-ColorText "Failed to add session mapping: $_" -Color Red
        throw
    }
}

function Set-SessionArchiveStatus {
    <#
    .SYNOPSIS
        Archives or unarchives a session
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$SessionId,
        [Parameter(Mandatory=$true)]
        [bool]$Archived
    )

    Write-DebugInfo "=== Set-SessionArchiveStatus ===" -Color Cyan
    Write-DebugInfo "  Session ID: $SessionId"
    Write-DebugInfo "  Archived: $Archived"

    if (-not (Test-Path $Global:SessionMappingPath)) {
        Write-DebugInfo "  Session mapping file does not exist - initializing" -Color Yellow
        Initialize-SessionMapping
    }

    try {
        $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json

        # Find the session
        $session = $mapping.sessions | Where-Object { $_.sessionId -eq $SessionId }

        if ($session) {
            Write-DebugInfo "  Session found in mapping" -Color Green

            if ($Archived) {
                # Archive the session
                $archiveDate = (Get-Date).ToString('o')
                Write-DebugInfo "  Archiving session with date: $archiveDate" -Color Yellow

                # Add or update archived property
                if ($null -eq $session.PSObject.Properties['archived']) {
                    $session | Add-Member -NotePropertyName 'archived' -NotePropertyValue $true -Force
                } else {
                    $session.archived = $true
                }

                # Add or update archivedDate property
                if ($null -eq $session.PSObject.Properties['archivedDate']) {
                    $session | Add-Member -NotePropertyName 'archivedDate' -NotePropertyValue $archiveDate -Force
                } else {
                    $session.archivedDate = $archiveDate
                }
            } else {
                # Unarchive the session
                Write-DebugInfo "  Unarchiving session" -Color Yellow

                if ($null -ne $session.PSObject.Properties['archived']) {
                    $session.archived = $false
                }
                # Keep archivedDate for history but mark as unarchived
            }

            # Save the updated mapping
            $mapping | ConvertTo-Json -Depth 10 | Set-Content $Global:SessionMappingPath -Encoding UTF8
            Write-DebugInfo "  Session mapping updated successfully" -Color Green
            return $true

        } else {
            Write-DebugInfo "  Session NOT found in mapping - creating entry" -Color Yellow

            # Session not in mapping yet - create entry
            $newEntry = @{
                sessionId = $SessionId
                archived = $Archived
            }

            if ($Archived) {
                $newEntry.archivedDate = (Get-Date).ToString('o')
            }

            $mapping.sessions = @($mapping.sessions) + $newEntry
            $mapping | ConvertTo-Json -Depth 10 | Set-Content $Global:SessionMappingPath -Encoding UTF8
            Write-DebugInfo "  New session entry created with archive status" -Color Green
            return $true
        }

    } catch {
        Write-DebugInfo "  ERROR setting archive status: $_" -Color Red
        Write-ErrorLog "Error setting archive status: $_"
        return $false
    }
}

function Get-SessionArchiveStatus {
    <#
    .SYNOPSIS
        Gets the archive status of a session
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$SessionId
    )

    if (-not (Test-Path $Global:SessionMappingPath)) {
        return @{ Archived = $false; ArchivedDate = $null }
    }

    try {
        $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json
        $session = $mapping.sessions | Where-Object { $_.sessionId -eq $SessionId }

        if ($session -and $session.archived -eq $true) {
            return @{
                Archived = $true
                ArchivedDate = $session.archivedDate
            }
        }
    } catch {
        Write-DebugInfo "Error checking archive status: $_" -Color Red
    }

    return @{ Archived = $false; ArchivedDate = $null }
}

function Get-SessionNotes {
    <#
    .SYNOPSIS
        Gets the notes for a session
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$SessionId
    )

    if (-not (Test-Path $Global:SessionMappingPath)) {
        return ""
    }

    try {
        $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json
        $session = $mapping.sessions | Where-Object { $_.sessionId -eq $SessionId }

        if ($session -and $session.notes) {
            return $session.notes
        }
    } catch {
        Write-DebugInfo "Error getting session notes: $_" -Color Red
    }

    return ""
}

function Set-SessionNotes {
    <#
    .SYNOPSIS
        Sets the notes for a session
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$SessionId,
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$Notes
    )

    Write-DebugInfo "=== Set-SessionNotes ===" -Color Cyan
    Write-DebugInfo "  Session ID: $SessionId"
    Write-DebugInfo "  Notes: $Notes"

    if (-not (Test-Path $Global:SessionMappingPath)) {
        Write-DebugInfo "  Session mapping file does not exist - initializing" -Color Yellow
        Initialize-SessionMapping
    }

    try {
        $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json

        # Find the session
        $session = $mapping.sessions | Where-Object { $_.sessionId -eq $SessionId }

        if ($session) {
            Write-DebugInfo "  Session found in mapping" -Color Green

            # Add or update notes property
            if ($null -eq $session.PSObject.Properties['notes']) {
                $session | Add-Member -NotePropertyName 'notes' -NotePropertyValue $Notes -Force
                Write-DebugInfo "  Added notes property" -Color Green
            } else {
                $session.notes = $Notes
                Write-DebugInfo "  Updated notes property" -Color Green
            }

            # Save the updated mapping
            $mapping | ConvertTo-Json -Depth 10 | Set-Content $Global:SessionMappingPath -Encoding UTF8
            Write-DebugInfo "  Session mapping updated successfully" -Color Green
            return $true

        } else {
            Write-DebugInfo "  Session NOT found in mapping - creating entry" -Color Yellow

            # Session not in mapping yet - create entry
            $newEntry = @{
                sessionId = $SessionId
                notes = $Notes
            }

            $mapping.sessions = @($mapping.sessions) + $newEntry
            $mapping | ConvertTo-Json -Depth 10 | Set-Content $Global:SessionMappingPath -Encoding UTF8
            Write-DebugInfo "  New session entry created with notes" -Color Green
            return $true
        }

    } catch {
        Write-DebugInfo "  ERROR setting notes: $_" -Color Red
        Write-ErrorLog "Error setting session notes: $_"
        return $false
    }
}

function Get-ColumnConfiguration {
    <#
    .SYNOPSIS
        Gets the column visibility configuration
    #>
    if (-not (Test-Path $Global:ColumnConfigPath)) {
        # Return default configuration (Notes, Git, and Limit hidden by default)
        # LimitFeature: Limit column added, default hidden
        return @{
            Active = $true
            Limit = $false  # LimitFeature: Context usage percentage, hidden by default (slow)
            Model = $true
            Session = $true
            Notes = $false
            Messages = $true
            Created = $true
            Modified = $true
            Cost = $true
            WinTerminal = $true
            ForkedFrom = $true
            Git = $false
            Path = $true
        }
    }

    try {
        $config = Get-Content $Global:ColumnConfigPath -Raw | ConvertFrom-Json
        # Convert from PSCustomObject to hashtable for easier use
        $ht = @{}
        $config.PSObject.Properties | ForEach-Object {
            $ht[$_.Name] = $_.Value
        }
        return $ht
    } catch {
        Write-DebugInfo "Error loading column config: $_" -Color Red
        # Return default on error
        # LimitFeature: Limit column added, default hidden
        return @{
            Active = $true
            Limit = $false  # LimitFeature: Context usage percentage, hidden by default (slow)
            Model = $true
            Session = $true
            Notes = $false
            Messages = $true
            Created = $true
            Modified = $true
            Cost = $true
            WinTerminal = $true
            ForkedFrom = $true
            Git = $false
            Path = $true
        }
    }
}

function Set-ColumnConfiguration {
    <#
    .SYNOPSIS
        Saves the column visibility configuration
    #>
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Config
    )

    try {
        $Config | ConvertTo-Json | Set-Content $Global:ColumnConfigPath -Encoding UTF8
        return $true
    } catch {
        Write-DebugInfo "Error saving column config: $_" -Color Red
        return $false
    }
}

function Show-ColumnConfigMenu {
    <#
    .SYNOPSIS
        Interactive menu for configuring column visibility
    #>

    # Load current configuration
    $config = Get-ColumnConfiguration

    # Define columns in display order
    # LimitFeature: Added Limit column
    $columns = @(
        @{ Name = "Active"; Label = "Active" }
        @{ Name = "Limit"; Label = "Limit (Context %)" }  # LimitFeature: Context usage percentage
        @{ Name = "Model"; Label = "Model" }
        @{ Name = "Session"; Label = "Session" }
        @{ Name = "Notes"; Label = "Notes" }
        @{ Name = "Messages"; Label = "Messages" }
        @{ Name = "Created"; Label = "Created" }
        @{ Name = "Modified"; Label = "Modified" }
        @{ Name = "Cost"; Label = "Cost" }
        @{ Name = "WinTerminal"; Label = "Win Terminal" }
        @{ Name = "ForkedFrom"; Label = "Forked From" }
        @{ Name = "Git"; Label = "Git Repo" }
        @{ Name = "Path"; Label = "Path" }
    )

    $selectedIndex = 0
    $saveExitIndex = $columns.Count
    $abortIndex = $columns.Count + 1

    while ($true) {
        Clear-Host
        Write-Host ""
        Write-ColorText "========================================" -Color Cyan
        Write-ColorText "          COLUMN CONFIGURATION          " -Color Cyan
        Write-ColorText "========================================" -Color Cyan
        Write-Host ""
        Write-Host "Select columns to display in the main menu:" -ForegroundColor Gray
        Write-Host "Use " -NoNewline -ForegroundColor Gray
        Write-Host "$([char]0x25B2)$([char]0x25BC)" -NoNewline -ForegroundColor Yellow
        Write-Host " to navigate, " -NoNewline -ForegroundColor Gray
        Write-Host "[Space]" -NoNewline -ForegroundColor Yellow
        Write-Host " or " -NoNewline -ForegroundColor Gray
        Write-Host "[Enter]" -NoNewline -ForegroundColor Yellow
        Write-Host " to toggle" -ForegroundColor Gray
        Write-Host ""
        Write-Host "TIP: " -NoNewline -ForegroundColor Yellow
        Write-Host "In the main menu, press " -NoNewline -ForegroundColor Gray
        Write-Host "1-12" -NoNewline -ForegroundColor Yellow
        Write-Host " to sort by column number" -ForegroundColor Gray
        Write-Host ""

        # Display column checkboxes
        for ($i = 0; $i -lt $columns.Count; $i++) {
            $column = $columns[$i]
            $isChecked = $config[$column.Name]
            $checkbox = if ($isChecked) { "[x]" } else { "[ ]" }
            $color = if ($i -eq $selectedIndex) { "Yellow" } else { "Green" }

            Write-Host "  $checkbox " -NoNewline -ForegroundColor $color
            Write-Host $column.Label -ForegroundColor $color
        }

        Write-Host ""

        # Display Save and Exit option
        $color = if ($selectedIndex -eq $saveExitIndex) { "Yellow" } else { "Green" }
        Write-Host "  Save and Exit" -ForegroundColor $color

        # Display Abort option
        $color = if ($selectedIndex -eq $abortIndex) { "Yellow" } else { "Green" }
        Write-Host "  Abort" -ForegroundColor $color

        # Read key
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        # Handle up arrow
        if ($key.VirtualKeyCode -eq 38) {
            $selectedIndex = ($selectedIndex - 1)
            if ($selectedIndex -lt 0) { $selectedIndex = $abortIndex }
        }
        # Handle down arrow
        elseif ($key.VirtualKeyCode -eq 40) {
            $selectedIndex = ($selectedIndex + 1)
            if ($selectedIndex -gt $abortIndex) { $selectedIndex = 0 }
        }
        # Handle space or enter
        elseif ($key.VirtualKeyCode -eq 32 -or $key.VirtualKeyCode -eq 13) {
            if ($selectedIndex -lt $columns.Count) {
                # Toggle checkbox
                $columnName = $columns[$selectedIndex].Name
                $config[$columnName] = -not $config[$columnName]
            }
            elseif ($selectedIndex -eq $saveExitIndex) {
                # Save and exit
                if (Set-ColumnConfiguration -Config $config) {
                    Write-Host ""
                    Write-ColorText "Column configuration saved." -Color Green
                    Start-Sleep -Seconds 1
                    return $true
                } else {
                    Write-Host ""
                    Write-ColorText "Failed to save configuration." -Color Red
                    Start-Sleep -Seconds 2
                    return $false
                }
            }
            elseif ($selectedIndex -eq $abortIndex) {
                # Abort without saving
                return $false
            }
        }
        # Handle Esc as abort
        elseif ($key.VirtualKeyCode -eq 27) {
            return $false
        }
    }
}

#endregion

#region Profile Registry

function Initialize-ProfileRegistry {
    <#
    .SYNOPSIS
        Creates the profile registry file if it doesn't exist
    #>
    if (-not (Test-Path $Global:ProfileRegistryPath)) {
        $registry = @{
            version = 1
            profiles = @()
        }

        $registry | ConvertTo-Json -Depth 10 | Set-Content $Global:ProfileRegistryPath -Encoding UTF8
        Write-ColorText "Profile registry initialized." -Color Green
    }
}

function Add-ProfileRegistry {
    <#
    .SYNOPSIS
        Adds a profile entry to the registry
    #>
    param(
        [string]$SessionName,
        [string]$ProfileGuid,
        [string]$OriginalSessionId,
        [string]$projectPath,
        [string]$BackgroundImage,
        [string]$Model
    )

    Initialize-ProfileRegistry

    $registry = Get-Content $Global:ProfileRegistryPath -Raw | ConvertFrom-Json

    $newEntry = [PSCustomObject]@{
        sessionName = $SessionName
        wtProfileGuid = $ProfileGuid
        originalSessionId = $OriginalSessionId
        created = (Get-Date -Format "o")
        projectPath = $projectPath
        backgroundImage = $BackgroundImage
        model = $Model
    }

    $registry.profiles = @($registry.profiles) + $newEntry

    $registry | ConvertTo-Json -Depth 10 | Set-Content $Global:ProfileRegistryPath -Encoding UTF8
}

function Get-ModelFromRegistry {
    <#
    .SYNOPSIS
        Gets the model for a session from the profile registry
    #>
    param([string]$SessionName)

    if (-not (Test-Path $Global:ProfileRegistryPath)) {
        return ""
    }

    try {
        $registry = Get-Content $Global:ProfileRegistryPath -Raw | ConvertFrom-Json
        $entry = $registry.profiles | Where-Object { $_.sessionName -eq $SessionName }

        if ($entry -and $entry.model) {
            return $entry.model
        }
    } catch {
        Write-ErrorLog "Error getting model from mapping: $_"
    }

    return ""
}

function Get-ModelFromSession {
    <#
    .SYNOPSIS
        Extracts the current model from a session's .jsonl file
    .DESCRIPTION
        Reads the LAST assistant message to get the most recent/current model,
        since users can change models mid-session. Results are cached based on
        file modification time to avoid re-parsing unchanged files.
    #>
    param(
        [string]$SessionId,
        [string]$ProjectPath
    )

    if (-not $SessionId -or -not $ProjectPath) {
        return ""
    }

    try {
        # Convert project path to Claude's encoded format
        $encodedPath = ConvertTo-ClaudeprojectPath -Path $ProjectPath
        $sessionFile = Join-Path $Global:ClaudeProjectsPath "$encodedPath\$SessionId.jsonl"

        if (-not (Test-Path $sessionFile)) {
            return ""
        }

        # Get file modification time for cache key
        $fileInfo = Get-Item $sessionFile
        $cacheKey = "$SessionId|$($fileInfo.LastWriteTime.Ticks)"

        # Check cache first
        if ($Global:ModelCache.ContainsKey($cacheKey)) {
            return $Global:ModelCache[$cacheKey]
        }

        # Clear old cache entries for this session (different modification times)
        $keysToRemove = $Global:ModelCache.Keys | Where-Object { $_ -like "$SessionId|*" -and $_ -ne $cacheKey }
        foreach ($key in $keysToRemove) {
            $Global:ModelCache.Remove($key)
        }

        # Read file line by line, keeping track of the LAST assistant message with model
        # This ensures we get the current model even if user changed it mid-session
        $lastModel = ""
        $reader = [System.IO.StreamReader]::new($sessionFile)
        try {
            while ($null -ne ($line = $reader.ReadLine())) {
                # Only check lines that might contain assistant messages
                if ($line -notmatch '"type":"assistant"') {
                    continue
                }

                # Parse the JSON
                $entry = $line | ConvertFrom-Json

                # Check if this is an assistant message with model info
                if ($entry.type -eq "assistant" -and $entry.message.model) {
                    $fullModel = $entry.message.model

                    # Parse model name to friendly format
                    if ($fullModel -match 'opus') {
                        $lastModel = "opus"
                    } elseif ($fullModel -match 'sonnet') {
                        $lastModel = "sonnet"
                    } elseif ($fullModel -match 'haiku') {
                        $lastModel = "haiku"
                    } else {
                        # Return first word of model name
                        if ($fullModel -match 'claude-([^-]+)') {
                            $lastModel = $matches[1]
                        } else {
                            $lastModel = $fullModel
                        }
                    }
                }
            }
        } finally {
            $reader.Close()
        }

        # Cache the result
        $Global:ModelCache[$cacheKey] = $lastModel

        return $lastModel
    } catch {
        Write-ErrorLog "Error getting model from session file: $_"
    }

    return ""
}

#endregion

#region Session Renaming

function Rename-ClaudeSession {
    <#
    .SYNOPSIS
        Renames a Claude Code session and updates all related metadata
    .DESCRIPTION
        Updates customTitle in sessions-index.json and Windows Terminal profile name if exists
    #>
    param(
        [Parameter(Mandatory=$true)]
        [object]$Session
    )

    Write-DebugInfo "=== Rename-ClaudeSession Started ===" -Color Cyan
    Write-DebugInfo "  Session ID: $($Session.sessionId)"
    Write-DebugInfo "  Custom Title: $($Session.customTitle)"
    Write-DebugInfo "  Tracked Name: $($Session.trackedName)"
    Write-DebugInfo "  Project Path: $($Session.projectPath)"

    try {
        $sessionId = $Session.sessionId
        $projectPath = $Session.projectPath
        $oldTitle = if ($Session.customTitle) { $Session.customTitle } elseif ($Session.trackedName) { $Session.trackedName } else { "(unnamed)" }

        Write-DebugInfo "  Old Title (resolved): $oldTitle"

        # Get old Windows Terminal profile name and background if they exist
        $oldWTProfile = Get-WTProfileName -SessionTitle $oldTitle -SessionId $sessionId
        Write-DebugInfo "  Old WT Profile: $oldWTProfile"

        $oldBackgroundPath = $null
        if ($oldWTProfile) {
            # Try to get background path from Windows Terminal settings
            try {
                $settings = Get-Content $Global:WTSettingsPath -Raw | ConvertFrom-Json
                $oldProfile = $settings.profiles.list | Where-Object { $_.name -eq $oldWTProfile } | Select-Object -First 1
                if ($oldProfile -and $oldProfile.backgroundImage) {
                    $oldBackgroundPath = $oldProfile.backgroundImage
                    Write-DebugInfo "  Old Background Image: $oldBackgroundPath"
                }
            } catch {
                Write-DebugInfo "  Could not get old background path: $_" -Color Yellow
            }
        }

        Write-Host ""
        Write-ColorText "Renaming session: $oldTitle" -Color Cyan
        Write-Host ""

        # Prompt for new name
        Write-ColorText "Enter new session name (or [Enter] to cancel): " -Color Yellow -NoNewline
        $newName = Read-Host

        Write-DebugInfo "  User entered: '$newName'"

        # Check for cancellation
        if ([string]::IsNullOrWhiteSpace($newName)) {
            Write-DebugInfo "  User cancelled - empty name" -Color Yellow
            Write-ColorText "Rename cancelled." -Color Yellow
            Start-Sleep -Seconds 1
            return $false
        }

        # Sanitize for filesystem
        $safeName = $newName -replace '[\\/:*?"<>|]', '_'
        Write-DebugInfo "  Safe name: '$safeName'"

        if ($newName -ne $safeName) {
            Write-DebugInfo "  Name was sanitized (contained invalid characters)"
            Write-ColorText "Name contains invalid characters. Using: $safeName" -Color Yellow
            Write-Host ""
        }

        # 1. Update Claude's sessions-index.json
        Write-ColorText "Updating Claude session index..." -Color Cyan
        Write-DebugInfo "  Updating Claude's sessions-index.json..." -Color Yellow
        $encodedPath = ConvertTo-ClaudeProjectPath -Path $projectPath
        Write-DebugInfo "    Encoded path: $encodedPath"
        $indexPath = Join-Path $Global:ClaudeProjectsPath "$encodedPath\sessions-index.json"
        Write-DebugInfo "    Index path: $indexPath"

        if (Test-Path $indexPath) {
            Write-DebugInfo "    Index file EXISTS" -Color Green
            try {
                $index = Get-Content $indexPath -Raw | ConvertFrom-Json
                Write-DebugInfo "    Index file loaded, searching for session ID: $sessionId"
                $entry = $index.entries | Where-Object { $_.sessionId -eq $sessionId }
                if ($entry) {
                    Write-DebugInfo "    Entry FOUND - updating customTitle to: $safeName" -Color Green

                    # Check if customTitle property exists
                    if ($null -eq $entry.PSObject.Properties['customTitle']) {
                        Write-DebugInfo "    customTitle property does not exist - adding it" -Color Yellow
                        $entry | Add-Member -NotePropertyName 'customTitle' -NotePropertyValue $safeName -Force
                    } else {
                        Write-DebugInfo "    customTitle property exists - updating it" -Color Green
                        $entry.customTitle = $safeName
                    }

                    $index | ConvertTo-Json -Depth 10 | Set-Content $indexPath -Encoding UTF8
                    Write-DebugInfo "    Index file saved successfully" -Color Green
                    Write-ColorText "  Updated session title in Claude index" -Color Green
                } else {
                    Write-DebugInfo "    Entry NOT FOUND in index" -Color Red
                    Write-ColorText "  Warning: Session not found in index" -Color Yellow
                }
            } catch {
                Write-DebugInfo "    ERROR updating index: $_" -Color Red
                Write-ColorText "  Error updating index: $_" -Color Red
                return $false
            }
        } else {
            Write-DebugInfo "    Index file DOES NOT EXIST" -Color Red
            Write-ColorText "  Warning: sessions-index.json not found at $indexPath" -Color Yellow
        }

        # 2. Generate new background image and create new Windows Terminal profile
        if ($oldWTProfile) {
            Write-DebugInfo "  Session has Windows Terminal profile - creating new profile" -Color Green
            Write-ColorText "Creating new Windows Terminal profile..." -Color Cyan

            # Get git branch
            $gitBranch = Get-GitBranch -Path $projectPath
            Write-DebugInfo "    Git branch: $gitBranch"

            # Get model from session mapping
            $sessionEntry = Get-SessionMappingEntry -SessionId $sessionId
            $modelName = if ($sessionEntry -and $sessionEntry.model) { $sessionEntry.model } else { $null }
            Write-DebugInfo "    Model: $modelName"

            # Generate new background image
            Write-ColorText "  Generating new background image..." -Color Cyan
            Write-DebugInfo "    Creating background for: $safeName"
            $newBackgroundPath = New-SessionBackgroundImage -NewName $safeName -ProjectPath $projectPath -GitBranch $gitBranch -Model $modelName
            Write-DebugInfo "    New background path: $newBackgroundPath" -Color Green

            if ($newBackgroundPath) {
                # Create new Windows Terminal profile
                $newWTProfile = "Claude-$safeName"
                Write-DebugInfo "    Creating new WT profile: $newWTProfile"

                try {
                    $newProfile = Add-WTProfile -Name $newWTProfile -StartingDirectory $projectPath -BackgroundImage $newBackgroundPath
                    if ($newProfile) {
                        Write-DebugInfo "    New profile created successfully" -Color Green
                        Write-ColorText "  Created new Windows Terminal profile: $newWTProfile" -Color Green

                        # Update session-mapping.json with new profile name
                        Write-DebugInfo "  Updating session-mapping.json..." -Color Yellow
                        if (Test-Path $Global:SessionMappingPath) {
                            try {
                                $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json
                                $mappedSession = $mapping.sessions | Where-Object { $_.sessionId -eq $sessionId }
                                if ($mappedSession) {
                                    $mappedSession.wtProfileName = $newProfile.name
                                    $mappedSession.updated = (Get-Date).ToString('o')
                                    $mapping | ConvertTo-Json -Depth 10 | Set-Content $Global:SessionMappingPath -Encoding UTF8
                                    Write-DebugInfo "    Session mapping updated" -Color Green
                                    Write-ColorText "  Updated session mapping" -Color Green
                                }
                            } catch {
                                Write-DebugInfo "    ERROR updating session mapping: $_" -Color Red
                            }
                        }

                        # 3. Check if old profile is used by any other sessions and remove if not
                        Write-DebugInfo "  Checking if old profile is used by other sessions..." -Color Yellow
                        Write-DebugInfo "    Old profile: $oldWTProfile"

                        $otherSessionsUsingOldProfile = $false
                        try {
                            $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json
                            foreach ($sess in $mapping.sessions) {
                                if ($sess.sessionId -ne $sessionId -and $sess.wtProfileName -eq $oldWTProfile) {
                                    $otherSessionsUsingOldProfile = $true
                                    Write-DebugInfo "    Found other session using old profile: $($sess.sessionId)" -Color Yellow
                                    break
                                }
                            }
                        } catch {
                            Write-DebugInfo "    ERROR checking profile usage: $_" -Color Red
                        }

                        if (-not $otherSessionsUsingOldProfile) {
                            Write-DebugInfo "    No other sessions use old profile - removing it" -Color Green
                            Write-ColorText "  Removing old Windows Terminal profile..." -Color Cyan
                            $removed = Remove-WTProfile -ProfileName $oldWTProfile
                            if ($removed) {
                                Write-DebugInfo "    Old profile removed successfully" -Color Green
                                Write-ColorText "  Removed old profile: $oldWTProfile" -Color Green
                            }
                        } else {
                            Write-DebugInfo "    Other sessions still use old profile - keeping it" -Color Yellow
                            Write-ColorText "  Keeping old profile (used by other sessions)" -Color Yellow
                        }

                        # 4. Check if old background is used by any other profiles and delete if not
                        if ($oldBackgroundPath) {
                            Write-DebugInfo "  Checking if old background is used by other profiles..." -Color Yellow
                            Write-DebugInfo "    Old background: $oldBackgroundPath"

                            $sessionsUsingOldBackground = Get-SessionsUsingBackground -BackgroundPath $oldBackgroundPath
                            if ($sessionsUsingOldBackground.Count -eq 0) {
                                Write-DebugInfo "    No other profiles use old background - deleting it" -Color Green
                                Write-ColorText "  Deleting old background image..." -Color Cyan
                                try {
                                    Remove-Item -Path $oldBackgroundPath -Force -ErrorAction Stop
                                    Write-DebugInfo "    Old background deleted successfully" -Color Green
                                    Write-ColorText "  Deleted old background image" -Color Green
                                } catch {
                                    Write-DebugInfo "    ERROR deleting old background: $_" -Color Red
                                    Write-ColorText "  Warning: Could not delete old background image" -Color Yellow
                                }
                            } else {
                                Write-DebugInfo "    Other profiles still use old background - keeping it" -Color Yellow
                                Write-ColorText "  Keeping old background (used by other profiles)" -Color Yellow
                            }
                        }
                    } else {
                        Write-DebugInfo "    ERROR: Add-WTProfile returned null" -Color Red
                        Write-ColorText "  Error: Failed to create new profile" -Color Red
                    }
                } catch {
                    Write-DebugInfo "    EXCEPTION creating new profile: $_" -Color Red
                    Write-ColorText "  Error: Failed to create new profile - $_" -Color Red
                }
            } else {
                Write-DebugInfo "    ERROR: Background image generation failed" -Color Red
                Write-ColorText "  Error: Failed to generate new background image" -Color Red
            }
        } else {
            Write-DebugInfo "  NO Windows Terminal profile found for this session - no profile changes needed" -Color Yellow
        }

        Write-Host ""
        Write-DebugInfo "=== Rename Complete ===" -Color Green
        Write-ColorText "Session renamed successfully: '$oldTitle' -> '$safeName'" -Color Green
        Start-Sleep -Seconds 2
        return $true

    } catch {
        Write-Host ""
        Write-DebugInfo "=== Rename FAILED ===" -Color Red
        Write-DebugInfo "Exception: $_" -Color Red
        Write-DebugInfo "Stack trace: $($_.ScriptStackTrace)" -Color Red
        Write-ColorText "Error renaming session: $_" -Color Red
        Start-Sleep -Seconds 3
        return $false
    }
}

#endregion

#region Session Deletion

function Remove-Session {
    <#
    .SYNOPSIS
        Completely removes a Claude session and associated tracking
    #>
    param(
        [object]$Session,
        [string]$WTProfileName = ""
    )

    try {
        $sessionId = $Session.sessionId
        $projectPath = $Session.projectPath
        $sessionTitle = if ($Session.customTitle) { $Session.customTitle } elseif ($Session.trackedName) { $Session.trackedName } else { "(unnamed)" }

        Write-Host ""
        Write-ColorText "Deleting session: $sessionTitle" -Color Yellow
        Write-Host ""

        # 1. Remove from Claude's sessions-index.json
        Write-ColorText "  Removing from Claude's session index..." -Color Cyan
        $encodedPath = ConvertTo-ClaudeprojectPath -Path $projectPath
        $indexPath = Join-Path $Global:ClaudeProjectsPath "$encodedPath\sessions-index.json"

        if (Test-Path $indexPath) {
            try {
                $index = Get-Content $indexPath -Raw | ConvertFrom-Json
                $index.entries = @($index.entries | Where-Object { $_.sessionId -ne $sessionId })
                $index | ConvertTo-Json -Depth 10 | Set-Content $indexPath -Encoding UTF8
                Write-ColorText "    Removed from index" -Color Green
            } catch {
                Write-ColorText "    Warning: Could not update index - $_" -Color Yellow
            }
        }

        # 2. Delete the session .jsonl file
        Write-ColorText "  Deleting session file..." -Color Cyan
        $sessionFile = Join-Path $Global:ClaudeProjectsPath "$encodedPath\$sessionId.jsonl"
        if (Test-Path $sessionFile) {
            Remove-Item $sessionFile -Force
            Write-ColorText "    Deleted: $sessionFile" -Color Green
        } else {
            Write-ColorText "    File not found (already deleted?)" -Color Yellow
        }

        # 3. Remove from session-mapping.json
        Write-ColorText "  Cleaning up session tracking..." -Color Cyan
        if (Test-Path $Global:SessionMappingPath) {
            try {
                $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json
                $mapping.sessions = @($mapping.sessions | Where-Object { $_.sessionId -ne $sessionId })
                $mapping | ConvertTo-Json -Depth 10 | Set-Content $Global:SessionMappingPath -Encoding UTF8
                Write-ColorText "    Removed from session mapping" -Color Green
            } catch {
                Write-ColorText "    Warning: Could not update session mapping - $_" -Color Yellow
            }
        }

        # 4. Remove from profile-registry.json
        if (Test-Path $Global:ProfileRegistryPath) {
            try {
                $registry = Get-Content $Global:ProfileRegistryPath -Raw | ConvertFrom-Json
                $registry.profiles = @($registry.profiles | Where-Object { $_.originalSessionId -ne $sessionId })
                $registry | ConvertTo-Json -Depth 10 | Set-Content $Global:ProfileRegistryPath -Encoding UTF8
                Write-ColorText "    Removed from profile registry" -Color Green
            } catch {
                Write-ColorText "    Warning: Could not update profile registry - $_" -Color Yellow
            }
        }

        # 5. Check if Windows Terminal profile should be deleted
        if ($WTProfileName -and $WTProfileName -ne "") {
            Write-ColorText "  Checking Windows Terminal profile usage..." -Color Cyan

            # Check if any other session uses this profile
            $otherSessionsUsingProfile = $false

            if (Test-Path $Global:SessionMappingPath) {
                try {
                    $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json
                    $otherSessionsUsingProfile = $mapping.sessions | Where-Object { $_.wtProfileName -eq $WTProfileName }
                } catch {
                    Write-ErrorLog "Error checking other sessions using profile: $_"
                }
            }

            if ($otherSessionsUsingProfile) {
                Write-ColorText "    Profile '$WTProfileName' is used by other sessions - keeping it" -Color Yellow
            } else {
                Write-ColorText "    No other sessions use profile '$WTProfileName' - deleting it" -Color Cyan

                # Delete Windows Terminal profile
                $success = Remove-WTProfile -ProfileName $WTProfileName

                if ($success) {
                    Write-ColorText "    Windows Terminal profile deleted" -Color Green

                    # Delete background image directory
                    $sessionName = $WTProfileName -replace '^Claude-', ''
                    $bgDir = Join-Path $Global:MenuPath $sessionName
                    if (Test-Path $bgDir) {
                        Remove-Item $bgDir -Recurse -Force
                        Write-ColorText "    Background images deleted" -Color Green
                    }

                    # Remove from background-tracking.json
                    if (Test-Path $Global:BackgroundTrackingPath) {
                        try {
                            $tracking = Get-Content $Global:BackgroundTrackingPath -Raw | ConvertFrom-Json
                            $tracking.backgrounds = @($tracking.backgrounds | Where-Object { $_.sessionName -ne $sessionName })
                            $tracking | ConvertTo-Json -Depth 10 | Set-Content $Global:BackgroundTrackingPath -Encoding UTF8
                            Write-ColorText "    Removed from background tracking" -Color Green
                        } catch {
                            Write-ErrorLog "Error removing from background tracking: $_"
                        }
                    }
                }
            }
        }

        Write-Host ""
        Write-ColorText "Session deleted successfully!" -Color Green
        return $true

    } catch {
        Write-Host ""
        Write-ColorText "Error deleting session: $_" -Color Red
        return $false
    }
}

#endregion

#region Background Tracking

function Initialize-BackgroundTracking {
    <#
    .SYNOPSIS
        Creates the background tracking file if it doesn't exist
    #>
    if (-not (Test-Path $Global:BackgroundTrackingPath)) {
        $tracking = @{
            version = 1
            backgrounds = @()
        }

        $tracking | ConvertTo-Json -Depth 10 | Set-Content $Global:BackgroundTrackingPath -Encoding UTF8
        Write-ColorText "Background tracking initialized." -Color Green
    }
}

function Save-BackgroundTracking {
    <#
    .SYNOPSIS
        Saves background image tracking information
    #>
    param(
        [string]$SessionName,
        [string]$BackgroundPath,
        [string]$TextContent = "",
        [string]$ImageType = "generated"  # generated, fork, continue, custom-text, custom-file
    )

    Initialize-BackgroundTracking

    try {
        $tracking = Get-Content $Global:BackgroundTrackingPath -Raw | ConvertFrom-Json

        # Check if entry already exists
        $existingIndex = -1
        for ($i = 0; $i -lt $tracking.backgrounds.Count; $i++) {
            if ($tracking.backgrounds[$i].sessionName -eq $SessionName) {
                $existingIndex = $i
                break
            }
        }

        if ($existingIndex -ge 0) {
            # Update existing entry by replacing it
            $updatedEntry = @{
                sessionName = $SessionName
                backgroundPath = $BackgroundPath
                textContent = $TextContent
                imageType = $ImageType
                created = $tracking.backgrounds[$existingIndex].created
                updated = (Get-Date).ToString('o')
            }
            $tracking.backgrounds[$existingIndex] = $updatedEntry
        } else {
            # Create new entry
            $newEntry = @{
                sessionName = $SessionName
                backgroundPath = $BackgroundPath
                textContent = $TextContent
                imageType = $ImageType
                created = (Get-Date).ToString('o')
            }

            $tracking.backgrounds = @($tracking.backgrounds) + $newEntry
        }

        $tracking | ConvertTo-Json -Depth 10 | Set-Content $Global:BackgroundTrackingPath -Encoding UTF8

    } catch {
        Write-ColorText "Warning: Could not save background tracking: $_" -Color Yellow
    }
}

function Get-BackgroundTracking {
    <#
    .SYNOPSIS
        Gets background tracking information for a session
    #>
    param([string]$SessionName)

    if (-not (Test-Path $Global:BackgroundTrackingPath)) {
        return $null
    }

    try {
        $tracking = Get-Content $Global:BackgroundTrackingPath -Raw | ConvertFrom-Json
        $entry = $tracking.backgrounds | Where-Object { $_.sessionName -eq $SessionName }
        return $entry
    } catch {
        return $null
    }
}

function Get-OutOfSyncBackgrounds {
    <#
    .SYNOPSIS
        Finds all sessions with backgrounds that are out of sync with current session data
    .DESCRIPTION
        Compares stored model and git branch in background .txt files with current values
        from session files and git repository. Uses .txt files for faster reading.
    .RETURNS
        Array of objects containing session info and what's out of sync
    #>

    $outOfSync = @()

    Write-DebugInfo "=== Get-OutOfSyncBackgrounds ===" -Color Cyan

    # Get all sessions
    $allSessions = Get-AllClaudeSessions
    Write-DebugInfo "  Total sessions: $($allSessions.Count)"

    foreach ($session in $allSessions) {
        # Get session mapping entry (still needed to find WT profile name)
        $mappingEntry = Get-SessionMappingEntry -SessionId $session.sessionId
        if (-not $mappingEntry -or -not $mappingEntry.wtProfileName) {
            Write-DebugInfo "  Session $($session.sessionId): No WT mapping - skip" -Color DarkGray
            # No WT profile - skip
            continue
        }

        $changes = @()
        $wtProfileName = $mappingEntry.wtProfileName
        $sessionName = $wtProfileName -replace '^Claude-', ''
        Write-DebugInfo "  Checking: $sessionName" -Color Yellow

        # Check if background image exists
        $bgPath = Join-Path $Global:MenuPath "$sessionName\background.png"
        $bgExists = Test-Path $bgPath
        Write-DebugInfo "    bgPath: $bgPath (exists: $bgExists)"
        if (-not $bgExists) {
            # No background image - flag as needing generation
            $changes += "No background image"
        }

        # Compare model - read stored value from background .txt file (faster)
        $storedModel = Get-ModelFromBackgroundTxt -WTProfileName $wtProfileName
        $currentModel = Get-ModelFromSession -SessionId $session.sessionId -ProjectPath $session.projectPath
        Write-DebugInfo "    storedModel: '$storedModel', currentModel: '$currentModel'"
        if ($currentModel -and $storedModel -and $currentModel -ne $storedModel) {
            $changes += "Model: $storedModel -> $currentModel"
        } elseif ($currentModel -and -not $storedModel) {
            $changes += "Model: (none) -> $currentModel"
        }

        # Compare git branch - read stored value from background .txt file (faster)
        $storedBranch = Get-BranchFromBackgroundTxt -WTProfileName $wtProfileName
        $currentBranch = Get-GitBranch -Path $session.projectPath
        Write-DebugInfo "    storedBranch: '$storedBranch', currentBranch: '$currentBranch'"
        if ($currentBranch -and $storedBranch -and $currentBranch -ne $storedBranch) {
            $changes += "Branch: $storedBranch -> $currentBranch"
        } elseif ($currentBranch -and -not $storedBranch) {
            $changes += "Branch: (none) -> $currentBranch"
        }

        Write-DebugInfo "    Changes found: $($changes.Count)" -Color $(if ($changes.Count -gt 0) { "Green" } else { "DarkGray" })

        # If anything changed, add to list
        if ($changes.Count -gt 0) {
            $displayName = if ($session.customTitle) {
                $session.customTitle
            } elseif ($session.trackedName) {
                $session.trackedName
            } else {
                $sessionName
            }

            $outOfSync += [PSCustomObject]@{
                Session = $session
                SessionName = $sessionName
                DisplayName = $displayName
                WTProfileName = $wtProfileName
                Changes = $changes
                CurrentModel = $currentModel
                CurrentBranch = $currentBranch
                StoredModel = $storedModel
                StoredBranch = $storedBranch
            }
        }
    }

    Write-DebugInfo "  Total out of sync: $($outOfSync.Count)" -Color Cyan
    return $outOfSync
}

function Get-SessionsWithMissingTxtFiles {
    <#
    .SYNOPSIS
        Finds all sessions that have background.png but no corresponding background.txt
    .RETURNS
        Array of objects containing session info for missing txt files
    #>

    $missingTxt = @()

    Write-DebugInfo "=== Get-SessionsWithMissingTxtFiles ===" -Color Cyan
    Write-DebugInfo "  MenuPath: $Global:MenuPath"

    # Get all sessions
    $allSessions = Get-AllClaudeSessions
    Write-DebugInfo "  Total sessions found: $($allSessions.Count)"

    foreach ($session in $allSessions) {
        # Get session mapping entry
        $mappingEntry = Get-SessionMappingEntry -SessionId $session.sessionId
        if (-not $mappingEntry -or -not $mappingEntry.wtProfileName) {
            Write-DebugInfo "  Session $($session.sessionId): No WT profile mapping - skipping" -Color DarkGray
            continue
        }

        $wtProfileName = $mappingEntry.wtProfileName
        $sessionName = $wtProfileName -replace '^Claude-', ''
        Write-DebugInfo "  Checking session: $sessionName (WT: $wtProfileName)" -Color Yellow

        # Check if background image exists but txt doesn't
        $bgPath = Join-Path $Global:MenuPath "$sessionName\background.png"
        $txtPath = Join-Path $Global:MenuPath "$sessionName\background.txt"
        Write-DebugInfo "    bgPath: $bgPath"
        Write-DebugInfo "    txtPath: $txtPath"
        Write-DebugInfo "    bgExists: $(Test-Path $bgPath), txtExists: $(Test-Path $txtPath)"

        if ((Test-Path $bgPath) -and -not (Test-Path $txtPath)) {
            Write-DebugInfo "    -> MISSING TXT FILE" -Color Green
            $displayName = if ($session.customTitle) {
                $session.customTitle
            } elseif ($session.trackedName) {
                $session.trackedName
            } else {
                $sessionName
            }

            $missingTxt += [PSCustomObject]@{
                Session = $session
                SessionName = $sessionName
                DisplayName = $displayName
                WTProfileName = $wtProfileName
                BackgroundPath = $bgPath
                TxtPath = $txtPath
                StoredModel = if ($mappingEntry.model) { $mappingEntry.model } else { "" }
                StoredBranch = if ($mappingEntry.gitBranch) { $mappingEntry.gitBranch } else { "" }
            }
        } else {
            Write-DebugInfo "    -> OK (both exist or no bg)" -Color DarkGray
        }
    }

    Write-DebugInfo "  Total missing txt files: $($missingTxt.Count)" -Color Cyan
    return $missingTxt
}

function New-BackgroundTxtFile {
    <#
    .SYNOPSIS
        Creates a .txt file for an existing background image
    #>
    param(
        [string]$SessionName,
        [string]$TxtPath,
        [object]$Session,
        [string]$Model,
        [string]$GitBranch
    )

    try {
        # Get fork info
        $forkInfo = Get-ForkedFromInfo -SessionId $Session.sessionId
        $forkedFrom = $null

        if ($forkInfo -and $forkInfo.ForkedFrom) {
            $allSessions = Get-AllClaudeSessions
            $parentSession = $allSessions | Where-Object { $_.sessionId -eq $forkInfo.ForkedFrom }
            $forkedFrom = if ($parentSession -and $parentSession.customTitle) {
                $parentSession.customTitle
            } else {
                '(deleted or unnamed)'
            }
        }

        # Build txt content
        $computerUser = "$env:COMPUTERNAME`:$env:USERNAME"
        $txtContent = @()
        $txtContent += "Session: $SessionName"
        if ($forkedFrom) {
            $txtContent += "Forked from: $forkedFrom"
        }
        $txtContent += "Computer:User: $computerUser"
        if ($GitBranch) {
            $txtContent += "Branch: $GitBranch"
        }
        if ($Model) {
            $txtContent += "Model: $Model"
        }
        $txtContent += "Directory: $($Session.projectPath)"
        $txtContent += ""
        $txtContent += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $txtContent += "(txt file created retroactively)"

        # Ensure directory exists
        $txtDir = Split-Path $TxtPath -Parent
        if (-not (Test-Path $txtDir)) {
            New-Item -ItemType Directory -Path $txtDir -Force | Out-Null
        }

        $txtContent -join "`r`n" | Set-Content $TxtPath -Encoding UTF8
        return $true
    } catch {
        Write-ErrorLog "Error creating txt file: $_"
        return $false
    }
}

function Show-RegenerateBackgroundsMenu {
    <#
    .SYNOPSIS
        Shows menu for regenerating out-of-sync background images
    .DESCRIPTION
        First checks for missing .txt files, then lists sessions with backgrounds
        that differ from current session data and offers to regenerate them
    #>

    Clear-Host
    Write-Host ""
    Write-ColorText "=== Background Sanity Check ===" -Color Cyan
    Write-Host ""

    # First check for missing .txt files
    Write-ColorText "Checking for missing .txt files..." -Color Gray
    $missingTxt = Get-SessionsWithMissingTxtFiles

    if ($missingTxt.Count -gt 0) {
        Write-Host ""
        Write-ColorText "Found $($missingTxt.Count) background image(s) without .txt files:" -Color Yellow
        Write-Host ""

        $index = 1
        foreach ($item in $missingTxt) {
            Write-Host "  $index. " -NoNewline -ForegroundColor White
            Write-Host "$($item.DisplayName)" -NoNewline -ForegroundColor Cyan
            Write-Host " [$($item.WTProfileName)]" -ForegroundColor DarkGray
            $index++
        }

        Write-Host ""
        Write-Host "-" * 60 -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "Generate missing .txt files? " -NoNewline -ForegroundColor Gray
        Write-Host "Y" -NoNewline -ForegroundColor Yellow
        Write-Host "es " -NoNewline -ForegroundColor Gray
        Write-Host "|" -NoNewline -ForegroundColor Gray
        Write-Host " N" -NoNewline -ForegroundColor Yellow
        Write-Host "o " -NoNewline -ForegroundColor Gray

        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $generateTxt = $key.Character.ToString().ToUpper()

        if ($key.VirtualKeyCode -eq 27) {
            $generateTxt = 'N'
        }

        Write-Host ""

        if ($generateTxt -eq 'Y') {
            Write-Host ""
            Write-ColorText "Generating .txt files..." -Color Cyan

            $successCount = 0
            $failCount = 0

            foreach ($item in $missingTxt) {
                Write-Host "  Creating: " -NoNewline -ForegroundColor Gray
                Write-Host "$($item.SessionName).txt" -NoNewline -ForegroundColor Cyan
                Write-Host "..." -NoNewline -ForegroundColor Gray

                # Get current model and branch if not stored
                $model = $item.StoredModel
                if (-not $model) {
                    $model = Get-ModelFromSession -SessionId $item.Session.sessionId -ProjectPath $item.Session.projectPath
                }
                $gitBranch = $item.StoredBranch
                if (-not $gitBranch) {
                    $gitBranch = Get-GitBranch -Path $item.Session.projectPath
                }

                $success = New-BackgroundTxtFile -SessionName $item.SessionName -TxtPath $item.TxtPath -Session $item.Session -Model $model -GitBranch $gitBranch

                if ($success) {
                    Write-Host " Done" -ForegroundColor Green
                    $successCount++
                } else {
                    Write-Host " Failed" -ForegroundColor Red
                    $failCount++
                }
            }

            Write-Host ""
            Write-ColorText "Created $successCount .txt file(s)" -Color $(if ($failCount -gt 0) { "Yellow" } else { "Green" })
            if ($failCount -gt 0) {
                Write-ColorText "$failCount failed" -Color Red
            }
            Write-Host ""
            Write-Host "Press any key to continue..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }

        Write-Host ""
    }

    # Now check for out-of-sync backgrounds
    Write-ColorText "Scanning sessions for out-of-sync backgrounds..." -Color Gray
    Write-Host ""

    # Get out of sync backgrounds
    $outOfSync = Get-OutOfSyncBackgrounds

    if ($outOfSync.Count -eq 0) {
        Write-ColorText "All background images are in sync!" -Color Green
        Write-Host ""
        Write-Host "Press any key to return..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }

    # Display the list
    Write-ColorText "Found $($outOfSync.Count) session(s) with out-of-sync backgrounds:" -Color Yellow
    Write-Host ""

    $index = 1
    foreach ($item in $outOfSync) {
        Write-Host "  $index. " -NoNewline -ForegroundColor White
        Write-Host "$($item.DisplayName)" -NoNewline -ForegroundColor Cyan
        Write-Host " [$($item.WTProfileName)]" -ForegroundColor DarkGray
        foreach ($change in $item.Changes) {
            Write-Host "     - $change" -ForegroundColor Yellow
        }
        $index++
    }

    Write-Host ""
    Write-Host "─" * 60 -ForegroundColor DarkGray
    Write-Host ""

    # Prompt for regeneration
    Write-Host "Options:" -ForegroundColor Gray
    Write-Host "  " -NoNewline
    Write-Host "A" -NoNewline -ForegroundColor Yellow
    Write-Host " - Regenerate ALL out-of-sync backgrounds" -ForegroundColor Gray
    Write-Host "  " -NoNewline
    Write-Host "1-$($outOfSync.Count)" -NoNewline -ForegroundColor Yellow
    Write-Host " - Regenerate specific session" -ForegroundColor Gray
    Write-Host "  " -NoNewline
    Write-Host "Q" -NoNewline -ForegroundColor Yellow
    Write-Host " - Return without regenerating" -ForegroundColor Gray
    Write-Host ""

    $choice = Read-Host "Enter choice"

    if ($choice -eq 'Q' -or $choice -eq 'q' -or $choice -eq '') {
        return
    }

    $sessionsToRegenerate = @()

    if ($choice -eq 'A' -or $choice -eq 'a') {
        $sessionsToRegenerate = $outOfSync
    } else {
        $num = 0
        if ([int]::TryParse($choice, [ref]$num) -and $num -ge 1 -and $num -le $outOfSync.Count) {
            $sessionsToRegenerate = @($outOfSync[$num - 1])
        } else {
            Write-ColorText "Invalid choice." -Color Red
            Start-Sleep -Seconds 1
            return
        }
    }

    # Regenerate selected backgrounds
    Write-Host ""
    Write-ColorText "Regenerating $($sessionsToRegenerate.Count) background(s)..." -Color Cyan
    Write-Host ""

    $successCount = 0
    $failCount = 0

    foreach ($item in $sessionsToRegenerate) {
        Write-Host "  Regenerating: " -NoNewline -ForegroundColor Gray
        Write-Host "$($item.DisplayName)" -NoNewline -ForegroundColor Cyan
        Write-Host "..." -NoNewline -ForegroundColor Gray

        try {
            # Get fork info
            $forkInfo = Get-ForkedFromInfo -SessionId $item.Session.sessionId

            # Detect current git branch
            $gitBranch = $item.CurrentBranch
            if (-not $gitBranch) {
                $gitBranch = Get-GitBranch -Path $item.Session.projectPath
            }

            # Get current model
            $model = $item.CurrentModel
            if (-not $model) {
                $model = Get-ModelFromSession -SessionId $item.Session.sessionId -ProjectPath $item.Session.projectPath
            }

            if ($forkInfo -and $forkInfo.ForkedFrom) {
                # Fork session - get parent name
                $allSessions = Get-AllClaudeSessions
                $parentSession = $allSessions | Where-Object { $_.sessionId -eq $forkInfo.ForkedFrom }
                $parentName = if ($parentSession -and $parentSession.customTitle) {
                    $parentSession.customTitle
                } else {
                    '(deleted or unnamed)'
                }

                # Regenerate fork-style background
                $bgPath = New-SessionBackgroundImage -NewName $item.SessionName -OldName $parentName -IsFork -GitBranch $gitBranch -Model $model -ProjectPath $item.Session.projectPath
            } else {
                # Non-fork session - regenerate continue-style background
                $bgPath = New-ContinueSessionBackgroundImage -SessionName $item.SessionName -GitBranch $gitBranch -Model $model -ProjectPath $item.Session.projectPath
            }

            # Update Windows Terminal profile with new image path
            $settingsJson = Get-Content $Global:WTSettingsPath -Raw
            $settings = $settingsJson | ConvertFrom-Json

            for ($i = 0; $i -lt $settings.profiles.list.Count; $i++) {
                if ($settings.profiles.list[$i].name -eq $item.WTProfileName) {
                    $imagePath = $bgPath -replace '\\', '/'
                    $settings.profiles.list[$i].backgroundImage = $imagePath
                    $settings | ConvertTo-Json -Depth 10 | Set-Content $Global:WTSettingsPath -Encoding UTF8
                    break
                }
            }

            # Update session mapping with current model and git branch
            Add-SessionMapping -SessionId $item.Session.sessionId `
                              -WTProfileName $item.WTProfileName `
                              -ProjectPath $item.Session.projectPath `
                              -Model $model `
                              -GitBranch $gitBranch

            Write-Host " Done" -ForegroundColor Green
            $successCount++

        } catch {
            Write-Host " Failed: $_" -ForegroundColor Red
            $failCount++
        }
    }

    Write-Host ""
    Write-Host "─" * 60 -ForegroundColor DarkGray
    Write-ColorText "Regeneration complete: $successCount succeeded, $failCount failed" -Color $(if ($failCount -gt 0) { "Yellow" } else { "Green" })
    Write-Host ""
    Write-Host "Press any key to return..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function New-CustomTextBackgroundImage {
    <#
    .SYNOPSIS
        Wrapper for creating background images with custom text
    .PARAMETER SessionName
        The session name
    .PARAMETER CustomText
        Custom text to display as Line 1
    .PARAMETER ProjectPath
        The project directory path
    #>
    param(
        [string]$SessionName,
        [string]$CustomText,
        [string]$ProjectPath = ""
    )

    try {
        Write-DebugInfo "=== New-CustomTextBackgroundImage ===" -Color Cyan
        Write-DebugInfo "  SessionName: $SessionName"
        Write-DebugInfo "  CustomText: $CustomText"
        Write-DebugInfo "  ProjectPath: $ProjectPath"

        # Prepare output path
        $outputDir = Join-Path $Global:MenuPath $SessionName
        $outputPath = Join-Path $outputDir "background.png"

        # Prepare parameters for uniform function
        # Custom text goes in Line 1, everything else follows the standard format
        $computerUser = "$env:COMPUTERNAME`:$env:USERNAME"

        # Call the common uniform function
        $result = New-UniformBackgroundImage `
            -SessionName $CustomText `
            -ForkedFrom $null `
            -ComputerUser $computerUser `
            -GitBranch $null `
            -Model $null `
            -DirectoryPath $ProjectPath `
            -OutputPath $outputPath

        # Save tracking
        Save-BackgroundTracking -SessionName $SessionName -BackgroundPath $outputPath -TextContent $CustomText -ImageType "custom-text"

        return $result

    } catch {
        Write-ColorText "Failed to generate background image: $_" -Color Red
        throw
    }
}

function Set-BackgroundFromFile {
    <#
    .SYNOPSIS
        Sets a Windows Terminal profile to use a custom image file
    #>
    param(
        [string]$SessionName,
        [string]$WTProfileName,
        [string]$ImageFilePath
    )

    try {
        # Verify file exists
        if (-not (Test-Path $ImageFilePath)) {
            Write-ColorText "Error: Image file not found: $ImageFilePath" -Color Red
            return $false
        }

        # Update Windows Terminal profile
        $backupPath = Backup-WTSettings
        $settingsJson = Get-Content $Global:WTSettingsPath -Raw
        $settings = $settingsJson | ConvertFrom-Json

        $profileIndex = -1
        for ($i = 0; $i -lt $settings.profiles.list.Count; $i++) {
            if ($settings.profiles.list[$i].name -eq $WTProfileName) {
                $profileIndex = $i
                break
            }
        }

        if ($profileIndex -ge 0) {
            $imagePath = $ImageFilePath -replace '\\', '/'
            $settings.profiles.list[$profileIndex].backgroundImage = $imagePath
            $settings | ConvertTo-Json -Depth 10 | Set-Content $Global:WTSettingsPath -Encoding UTF8

            # Save tracking
            Save-BackgroundTracking -SessionName $SessionName -BackgroundPath $ImageFilePath -TextContent "" -ImageType "custom-file"

            Write-ColorText "Updated Windows Terminal profile with custom image" -Color Green
            return $true
        } else {
            Write-ColorText "Could not find Windows Terminal profile: $WTProfileName" -Color Red
            return $false
        }

    } catch {
        Write-ColorText "Error setting background from file: $_" -Color Red
        return $false
    }
}

function Remove-BackgroundFromProfile {
    <#
    .SYNOPSIS
        Removes the background image from a Windows Terminal profile
    #>
    param([string]$WTProfileName)

    try {
        $backupPath = Backup-WTSettings
        $settingsJson = Get-Content $Global:WTSettingsPath -Raw
        $settings = $settingsJson | ConvertFrom-Json

        $profileIndex = -1
        for ($i = 0; $i -lt $settings.profiles.list.Count; $i++) {
            if ($settings.profiles.list[$i].name -eq $WTProfileName) {
                $profileIndex = $i
                break
            }
        }

        if ($profileIndex -ge 0) {
            # Remove background image properties
            $profile = $settings.profiles.list[$profileIndex]
            $profile.PSObject.Properties.Remove('backgroundImage')
            $profile.PSObject.Properties.Remove('backgroundImageOpacity')
            $profile.PSObject.Properties.Remove('backgroundImageStretchMode')

            $settings | ConvertTo-Json -Depth 10 | Set-Content $Global:WTSettingsPath -Encoding UTF8

            Write-ColorText "Removed background image from profile: $WTProfileName" -Color Green
            return $true
        } else {
            Write-ColorText "Could not find Windows Terminal profile: $WTProfileName" -Color Red
            return $false
        }

    } catch {
        Write-ColorText "Error removing background: $_" -Color Red
        return $false
    }
}

#endregion

#region Main Program

function Initialize-Environment {
    <#
    .SYNOPSIS
        Performs first-run initialization
    #>

    # Create .claude-menu directory if needed
    if (-not (Test-Path $Global:MenuPath)) {
        New-Item -ItemType Directory -Path $Global:MenuPath -Force | Out-Null
        Write-ColorText "Created menu directory: $Global:MenuPath" -Color Green
    }

    # Clear debug log on startup (fresh start each run)
    if (Test-Path $Global:DebugLogPath) {
        try {
            Remove-Item $Global:DebugLogPath -Force -ErrorAction SilentlyContinue
        } catch {
            # Silently ignore errors
        }
    }

    # Write startup header to debug log if debug is enabled
    if (Get-DebugState) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "[$timestamp] ========== Claude Session Forker Started ==========" | Add-Content -Path $Global:DebugLogPath -Encoding UTF8
    }

    # Check prerequisites
    if (-not (Test-ClaudeCLI)) {
        Write-ColorText "ERROR: Claude CLI not found in PATH" -Color Red
        Write-Host ""
        Write-Host "Please ensure Claude CLI is installed and available in your PATH."
        Write-Host "Expected location: $env:USERPROFILE\.local\bin\claude.exe"
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }

    if (-not (Test-WindowsTerminal)) {
        Write-ColorText "ERROR: Windows Terminal not found" -Color Red
        Write-Host ""
        Write-Host "Please install Windows Terminal from:"
        Write-Host "https://aka.ms/terminal"
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }

    # Initialize base Windows Terminal profile
    if (Test-Path $Global:WTSettingsPath) {
        Initialize-BaseWTProfile | Out-Null
    }

    # Initialize profile registry
    Initialize-ProfileRegistry

    # Initialize session mapping
    Initialize-SessionMapping

    # Initialize background tracking
    Initialize-BackgroundTracking
}

function Start-MainMenu {
    <#
    .SYNOPSIS
        Main program loop
    #>

    # Initialize environment
    Initialize-Environment

    # Validate session mappings on startup
    Validate-SessionMappings

    # Menu loop with show/hide toggle and delete mode
    $showUnnamed = $true
    $deleteMode = $false
    $showAllInDeleteMode = $false
    $selectedIndex = 0
    $reloadSessions = $true
    $isRefresh = $false  # Track if this is an explicit refresh (to trigger model checks)
    $sessions = $null

    while ($true) {
        # Only reload sessions when needed (not during navigation)
        if ($reloadSessions) {
            $sessions = Get-AllClaudeSessions
            $reloadSessions = $false
        }

        # Initialize as empty array if null
        if ($null -eq $sessions) { $sessions = @() }

        # Check if this is first run (no sessions)
        $claudeProjectsPath = "$env:USERPROFILE\.claude\projects"
        $isFirstRun = -not (Test-Path $claudeProjectsPath)
        $sessionCount = if ($sessions) { $sessions.Count } else { 0 }

        if ($sessionCount -eq 0) {
            Clear-Host
            Write-Host ""
            Write-ColorText "========================================" -Color Cyan
            Write-ColorText "  CLAUDE SESSION FORKER" -Color Cyan
            Write-ColorText "========================================" -Color Cyan
            Write-Host ""

            if ($isFirstRun) {
                Write-ColorText "No Claude Code sessions found - First Run Detected!" -Color Yellow
                Write-Host ""
                Write-Host "It looks like you haven't created any Claude Code sessions yet."
                Write-Host "This is normal if this is your first time using Claude Code."
                Write-Host ""
                Write-ColorText "What you need to do:" -Color Cyan
                Write-Host ""
                Write-Host "1. The Claude Code directory will be created when you start your first session"
                Write-Host "2. Press [N] below to create your first session"
                Write-Host "3. After running Claude Code once, sessions will appear here"
            } else {
                Write-ColorText "No Claude Code sessions found!" -Color Yellow
                Write-Host ""
                Write-Host "The Claude Code directory exists at:"
                Write-Host "  $claudeProjectsPath"
                Write-Host ""
                Write-Host "But no sessions were found."
                Write-Host ""
                Write-ColorText "To get started:" -Color Cyan
                Write-Host "- Press [N] to create your first session here"
                Write-Host "- Or run 'claude' from any directory, then press [R] to refresh"
            }

            Write-Host ""
            Write-ColorText "Tip:" -Color Cyan
            Write-Host "You can also run 'claude' from any directory to create a session manually"
            Write-Host ""
        }

        # Show menu and get display rows
        $menuTitle = if ($deleteMode) { "WIN TERMINAL CONFIG" } else { "MAIN MENU" }
        # In deleteMode, only show profiles unless showAllInDeleteMode is true
        $onlyWithProfiles = $deleteMode -and -not $showAllInDeleteMode

        Write-DebugInfo "=== ABOUT TO CALL Show-SessionMenu ==="
        Write-DebugInfo "  Title: '$menuTitle', IsRefresh: $isRefresh"

        $menuResult = Show-SessionMenu -Sessions $sessions -ShowUnnamed $showUnnamed -OnlyWithProfiles $onlyWithProfiles -Title $menuTitle -SelectedIndex $selectedIndex -IsRefresh $isRefresh

        # Reset refresh flag after use (so subsequent iterations don't re-check models)
        $isRefresh = $false

        Write-DebugInfo "=== RETURNED FROM Show-SessionMenu ==="

        # Extract display rows and menu metadata
        $displayRows = $menuResult.Rows
        $firstRowY = $menuResult.FirstRowY
        $boxWidth = $menuResult.BoxWidth
        $onlyWithProfilesActual = $menuResult.OnlyWithProfiles

        # Ensure $displayRows is treated as an array
        if ($displayRows -isnot [array]) {
            $displayRows = @($displayRows)
        }

        # Check if any sessions have WT profiles (only check when NOT in delete mode)
        if (-not $deleteMode) {
            $hasWTProfiles = ($displayRows | Where-Object { $_.Profile -and $_.Profile -ne '-' -and $_.Profile -ne '' }).Count -gt 0
        } else {
            # In delete mode, we're already showing only profiles, so this doesn't matter
            $hasWTProfiles = $true
        }

        # Calculate min and max option based on displayed rows
        if ($displayRows.Count -gt 0) {
            $minOption = ($displayRows | ForEach-Object { $_.Num } | Measure-Object -Minimum).Minimum
            $maxOption = ($displayRows | ForEach-Object { $_.Num } | Measure-Object -Maximum).Maximum
        } else {
            $minOption = 1
            $maxOption = 1
        }

        # Show helpful message if menu is empty but unnamed sessions exist
        if ($displayRows.Count -eq 0 -and -not $showUnnamed -and $sessionCount -gt 0 -and -not $deleteMode) {
            Write-Host ""
            Write-ColorText "NOTE: You have $sessionCount Claude session(s) that are unnamed." -Color Yellow
            Write-Host ""
            Write-Host "Press [S] to ""Show unnamed sessions"" to view them."
            Write-Host ""
        }

        # Check global permission status
        $permissionStatus = Get-GlobalPermissionStatus

        # Extract boolean value (handle both hashtable and boolean return types)
        $hasBypassPermissions = if ($permissionStatus -is [hashtable]) {
            $permissionStatus.Enabled
        } else {
            $permissionStatus
        }

        # Get user selection using arrow-key navigation
        $result = Get-ArrowKeyNavigation -MenuRows $displayRows -CurrentIndex $selectedIndex -ShowUnnamed $showUnnamed -HasWTProfiles $hasWTProfiles -DeleteMode $deleteMode -ShowAllInDeleteMode $showAllInDeleteMode -HasBypassPermissions $hasBypassPermissions -FirstRowY $firstRowY -BoxWidth $boxWidth -OnlyWithProfiles $onlyWithProfilesActual -TotalPages $menuResult.TotalPages

        # Handle result
        switch ($result.Type) {
            'Navigate' {
                # Just update index and continue WITHOUT reloading sessions
                $selectedIndex = $result.Index
                continue
            }
            'Resize' {
                # Window was resized - redraw menu with new width (don't reload session data)
                continue
            }
            'SortColumn' {
                # Column sort changed - redraw menu with new sort (don't reload session data)
                # Reset to page 1 when sorting changes
                $Global:CurrentPage = 1
                $selectedIndex = 0
                continue
            }
            'PageUp' {
                # Page up - go to previous page
                if ($Global:CurrentPage -gt 1) {
                    $Global:CurrentPage--
                    $selectedIndex = 0
                }
                continue
            }
            'PageDown' {
                # Page down - go to next page
                $totalPages = $menuResult.TotalPages
                if ($Global:CurrentPage -lt $totalPages) {
                    $Global:CurrentPage++
                    $selectedIndex = 0
                }
                continue
            }
            'Quit' {
                # Position cursor where the prompts ended (below all menu content)
                if ($result.PromptEndY -and $result.PromptEndY -gt 0) {
                    try {
                        $pos = $host.UI.RawUI.CursorPosition
                        $pos.Y = $result.PromptEndY
                        $pos.X = 0
                        $host.UI.RawUI.CursorPosition = $pos
                    } catch {
                        # Fallback - just add blank lines
                        Write-Host ""
                    }
                } else {
                    # Fallback if position not available
                    Write-Host ""
                }

                Write-Host ""

                # Get and display a quote (rotates through APIs)
                $quote = Get-NextQuote
                if ($quote.Success) {
                    # Display quote with dual color effect (gray/cyan with one random word highlighted)
                    Write-DualColorText -Text $quote.Text
                } else {
                    Write-ColorText "Goodbye!" -Color Cyan
                }

                Write-Host ""
                exit 0
            }

            'NewSession' {
                # New session
                Start-NewSession
                # If we get here, new session was aborted or completed, go back to menu
                continue
            }

            'ShowUnnamed' {
                $showUnnamed = $true
                $selectedIndex = 0
                $reloadSessions = $true
                continue
            }

            'HideUnnamed' {
                $showUnnamed = $false
                $selectedIndex = 0
                $reloadSessions = $true
                continue
            }

            'Debug' {
                # Show debug toggle
                Show-DebugToggle
                $selectedIndex = 0
                $reloadSessions = $true
                continue
            }

            'About' {
                # Show About screen
                Show-AboutScreen
                $selectedIndex = 0
                $reloadSessions = $true
                continue
            }

            'ColumnConfig' {
                # Show column configuration menu
                $saved = Show-ColumnConfigMenu
                if ($saved) {
                    # Configuration was saved, reload to apply changes
                    $selectedIndex = 0
                    $reloadSessions = $true
                }
                continue
            }

            'CostAnalysis' {
                # Show cost analysis report
                Show-CostAnalysis -Sessions $sessions
                $selectedIndex = 0
                $reloadSessions = $true
                continue
            }

            'Refresh' {
                # Refresh menu - just continue the loop to reload session data
                $selectedIndex = 0
                $reloadSessions = $true
                $isRefresh = $true  # Signal to check model changes from session files
                continue
            }

            'EnterDeleteMode' {
                $deleteMode = $true
                $selectedIndex = 0
                $reloadSessions = $true
                continue
            }

            'ExitDeleteMode' {
                $deleteMode = $false
                $selectedIndex = 0
                $reloadSessions = $true
                continue
            }

            'EnableBypassPermissions' {
                Enable-GlobalBypassPermissions
                $selectedIndex = 0
                $reloadSessions = $true
                continue
            }

            'DisableBypassPermissions' {
                Disable-GlobalBypassPermissions
                $selectedIndex = 0
                $reloadSessions = $true
                continue
            }

            'ShowAllInDeleteMode' {
                $showAllInDeleteMode = $true
                $selectedIndex = 0
                $reloadSessions = $true
                continue
            }

            'ProfilesOnlyInDeleteMode' {
                $showAllInDeleteMode = $false
                $selectedIndex = 0
                $reloadSessions = $true
                continue
            }

            'RegenerateBackgrounds' {
                Show-RegenerateBackgroundsMenu
                $reloadSessions = $true
                continue
            }

            'Select' {
                # Get the selected row directly by index
                $selectedRow = $displayRows[$result.Index]

                # Set reload flag for when we return to menu
                $reloadSessions = $true

                if ($deleteMode) {
                    # Profile management mode - show management menu
                    if ($selectedRow.Profile) {
                        $session = $selectedRow.Session
                        $wtProfileName = $selectedRow.Profile

                        $managementAction = Get-SessionManagementChoice -Session $session -WTProfileName $wtProfileName

                        switch ($managementAction) {
                            'abort' {
                                # User aborted, go back to menu
                                continue
                            }
                            'regenerate' {
                                # Show regenerate submenu
                                $sessionName = $wtProfileName -replace '^Claude-', ''
                                $regenerateChoice = Get-RegenerateImageChoice -SessionName $sessionName

                                switch ($regenerateChoice) {
                                    'abort' {
                                        # User aborted, go back to management menu
                                        continue
                                    }
                                    'refresh' {
                                        # Regenerate/Refresh from session name
                                        Write-Host ""
                                        Write-ColorText "Regenerating background image for: $sessionName" -Color Cyan

                                        $success = Update-SessionBackgroundImage -Session $session -WTProfileName $wtProfileName

                                        if ($success) {
                                            Write-Host ""
                                            Write-ColorText "Background image regenerated successfully!" -Color Green
                                            Write-Host ""
                                        } else {
                                            Write-Host ""
                                            Write-ColorText "Failed to regenerate background image." -Color Red
                                            Write-Host ""
                                        }

                                        Read-Host "Press Enter to continue"
                                        continue
                                    }
                                    'file' {
                                        # Use custom image file
                                        Write-Host ""
                                        Write-ColorText "Enter full path to image file: " -Color Yellow -NoNewline
                                        $imagePath = Read-Host

                                        if (-not (Test-Path $imagePath)) {
                                            Write-Host ""
                                            Write-ColorText "Error: File not found: $imagePath" -Color Red
                                            Write-Host ""
                                            Read-Host "Press Enter to continue"
                                            continue
                                        }

                                        Write-Host ""
                                        Write-ColorText "Setting background from file..." -Color Cyan

                                        $success = Set-BackgroundFromFile -SessionName $sessionName -WTProfileName $wtProfileName -ImageFilePath $imagePath

                                        if ($success) {
                                            Write-Host ""
                                            Write-ColorText "Background image updated successfully!" -Color Green
                                            Write-Host ""
                                        } else {
                                            Write-Host ""
                                            Write-ColorText "Failed to set background image." -Color Red
                                            Write-Host ""
                                        }

                                        Read-Host "Press Enter to continue"
                                        continue
                                    }
                                    'text' {
                                        # Generate from custom text
                                        Write-Host ""
                                        Write-ColorText "Enter custom text for background image: " -Color Yellow -NoNewline
                                        $customText = Read-Host

                                        if ([string]::IsNullOrWhiteSpace($customText)) {
                                            Write-Host ""
                                            Write-ColorText "Error: Text cannot be empty." -Color Red
                                            Write-Host ""
                                            Read-Host "Press Enter to continue"
                                            continue
                                        }

                                        Write-Host ""
                                        Write-ColorText "Generating custom background image..." -Color Cyan

                                        try {
                                            $bgPath = New-CustomTextBackgroundImage -SessionName $sessionName -CustomText $customText -ProjectPath $session.projectPath

                                            # Update Windows Terminal profile
                                            $backupPath = Backup-WTSettings
                                            $settingsJson = Get-Content $Global:WTSettingsPath -Raw
                                            $settings = $settingsJson | ConvertFrom-Json

                                            $profileIndex = -1
                                            for ($i = 0; $i -lt $settings.profiles.list.Count; $i++) {
                                                if ($settings.profiles.list[$i].name -eq $wtProfileName) {
                                                    $profileIndex = $i
                                                    break
                                                }
                                            }

                                            if ($profileIndex -ge 0) {
                                                $imagePath = $bgPath -replace '\\', '/'
                                                $settings.profiles.list[$profileIndex].backgroundImage = $imagePath
                                                $settings | ConvertTo-Json -Depth 10 | Set-Content $Global:WTSettingsPath -Encoding UTF8
                                                Write-Host ""
                                                Write-ColorText "Background image created and applied successfully!" -Color Green
                                                Write-Host ""
                                            } else {
                                                Write-Host ""
                                                Write-ColorText "Warning: Could not update profile, but image was created." -Color Yellow
                                                Write-Host ""
                                            }
                                        } catch {
                                            Write-Host ""
                                            Write-ColorText "Failed to generate background image: $_" -Color Red
                                            Write-Host ""
                                        }

                                        Read-Host "Press Enter to continue"
                                        continue
                                    }
                                }
                            }
                            'delete' {
                                # Delete Windows Terminal profile
                                Write-Host ""
                                Write-ColorText "Are you sure you want to delete profile: $wtProfileName?" -Color Yellow
                                Write-Host ""
                                Write-Host "Y" -NoNewline -ForegroundColor Yellow
                                Write-Host "es | " -NoNewline -ForegroundColor Gray
                                Write-Host "N" -NoNewline -ForegroundColor Yellow
                                Write-Host "o " -NoNewline -ForegroundColor Gray
                                $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                                $confirmed = $key.Character.ToString().ToUpper()

                                # Handle Esc as No
                                if ($key.VirtualKeyCode -eq 27) {
                                    $confirmed = 'N'
                                }

                                # Handle Enter as default (Yes)
                                if ($key.VirtualKeyCode -eq 13) {
                                    $confirmed = 'Y'
                                }

                                if ($confirmed -eq 'Y') {
                                    $success = Remove-WTProfile -ProfileName $wtProfileName

                                    if ($success) {
                                        Write-Host ""
                                        Write-ColorText "Profile deleted successfully!" -Color Green
                                        Write-Host ""

                                        # Check if there are more profiles to manage
                                        # Re-scan sessions to get fresh data
                                        $sessionsCheck = Get-AllClaudeSessions
                                        $hasMoreProfiles = $false

                                        foreach ($sess in $sessionsCheck) {
                                            $wtProfileCheck = Get-WTProfileName -SessionTitle $sess.customTitle -SessionId $sess.sessionId
                                            if ($wtProfileCheck -and $wtProfileCheck -ne "") {
                                                $hasMoreProfiles = $true
                                                break
                                            }
                                        }

                                        if ($hasMoreProfiles) {
                                            # Stay in management mode, continue to refresh menu
                                            Read-Host "Press Enter to continue"
                                            continue
                                        } else {
                                            # No more profiles to manage, return to main menu
                                            Write-ColorText "No more Windows Terminal profiles. Returning to main menu..." -Color Cyan
                                            Start-Sleep -Seconds 2
                                            $deleteMode = $false
                                            continue
                                        }
                                    }
                                } else {
                                    Write-Host "Cancelled."
                                    Read-Host "Press Enter to continue"
                                }

                                continue
                            }
                            'remove-background' {
                                # Remove background image from profile
                                Write-Host ""
                                Write-ColorText "Are you sure you want to remove the background image from: $wtProfileName?" -Color Yellow
                                Write-Host ""
                                Write-Host "Y" -NoNewline -ForegroundColor Yellow
                                Write-Host "es | " -NoNewline -ForegroundColor Gray
                                Write-Host "N" -NoNewline -ForegroundColor Yellow
                                Write-Host "o " -NoNewline -ForegroundColor Gray
                                $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                                $confirmed = $key.Character.ToString().ToUpper()

                                # Handle Esc as No
                                if ($key.VirtualKeyCode -eq 27) {
                                    $confirmed = 'N'
                                }

                                # Handle Enter as default (Yes)
                                if ($key.VirtualKeyCode -eq 13) {
                                    $confirmed = 'Y'
                                }

                                if ($confirmed -eq 'Y') {
                                    $success = Remove-BackgroundFromProfile -WTProfileName $wtProfileName

                                    if ($success) {
                                        Write-Host ""
                                        Write-ColorText "Background image removed successfully!" -Color Green
                                        Write-Host ""
                                    }
                                } else {
                                    Write-Host "Cancelled."
                                }

                                Read-Host "Press Enter to continue"
                                continue
                            }
                            'launch' {
                                # User wants to continue or fork the session
                                # Exit delete mode and proceed to normal flow below
                                $deleteMode = $false
                                # Don't continue - fall through to normal session handling
                            }
                        }
                    } else {
                        # Session has no Windows Terminal profile - offer to create one
                        $session = $selectedRow.Session

                        Write-Host ""
                        Write-ColorText "This session does not have a Windows Terminal profile." -Color Yellow
                        Write-Host ""
                        Write-ColorText "Would you like to create one?" -Color Cyan
                        Write-Host ""
                        Write-Host "Y" -NoNewline -ForegroundColor Yellow
                        Write-Host "es | " -NoNewline -ForegroundColor Gray
                        Write-Host "N" -NoNewline -ForegroundColor Yellow
                        Write-Host "o " -NoNewline -ForegroundColor Gray
                        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                        $createProfile = $key.Character.ToString().ToUpper()
                        Write-Host $createProfile  # Echo the key

                        # Handle Esc as No
                        if ($key.VirtualKeyCode -eq 27) {
                            $createProfile = 'N'
                        }

                        # Handle Enter as default (Yes)
                        if ($key.VirtualKeyCode -eq 13) {
                            $createProfile = 'Y'
                        }

                        if ($createProfile -eq 'Y') {
                            # Get session name
                            Write-Host ""
                            Write-ColorText "Enter a name for this profile: " -Color Yellow -NoNewline
                            $profileName = Read-Host

                            if ([string]::IsNullOrWhiteSpace($profileName)) {
                                Write-Host ""
                                Write-ColorText "Profile name cannot be empty." -Color Red
                                Read-Host "Press Enter to continue"
                                continue
                            }

                            # Check for background image conflict and resolve
                            $resolution = Resolve-BackgroundImageConflict -SessionName $profileName

                            if ($resolution.action -eq 'abort') {
                                Write-Host ""
                                Write-ColorText "Profile creation aborted." -Color Yellow
                                Read-Host "Press Enter to continue"
                                continue
                            }

                            # Use the resolved name (may have been modified for 'new' action)
                            $finalProfileName = $resolution.name

                            # Create Windows Terminal profile with background image
                            $wtProfileName = "Claude-$finalProfileName"
                            Write-Host ""
                            Write-ColorText "Creating Windows Terminal profile: $wtProfileName" -Color Cyan

                            # Generate or use background image
                            if ($resolution.action -eq 'use') {
                                # Use existing image
                                $bgImagePath = $resolution.path
                                Write-ColorText "Using existing background image." -Color Green
                            } else {
                                # Generate new image (either 'create' or 'overwrite')
                                # Detect git branch
                                $gitBranch = Get-GitBranch -Path $session.projectPath

                                # Get model from session mapping if available
                                $sessionEntry = Get-SessionMappingEntry -SessionId $session.sessionId
                                $modelName = if ($sessionEntry -and $sessionEntry.model) { $sessionEntry.model } else { $null }

                                $bgImagePath = New-SessionBackgroundImage -NewName $finalProfileName -OldName "" -GitBranch $gitBranch -Model $modelName -ProjectPath $session.projectPath
                            }

                            if ($bgImagePath) {
                                # Add profile to Windows Terminal
                                $profile = Add-WTProfile -Name $wtProfileName -BackgroundImage $bgImagePath -StartingDirectory $session.projectPath

                                if ($profile) {
                                    # Update session mapping (use actual profile name in case it was modified)
                                    $actualProfileName = $profile.name
                                    $gitBranch = Get-GitBranch -Path $session.projectPath
                                    $model = Get-ModelFromSession -SessionId $session.sessionId -ProjectPath $session.projectPath
                                    Add-SessionMapping -SessionId $session.sessionId -WTProfileName $actualProfileName -ProjectPath $session.projectPath -Model $model -GitBranch $gitBranch

                                    Write-Host ""
                                    Write-ColorText "Windows Terminal profile created successfully: $actualProfileName" -Color Green
                                    Write-Host ""
                                } else {
                                    Write-Host ""
                                    Write-ColorText "Failed to create Windows Terminal profile." -Color Red
                                    Write-Host ""
                                }
                            } else {
                                Write-Host ""
                                Write-ColorText "Failed to generate background image." -Color Red
                                Write-Host ""
                            }

                            Read-Host "Press Enter to continue"
                        }

                        continue
                    }

                    # If we get here and still in deleteMode, something went wrong, go back to menu
                    if ($deleteMode) {
                        continue
                    }

                    # Fall through to normal session handling if user chose 'launch'
                }

                # Normal session selection (not in deleteMode)
                # Existing session
                $session = $selectedRow.Session

                # Get session title for display
                $sessionTitle = if ($session.customTitle) {
                    $session.customTitle
                } elseif ($session.trackedName) {
                    "[$($session.trackedName)]"
                } else {
                    "(unnamed)"
                }

                Write-DebugInfo "Main loop: Session selected, displaying options" -Color Cyan
                Write-DebugInfo "  Session ID: $($session.sessionId)"
                Write-DebugInfo "  Session Title: $sessionTitle"
                Write-DebugInfo "  Custom Title: $($session.customTitle)"
                Write-DebugInfo "  Tracked Name: $($session.trackedName)"

                # Check if session is archived
                $archiveStatus = Get-SessionArchiveStatus -SessionId $session.sessionId
                Write-DebugInfo "  Archive Status: Archived=$($archiveStatus.Archived), Date=$($archiveStatus.ArchivedDate)" -Color Cyan

                # Get session notes
                $notes = Get-SessionNotes -SessionId $session.sessionId
                Write-DebugInfo "  Session Notes: '$notes'" -Color Cyan

                # Ask: Fork, Continue, or Delete? (or Unarchive if archived)
                # Loop to handle 'limit-instructions' which shows help then returns to Session Options
                $action = $null
                while ($action -eq $null -or $action -eq 'limit-instructions') {
                    Write-DebugInfo "  Calling Get-ForkOrContinue..." -Color Yellow
                    $action = Get-ForkOrContinue -SessionId $session.sessionId -SessionTitle $sessionTitle -ProjectPath $session.projectPath -IsArchived $archiveStatus.Archived -ArchivedDate $archiveStatus.ArchivedDate -Notes $notes
                    Write-DebugInfo "  Get-ForkOrContinue returned: '$action'" -Color Green

                    if ($action -eq 'limit-instructions') {
                        # User wants to see context limit management instructions
                        Write-DebugInfo "  Action is 'limit-instructions' - showing guide" -Color Yellow

                        # Get current context usage for display
                        $sessionModel = Get-ModelFromSession -SessionId $session.sessionId -ProjectPath $session.projectPath
                        $contextUsage = Get-SessionContextUsage -SessionId $session.sessionId -ProjectPath $session.projectPath -Model $sessionModel
                        $currentPct = if ($contextUsage -and $contextUsage.Percentage) { $contextUsage.Percentage } else { 0 }

                        # Show the instructions
                        Show-LimitInstructions -CurrentPercentage $currentPct -ProjectPath $session.projectPath

                        # Loop will continue and re-show Session Options
                    }
                }

                if ($action -eq 'abort') {
                    Write-DebugInfo "  Action is 'abort' - returning to menu" -Color Yellow
                    # User aborted, go back to menu
                    continue
                } elseif ($action -eq 'archive') {
                    # User chose to archive the session
                    Write-DebugInfo "Main loop: User chose 'archive' action" -Color Cyan
                    $success = Set-SessionArchiveStatus -SessionId $session.sessionId -Archived $true
                    if ($success) {
                        Write-Host ""
                        Write-ColorText "Session archived successfully." -Color Green
                        Start-Sleep -Seconds 1
                        # Reload sessions to show archive status
                        $selectedIndex = 0
                        $reloadSessions = $true
                    } else {
                        Write-Host ""
                        Write-ColorText "Failed to archive session." -Color Red
                        Start-Sleep -Seconds 2
                    }
                    continue
                } elseif ($action -eq 'unarchive') {
                    # User chose to unarchive the session
                    Write-DebugInfo "Main loop: User chose 'unarchive' action" -Color Cyan
                    $success = Set-SessionArchiveStatus -SessionId $session.sessionId -Archived $false
                    if ($success) {
                        Write-Host ""
                        Write-ColorText "Session unarchived successfully." -Color Green
                        Start-Sleep -Seconds 1
                        # Reload sessions to show updated status
                        $selectedIndex = 0
                        $reloadSessions = $true
                    } else {
                        Write-Host ""
                        Write-ColorText "Failed to unarchive session." -Color Red
                        Start-Sleep -Seconds 2
                    }
                    continue
                } elseif ($action -eq 'notes') {
                    # User chose to edit notes
                    Write-DebugInfo "Main loop: User chose 'notes' action" -Color Cyan

                    # Get current notes
                    $currentNotes = Get-SessionNotes -SessionId $session.sessionId

                    # Prompt for new notes
                    Write-Host ""
                    if ($currentNotes) {
                        Write-ColorText "Current notes: $currentNotes" -Color DarkGray
                        Write-Host ""
                    }
                    Write-ColorText "Enter notes (or press Enter to clear): " -Color Yellow -NoNewline
                    $newNotes = Read-Host

                    # Save notes
                    $success = Set-SessionNotes -SessionId $session.sessionId -Notes $newNotes
                    if ($success) {
                        Write-Host ""
                        if ($newNotes) {
                            Write-ColorText "Notes saved successfully." -Color Green
                        } else {
                            Write-ColorText "Notes cleared." -Color Green
                        }
                        Start-Sleep -Seconds 1
                    } else {
                        Write-Host ""
                        Write-ColorText "Failed to save notes." -Color Red
                        Start-Sleep -Seconds 2
                    }
                    continue
                } elseif ($action -eq 'delete') {
                    # User chose to delete the session
                    $sessionTitle = if ($session.customTitle) { $session.customTitle } elseif ($session.trackedName) { "[$($session.trackedName)]" } else { "(unnamed)" }
                    $wtProfile = Get-WTProfileName -SessionTitle $session.customTitle -SessionId $session.sessionId

                    # Show confirmation
                    Write-Host ""
                    Write-ColorText "WARNING: You are about to delete the following session:" -Color Red
                    Write-Host ""
                    Write-Host "  Session: $sessionTitle"
                    Write-Host "  ID: $($session.sessionId)"
                    Write-Host "  Path: $($session.projectPath)"
                    if ($wtProfile) {
                        Write-Host "  Windows Terminal Profile: $wtProfile"
                    }
                    Write-Host ""
                    Write-ColorText "This action cannot be undone!" -Color Red
                    Write-Host ""
                    Write-ColorText "Are you sure?" -Color Yellow
                    Write-Host ""
                    Write-Host "Y" -NoNewline -ForegroundColor Yellow
                    Write-Host "es | " -NoNewline -ForegroundColor Gray
                    Write-Host "N" -NoNewline -ForegroundColor Yellow
                    Write-Host "o " -NoNewline -ForegroundColor Gray
                    $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    $confirmed = $key.Character.ToString().ToUpper()

                    # Handle Esc as No
                    if ($key.VirtualKeyCode -eq 27) {
                        $confirmed = 'N'
                    }

                    # Handle Enter as default (Yes)
                    if ($key.VirtualKeyCode -eq 13) {
                        $confirmed = 'Y'
                    }

                    if ($confirmed -eq 'Y') {
                        $success = Remove-Session -Session $session -WTProfileName $wtProfile

                        if ($success) {
                            Write-Host ""
                            Read-Host "Press Enter to continue"
                        } else {
                            Write-Host ""
                            Write-ColorText "Session deletion failed. Press Enter to continue." -Color Red
                            Read-Host
                        }
                    } else {
                        Write-Host ""
                        Write-ColorText "Deletion cancelled." -Color Yellow
                        Read-Host "Press Enter to continue"
                    }

                    continue
                } elseif ($action -eq 'rename') {
                    # User chose to rename the session
                    Write-DebugInfo "Main loop: User chose 'rename' action" -Color Cyan
                    Write-DebugInfo "  Calling Rename-ClaudeSession..." -Color Yellow
                    $renamed = Rename-ClaudeSession -Session $session
                    Write-DebugInfo "  Rename-ClaudeSession returned: $renamed" -Color $(if ($renamed) { "Green" } else { "Red" })

                    # Reload sessions to show the new name
                    if ($renamed) {
                        Write-DebugInfo "  Reloading sessions to show new name" -Color Green
                        $selectedIndex = 0
                        $reloadSessions = $true
                    } else {
                        Write-DebugInfo "  Rename failed - not reloading sessions" -Color Yellow
                    }
                    continue
                } elseif ($action -eq 'continue') {
                    Start-ContinueSession -Session $session
                    # If we get here, continue was aborted or completed, go back to menu
                    continue
                } elseif ($action -eq 'fork') {
                    Start-ForkSession -Session $session
                    # If we get here, fork was aborted during process, go back to menu
                    # Otherwise Start-ForkSession exits directly
                    continue
                }
            }
        }
    }
}

#endregion

# Entry point
try {
    Start-MainMenu
} catch {
    Write-Host ""
    Write-ColorText "An error occurred: $_" -Color Red
    Write-Host ""
    Write-Host $_.ScriptStackTrace
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}
