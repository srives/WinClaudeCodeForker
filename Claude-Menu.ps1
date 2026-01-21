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
    Version: 1.4.0
    Date: 2026-01-20
    Requires: PowerShell 5.1+, Windows Terminal, Claude CLI
#>

# Global error handling
$ErrorActionPreference = "Stop"
$Global:ScriptVersion = "2026.1.20"
$Global:MenuPath = "$env:USERPROFILE\.claude-menu"
$Global:ProfileRegistryPath = "$Global:MenuPath\profile-registry.json"
$Global:SessionMappingPath = "$Global:MenuPath\session-mapping.json"
$Global:BackgroundTrackingPath = "$Global:MenuPath\background-tracking.json"
$Global:DebugStatePath = "$Global:MenuPath\debug.txt"
$Global:DebugLogPath = "$Global:MenuPath\debug.log"
$Global:QuoteStatePath = "$Global:MenuPath\quote-state.json"
$Global:WTSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$Global:ClaudePath = "$env:USERPROFILE\.claude"
$Global:LastClaudeCommand = $null
$Global:LastClaudeError = $null
$Global:PathCache = @{}
$Global:ClaudeProjectsPath = "$env:USERPROFILE\.claude\projects"
$Global:ClaudeSettingsPath = "$env:USERPROFILE\.claude\settings.json"
$Global:TokenUsageCache = @{}
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

function Show-DebugToggle {
    <#
    .SYNOPSIS
        Shows debug menu with options to toggle, view log, or see instructions
    #>

    # Position cursor below main menu
    if ($Global:PromptEndY -gt 0) {
        try {
            $pos = $host.UI.RawUI.CursorPosition
            $pos.Y = $Global:PromptEndY
            $pos.X = 0
            $host.UI.RawUI.CursorPosition = $pos
        } catch {
            # Fallback - just add blank lines
            Write-Host ""
        }
    }

    $currentState = Get-DebugState
    $stateText = if ($currentState) { "ON" } else { "OFF" }
    $stateColor = if ($currentState) { "Green" } else { "Red" }

    $continue = $true
    while ($continue) {
        Write-Host ""
        Write-ColorText "========================================" -Color Cyan
        Write-ColorText "  DEBUG MODE" -Color Cyan
        Write-ColorText "========================================" -Color Cyan
        Write-Host ""
        Write-Host "Current state: " -NoNewline
        Write-Host $stateText -ForegroundColor $stateColor
        Write-Host ""
        Write-Host "Options:"
        $toggleText = if ($currentState) { "Turn Debug Off" } else { "Turn Debug On" }
        Write-Host "  1. $toggleText"
        Write-Host "  2. Notepad Debug Log"
        Write-Host "  3. Show instructions"
        Write-Host "  4. Abort"
        Write-Host ""
        Write-ColorText "Choice [1-4]: " -Color Yellow -NoNewline
        $response = Read-Host

        switch ($response) {
            '1' {
                # Toggle debug flag
                $newState = -not $currentState
                Set-DebugState -Enabled $newState

                # Exit back to main menu
                $continue = $false
            }
            '2' {
                # Open debug log in notepad
                if (Test-Path $Global:DebugLogPath) {
                    Start-Process notepad.exe -ArgumentList $Global:DebugLogPath
                } else {
                    Write-Host ""
                    Write-ColorText "Debug log file does not exist yet." -Color Yellow
                }

                # Exit back to main menu
                $continue = $false
            }
            '3' {
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

                # Exit back to main menu
                $continue = $false
            }
            '4' {
                # Abort - return to main menu
                $continue = $false
            }
            default {
                Write-Host ""
                Write-ColorText "Invalid choice. Please enter 1-4." -Color Red
                Write-Host ""
                Start-Sleep -Seconds 1
            }
        }
    }
}

#endregion

#region Cost Tracking

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
    $inputRate = 3.00 / 1000000
    $cacheWriteRate = 3.75 / 1000000
    $cacheReadRate = 0.30 / 1000000
    $outputRate = 15.00 / 1000000

    $inputCost = $TokenUsage.InputTokens * $inputRate
    $cacheWriteCost = $TokenUsage.CacheCreationTokens * $cacheWriteRate
    $cacheReadCost = $TokenUsage.CacheReadTokens * $cacheReadRate
    $outputCost = $TokenUsage.OutputTokens * $outputRate

    $totalCost = $inputCost + $cacheWriteCost + $cacheReadCost + $outputCost

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

    # Position cursor below main menu
    if ($Global:PromptEndY -gt 0) {
        try {
            $pos = $host.UI.RawUI.CursorPosition
            $pos.Y = $Global:PromptEndY
            $pos.X = 0
            $host.UI.RawUI.CursorPosition = $pos
        } catch {
            # Fallback - just add blank lines
            Write-Host ""
        }
    }

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
        $inputStr = (Format-TokenCount -Count $sc.InputTokens).PadRight(8)
        $outputStr = (Format-TokenCount -Count $sc.OutputTokens).PadRight(8)
        $cacheStr = (Format-TokenCount -Count ($sc.CacheWrites + $sc.CacheReads)).PadRight(8)
        $hitStr = if ($sc.CacheHitRate -gt 0) { "$($sc.CacheHitRate)%" } else { "-" }
        $hitStr = $hitStr.PadRight(6)

        try {
            $created = ([DateTime]$sc.Created).ToString("yyyy-MM-dd HH:mm")
        } catch {
            $created = "N/A"
        }

        Write-Host "$title  $costStr  $inputStr  $outputStr  $cacheStr  $hitStr  $created"
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
    Write-Host ""
    Read-Host "Press Enter to continue"
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
                            $syntheticEntry = [PSCustomObject]@{
                                sessionId = $sessionId
                                customTitle = ""  # Empty - unnamed session
                                projectPath = $projectPath
                                created = $jsonlFile.CreationTime.ToString('o')
                                modified = $jsonlFile.LastWriteTime.ToString('o')
                                messageCount = 0  # We don't know yet
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

    # Now, check session-mapping.json for sessions we've created that Claude hasn't indexed yet
    Write-DebugInfo "Checking session-mapping.json for tracked sessions..." -Color Cyan
    Write-DebugInfo "  Mapping file: $Global:SessionMappingPath"

    if (Test-Path $Global:SessionMappingPath) {
        Write-DebugInfo "  Mapping file EXISTS" -Color Green
        try {
            $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json
            $mappedCount = if ($mapping.sessions) { $mapping.sessions.Count } else { 0 }
            Write-DebugInfo "  Found $mappedCount tracked session(s)" -Color Green

            foreach ($mappedSession in $mapping.sessions) {
                Write-DebugInfo "    Tracked session: $($mappedSession.sessionId)" -Color DarkGray
                Write-DebugInfo "      Profile: $($mappedSession.wtProfileName)" -Color DarkGray
                Write-DebugInfo "      Path: $($mappedSession.projectPath)" -Color DarkGray

                # Skip if we already have this session from Claude's index
                if ($sessionIdsSeen.ContainsKey($mappedSession.sessionId)) {
                    Write-DebugInfo "      Already found in Claude's index - skipping" -Color DarkGray
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

                    # Create a synthetic session entry
                    $syntheticEntry = [PSCustomObject]@{
                        sessionId = $mappedSession.sessionId
                        customTitle = ""  # Empty - we'll show [name] in brackets
                        projectPath = $mappedSession.projectPath
                        created = $mappedSession.created
                        modified = $fileInfo.LastWriteTime.ToString('o')
                        messageCount = 0  # We don't know yet
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
            $profile = $settings.profiles.list | Where-Object { $_.name -eq $profileName }

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
        Validates that Windows Terminal profiles referenced in session mappings actually exist
        Removes invalid profile references
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
            $mapping | ConvertTo-Json -Depth 10 | Set-Content $Global:SessionMappingPath -Encoding UTF8
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
        $profile = $settings.profiles.list | Where-Object { $_.name -eq $ProfileName }

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
        [int]$SelectedIndex = 0
    )

    # Initialize as empty array if null
    if ($null -eq $Sessions) { $Sessions = @() }

    Clear-Host

    # Show screen size in top right corner when debug mode is ON
    if (Get-DebugState) {
        try {
            $windowWidth = $Host.UI.RawUI.WindowSize.Width
            $windowHeight = $Host.UI.RawUI.WindowSize.Height
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
        $consoleWidth = $Host.UI.RawUI.WindowSize.Width
        $padding = [Math]::Max(0, ($consoleWidth - $spacedTitle.Length) / 2)
        Write-Host (" " * $padding) -NoNewline
        Write-Host $spacedTitle -ForegroundColor Cyan
        Write-Host ""
    }

    Write-Host "Claude Code Session Forker, S. Rives, v.$Global:ScriptVersion" -ForegroundColor Cyan
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
        $wtProfile = Get-WTProfileName -SessionTitle $session.customTitle -SessionId $session.sessionId

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

        # Get model - try multiple sources
        $model = ""

        # First, try from registry using customTitle (for older forked sessions)
        if ($session.customTitle) {
            $model = Get-ModelFromRegistry -SessionName $session.customTitle
        }

        # If no model yet, try from session-mapping.json using sessionId
        if (-not $model -and $session.sessionId) {
            $mappingEntry = Get-SessionMappingEntry -SessionId $session.sessionId
            if ($mappingEntry -and $mappingEntry.model) {
                $model = $mappingEntry.model
            }
        }

        # Final fallback: read from session .jsonl file
        if (-not $model) {
            $model = Get-ModelFromSession -SessionId $session.sessionId -ProjectPath $session.projectPath
        }

        # Get fork tree information
        # Use customTitle if available, otherwise use trackedName
        $sessionTitleForFork = if ($session.customTitle) { $session.customTitle } elseif ($session.trackedName) { $session.trackedName } else { "" }
        $forkTree = Get-ForkTree -SessionId $session.sessionId -SessionTitle $sessionTitleForFork -AllSessions $Sessions

        # Get activity marker based on file modification time
        $activeMarker = Get-SessionActivityMarker -SessionId $session.sessionId -ProjectPath $session.projectPath

        # Get cost (with caching to avoid repeated parsing)
        $usage = Get-SessionTokenUsage -SessionId $session.sessionId -ProjectPath $session.projectPath
        $cost = if ($usage) { Get-SessionCost -TokenUsage $usage } else { 0.0 }
        $costDisplay = Format-Cost -Cost $cost

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
            Cost = $costDisplay
            CostValue = [double]$cost  # Ensure numeric for sorting
            Session = $session
            OriginalIndex = $i
            CreatedDate = $created
            ModifiedDate = $modified
        }
    }

    # Sort rows if a column is selected (easter egg feature)
    if ($Global:SortColumn -gt 0 -and $rows.Count -gt 0) {
        $sortProperty = switch ($Global:SortColumn) {
            1 { 'Active' }      # Active marker
            2 { 'Model' }       # Model name
            3 { 'Title' }       # Session title
            4 { 'Messages' }    # Message count
            5 { 'CreatedDate' } # Created date (use date object for proper sorting)
            6 { 'ModifiedDate' }# Modified date (use date object for proper sorting)
            7 { 'CostValue' }   # Cost (numeric value)
            8 { 'Profile' }     # Win Terminal profile
            9 { 'ForkTree' }    # Forked from
            10 { 'Path' }       # Path
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
        $windowHeight = $Host.UI.RawUI.WindowSize.Height
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
        $windowWidth = $Host.UI.RawUI.WindowSize.Width
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

    Write-Host ("+" + ("-" * ($boxWidth - 2)) + "+") -ForegroundColor DarkGray

    # Display header - different format for profile mode
    # Calculate dynamic path width to match row formatting
    if ($OnlyWithProfiles) {
        $pathWidth = [Math]::Max(15, $boxWidth - 121)

        # Column headers with color highlighting for sorted column
        $headers = @("Session", "Messages", "Created", "Modified", "Cost", "WT Profile", "Color Scheme", "Path")
        $headerLines = @("-------", "--------", "-------", "--------", "----", "----------", "------------", "----")
        $headerWidths = @(30, 8, 12, 12, 8, 20, 20, ($pathWidth - 1))
        $widths = @(30, 8, 12, 12, 8, 20, 20, $pathWidth)

        # Map header index to global column number: Session=3, Messages=4, Created=5, Modified=6, Cost=7, WTProfile=8, ColorScheme=none, Path=10
        $headerToColumn = @(3, 4, 5, 6, 7, 8, 0, 10)

        # Write header row
        Write-Host "| " -NoNewline -ForegroundColor DarkGray
        for ($i = 0; $i -lt $headers.Count; $i++) {
            $color = if ($headerToColumn[$i] -eq $Global:SortColumn) { "Yellow" } else { "Cyan" }
            Write-Host ("{0,-$($headerWidths[$i])}" -f $headers[$i]) -NoNewline -ForegroundColor $color
            if ($i -lt $headers.Count - 1) { Write-Host " " -NoNewline }
        }
        Write-Host "  |" -ForegroundColor DarkGray

        # Write separator line
        Write-Host "| " -NoNewline -ForegroundColor DarkGray
        for ($i = 0; $i -lt $headerLines.Count; $i++) {
            $color = if ($headerToColumn[$i] -eq $Global:SortColumn) { "Yellow" } else { "Cyan" }
            Write-Host ("{0,-$($headerWidths[$i])}" -f $headerLines[$i]) -NoNewline -ForegroundColor $color
            if ($i -lt $headerLines.Count - 1) { Write-Host " " -NoNewline }
        }
        Write-Host "  |" -ForegroundColor DarkGray
    } else {
        $pathWidth = [Math]::Max(15, $boxWidth - 147)

        # Column headers with color highlighting for sorted column
        $headers = @("Active", "Model", "Session", "Messages", "Created", "Modified", "Cost", "Win Terminal", "Forked From", "Path")
        $headerLines = @("------", "-----", "-------", "--------", "-------", "--------", "----", "------------", "-----------", "----")
        $headerWidths = @(6, 8, 30, 8, 12, 12, 8, 25, 25, ($pathWidth - 1))
        $widths = @(6, 8, 30, 8, 12, 12, 8, 25, 25, $pathWidth)

        # Write header row
        Write-Host "| " -NoNewline -ForegroundColor DarkGray
        for ($i = 0; $i -lt $headers.Count; $i++) {
            $color = if ($Global:SortColumn -eq ($i + 1)) { "Yellow" } else { "Cyan" }
            Write-Host ("{0,-$($headerWidths[$i])}" -f $headers[$i]) -NoNewline -ForegroundColor $color
            if ($i -lt $headers.Count - 1) { Write-Host " " -NoNewline }
        }
        Write-Host "  |" -ForegroundColor DarkGray

        # Write separator line
        Write-Host "| " -NoNewline -ForegroundColor DarkGray
        for ($i = 0; $i -lt $headerLines.Count; $i++) {
            $color = if ($Global:SortColumn -eq ($i + 1)) { "Yellow" } else { "Cyan" }
            Write-Host ("{0,-$($headerWidths[$i])}" -f $headerLines[$i]) -NoNewline -ForegroundColor $color
            if ($i -lt $headerLines.Count - 1) { Write-Host " " -NoNewline }
        }
        Write-Host "  |" -ForegroundColor DarkGray
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
            Write-Host "| " -NoNewline -ForegroundColor DarkGray
            Write-Host (Truncate-String $rowText ($boxWidth - 4)) -NoNewline -ForegroundColor $rowColor
            Write-Host (" " * [Math]::Max(0, $boxWidth - 4 - $rowText.Length)) -NoNewline
            Write-Host "  |" -ForegroundColor DarkGray
        } else {
            # Calculate dynamic path width: boxWidth - borders(4) - fixed columns(143)
            # Fixed: Active(6) + Model(8) + Session(30) + Messages(8) + Created(12) + Modified(12) + Cost(8) + WinTerminal(25) + ForkedFrom(25) + spaces(9) = 143
            $pathWidth = [Math]::Max(15, $boxWidth - 147)

            $active = Truncate-String $row.Active 6
            $model = Truncate-String $row.Model 8
            $title = Truncate-String $row.Title 30
            $cost = Truncate-String $row.Cost 8
            $profile = Truncate-String $row.Profile 25
            $forkTree = Truncate-String $row.ForkTree 25
            $path = Truncate-String $row.Path $pathWidth -FromLeft
            $rowText = ("{0,-6} {1,-8} {2,-30} {3,-8} {4,-12} {5,-12} {6,-8} {7,-25} {8,-25} {9,-$pathWidth}" -f $active, $model, $title, $row.Messages, $row.Created, $row.Modified, $cost, $profile, $forkTree, $path)
            Write-Host "| " -NoNewline -ForegroundColor DarkGray
            Write-Host (Truncate-String $rowText ($boxWidth - 4)) -NoNewline -ForegroundColor $rowColor
            Write-Host (" " * [Math]::Max(0, $boxWidth - 4 - $rowText.Length)) -NoNewline
            Write-Host "  |" -ForegroundColor DarkGray
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
        $pathWidth = [Math]::Max(15, $BoxWidth - 147)
        $active = Truncate-String $RowData.Active 6
        $model = Truncate-String $RowData.Model 8
        $title = Truncate-String $RowData.Title 30
        $cost = Truncate-String $RowData.Cost 8
        $profile = Truncate-String $RowData.Profile 25
        $forkTree = Truncate-String $RowData.ForkTree 25
        $path = Truncate-String $RowData.Path $pathWidth -FromLeft
        $rowText = ("{0,-6} {1,-8} {2,-30} {3,-8} {4,-12} {5,-12} {6,-8} {7,-25} {8,-25} {9,-$pathWidth}" -f $active, $model, $title, $RowData.Messages, $RowData.Created, $RowData.Modified, $cost, $profile, $forkTree, $path)
    }

    # Draw the row
    Write-Host "| " -NoNewline -ForegroundColor DarkGray
    Write-Host (Truncate-String $rowText ($BoxWidth - 4)) -NoNewline -ForegroundColor $rowColor
    Write-Host (" " * [Math]::Max(0, $BoxWidth - 4 - $rowText.Length)) -NoNewline
    Write-Host "  |" -ForegroundColor DarkGray
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
        $lastKnownWidth = $Host.UI.RawUI.WindowSize.Width
    } catch {
        $lastKnownWidth = 0
    }

    # Track last resize check time for periodic checking
    $lastResizeCheck = Get-Date
    $resizeCheckInterval = 500  # Check every 500ms

    # Display prompt with available commands ONCE
    $debugEnabled = Get-DebugState
    $debugColor = if ($debugEnabled) { "Red" } else { "Yellow" }

    Write-Host ""
    if ($DeleteMode) {
        Write-Host "Use " -NoNewline -ForegroundColor Gray
        Write-Host "UP/DOWN" -NoNewline -ForegroundColor Cyan
        Write-Host " arrows, " -NoNewline -ForegroundColor Gray
        Write-Host "Enter" -NoNewline -ForegroundColor Green
        Write-Host " to select | " -NoNewline -ForegroundColor Gray
        if ($ShowAllInDeleteMode) {
            Write-Host 'P' -NoNewline -ForegroundColor Yellow
            Write-Host "rofiles Only" -NoNewline -ForegroundColor Gray
        } else {
            Write-Host 'A' -NoNewline -ForegroundColor Yellow
            Write-Host "ll Sessions" -NoNewline -ForegroundColor Gray
        }
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
        Write-Host "e" -NoNewline -ForegroundColor Gray
        Write-Host 'X' -NoNewline -ForegroundColor Yellow
        Write-Host "it" -ForegroundColor Gray
    } elseif ($ShowUnnamed) {
        Write-Host "Use " -NoNewline -ForegroundColor Gray
        Write-Host "UP/DOWN" -NoNewline -ForegroundColor Cyan
        Write-Host " arrows, " -NoNewline -ForegroundColor Gray
        Write-Host "Enter" -NoNewline -ForegroundColor Green
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
        Write-Host "ide Unnamed Sessions" -NoNewline -ForegroundColor Gray
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
        Write-Host "UP/DOWN" -NoNewline -ForegroundColor Cyan
        Write-Host " arrows, " -NoNewline -ForegroundColor Gray
        Write-Host "Enter" -NoNewline -ForegroundColor Green
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
        Write-Host "how Unnamed Sessions" -NoNewline -ForegroundColor Gray
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

    # Show last Claude command or error at bottom of screen if available
    if ($Global:LastClaudeError -or $Global:LastClaudeCommand) {
        try {
            $windowHeight = $host.UI.RawUI.WindowSize.Height
            $cursorY = $host.UI.RawUI.CursorPosition.Y
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

    # Capture cursor position after displaying all prompts (for sub-menu positioning)
    $promptEndY = 0
    try {
        $promptEndY = $host.UI.RawUI.CursorPosition.Y
        $Global:PromptEndY = $promptEndY  # Store globally for sub-menu functions
    } catch {
        # Ignore if can't get cursor position
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
                    $currentWidth = $Host.UI.RawUI.WindowSize.Width
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
            # Handle Enter key
            elseif ($key.VirtualKeyCode -eq 13) {  # Enter
                if ($rowCount -gt 0) {
                    return @{ Type = 'Select'; Index = $selectedIndex }
                }
            }
            # Handle single-key commands
            else {
                $char = $key.Character.ToString().ToUpper()

                # Exit/Quit
                if ($char -eq 'X') {
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
                if ($char -eq 'S') {
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
                if ($char -eq 'A' -and $DeleteMode -and -not $ShowAllInDeleteMode) {
                    return @{ Type = 'ShowAllInDeleteMode'; Index = $selectedIndex }
                }
                if ($char -eq 'P' -and $DeleteMode -and $ShowAllInDeleteMode) {
                    return @{ Type = 'ProfilesOnlyInDeleteMode'; Index = $selectedIndex }
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
            Write-Host "ebug, [R]efresh, e[X]it: " -ForegroundColor Yellow -NoNewline
        } elseif ($ShowUnnamed) {
            $wtOption = if ($HasWTProfiles) { ", [W]in Terminal Config" } else { "" }
            $permOption = if ($HasBypassPermissions) { ", [C]hatty Claude Mode" } else { ", [Q]uiet Claude Mode" }
            Write-Host "$range Fork, Join, or Del Session, [N]ew Session$wtOption, [H]ide unnamed sessions$permOption, [O]Cost, " -ForegroundColor Yellow -NoNewline
            Write-Host "[D]" -ForegroundColor $debugColor -NoNewline
            Write-Host "ebug, [R]efresh, e[X]it: " -ForegroundColor Yellow -NoNewline
        } else {
            $wtOption = if ($HasWTProfiles) { ", [W]in Terminal Config" } else { "" }
            $permOption = if ($HasBypassPermissions) { ", [C]hatty Claude Mode" } else { ", [Q]uiet Claude Mode" }
            Write-Host "$range Fork, Join, or Del Session, [N]ew Session$wtOption, [S]how unnamed sessions$permOption, [O]Cost, " -ForegroundColor Yellow -NoNewline
            Write-Host "[D]" -ForegroundColor $debugColor -NoNewline
            Write-Host "ebug, [R]efresh, e[X]it: " -ForegroundColor Yellow -NoNewline
        }

        $input = Read-Host

        # Check for exit
        if ($input -eq 'X' -or $input -eq 'x') {
            if ($DeleteMode) {
                return @{ Type = 'ExitDeleteMode' }
            } else {
                return @{ Type = 'Quit'; PromptEndY = $promptEndY }
            }
        }


        # Check for new session
        if (($input -eq 'N' -or $input -eq 'n') -and -not $DeleteMode) {
            return @{ Type = 'NewSession' }
        }

        # Check for show/hide toggle
        if ($input -eq 'S' -or $input -eq 's') {
            return @{ Type = 'ShowUnnamed' }
        }
        if ($input -eq 'H' -or $input -eq 'h') {
            return @{ Type = 'HideUnnamed' }
        }

        # Check for debug mode
        if ($input -eq 'D' -or $input -eq 'd') {
            return @{ Type = 'Debug' }
        }

        # Check for cost analysis
        if ($input -eq '$') {
            return @{ Type = 'CostAnalysis' }
        }

        # Check for refresh
        if ($input -eq 'R' -or $input -eq 'r') {
            return @{ Type = 'Refresh' }
        }

        # Check for delete mode
        if (($input -eq 'W' -or $input -eq 'w') -and $HasWTProfiles -and -not $DeleteMode) {
            return @{ Type = 'EnterDeleteMode' }
        }

        # Check for quiet claude mode (enable bypass permissions)
        if (($input -eq 'Q' -or $input -eq 'q') -and -not $DeleteMode) {
            return @{ Type = 'EnableBypassPermissions' }
        }

        # Check for chatty claude mode (disable bypass permissions)
        if (($input -eq 'C' -or $input -eq 'c') -and -not $DeleteMode) {
            return @{ Type = 'DisableBypassPermissions' }
        }

        # Check for number selection
        $number = 0
        if ([int]::TryParse($input, [ref]$number)) {
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
    # Position cursor below main menu
    if ($Global:PromptEndY -gt 0) {
        try {
            $pos = $host.UI.RawUI.CursorPosition
            $pos.Y = $Global:PromptEndY
            $pos.X = 0
            $host.UI.RawUI.CursorPosition = $pos
        } catch {
            Write-Host ""  # Fallback
        }
    }

    Write-Host ""
    Write-ColorText "Starting new Claude session..." -Color Cyan
    Write-Host ""
    Write-Host "Current directory: $PWD"
    Write-Host ""

    # Prompt for directory choice
    Write-ColorText "Directory for new session:" -Color Yellow
    Write-Host "  [C] Use current directory (shown above)"
    Write-Host "  [S] Set different directory"
    Write-Host "  [A] Abort"
    Write-Host ""

    $directoryChoice = $null
    $targetDirectory = $PWD.Path.TrimEnd('\')

    while ($true) {
        Write-ColorText "Choice [C/S/A]: " -Color Yellow -NoNewline
        $choice = Read-Host

        if ($choice -eq 'C' -or $choice -eq 'c') {
            # Use current directory
            $targetDirectory = $PWD.Path.TrimEnd('\')
            break
        } elseif ($choice -eq 'S' -or $choice -eq 's') {
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
        } elseif ($choice -eq 'A' -or $choice -eq 'a') {
            Write-Host ""
            Write-ColorText "New session aborted." -Color Yellow
            return
        } else {
            Write-ColorText "Invalid choice. Please enter C, S, or A." -Color Red
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

        # Change to target directory and launch Claude
        Push-Location $targetDirectory
        Start-Process -FilePath $claudePath -NoNewWindow -Wait
        Pop-Location
        exit 0
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

            $bgPath = New-SessionBackgroundImage -NewName $finalSessionName -OldName $originText -GitBranch $gitBranch -Model $model
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
            Add-SessionMapping -SessionId $sessionId -WTProfileName $actualProfileName -ProjectPath $projectPath -Model $model

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
        Write-ColorText "Enter choice [Y/N]: " -Color Yellow -NoNewline
        $deleteChoice = Read-Host

        if ($deleteChoice -eq 'Y' -or $deleteChoice -eq 'y') {
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
    $sessionTitle = if ($Session.customTitle) { $Session.customTitle } else { '(unnamed)' }
    Write-DebugInfo "  Session Title: $sessionTitle"

    # Only create Windows Terminal profiles for named sessions
    if ($Session.customTitle -and $Session.customTitle -ne "") {
        Write-DebugInfo "  Session HAS custom title - checking for WT profile" -Color Cyan
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
                $existingProfile = $settings.profiles.list | Where-Object { $_.name -eq $wtProfileName }
                if ($existingProfile) {
                    Write-DebugInfo "    FOUND existing profile: $($existingProfile.name) (GUID: $($existingProfile.guid))" -Color Green
                } else {
                    Write-DebugInfo "    NO matching profile found" -Color Yellow
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

            $bgPath = New-ContinueSessionBackgroundImage -SessionName $sessionTitle -GitBranch $gitBranch -Model $modelName
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
                    $settings | ConvertTo-Json -Depth 10 | Set-Content $Global:WTSettingsPath -Encoding UTF8
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
                Add-SessionMapping -SessionId $Session.sessionId -WTProfileName $actualProfileName -ProjectPath $Session.projectPath

                Write-ColorText "Windows Terminal profile created: $actualProfileName" -Color Green
                Write-Host ""

                # Show user-friendly launch message
                $displayName = if ($Session.customTitle) { $Session.customTitle } else { $Session.sessionId }
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

                # Fallback to default profile
                $claudePath = Get-ClaudeCLIPath
                $args = "--resume", $Session.sessionId
                Start-Process -FilePath $claudePath -ArgumentList $args -NoNewWindow -Wait
            }
        }
    } else {
        # Unnamed session - offer to create Windows Terminal profile
        Write-DebugInfo "  Session DOES NOT have custom title - unnamed session path" -Color Cyan
        Write-ColorText "Continuing session: $sessionTitle" -Color Green
        Write-Host ""
        Write-ColorText "This session does not have a name or Windows Terminal profile." -Color Yellow
        Write-Host ""
        Write-ColorText "Would you like to create a profile with a custom name? (Y/N): " -Color Cyan -NoNewline
        $createProfile = Read-Host

        Write-DebugInfo "  User response to create profile: $createProfile"

        if ($createProfile -eq 'Y' -or $createProfile -eq 'y') {
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

                # Launch terminal with default profile
                $claudePath = Get-ClaudeCLIPath
                $args = "--resume", $Session.sessionId
                Start-Process -FilePath $claudePath -ArgumentList $args -NoNewWindow -Wait
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

                $bgImagePath = New-SessionBackgroundImage -NewName $finalSafeName -OldName "" -GitBranch $gitBranch -Model $modelName
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
                        Add-SessionMapping -SessionId $Session.sessionId -WTProfileName $actualProfileName -ProjectPath $Session.projectPath
                        Write-DebugInfo "  Session mapping updated successfully" -Color Green

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
                        $displayName = if ($Session.customTitle) { $Session.customTitle } else { $Session.sessionId }
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

                        # Fallback to default profile
                        Write-DebugInfo "  Launching terminal with default profile (fallback)" -Color Yellow
                        $claudePath = Get-ClaudeCLIPath
                        $args = "--resume", $Session.sessionId
                        Start-Process -FilePath $claudePath -ArgumentList $args -NoNewWindow -Wait
                    }
                } catch {
                    Write-DebugInfo "  EXCEPTION in Add-WTProfile: $_" -Color Red
                    Write-ErrorLog "Exception in Start-ContinueSession (Add-WTProfile): $_"
                    Write-ColorText "Error creating profile: $_" -Color Red
                    Write-ColorText "Launching terminal with default profile instead..." -Color Yellow
                    Write-Host ""

                    # Fallback to default profile
                    Write-DebugInfo "  Launching terminal with default profile (exception fallback)" -Color Yellow
                    $claudePath = Get-ClaudeCLIPath
                    $args = "--resume", $Session.sessionId
                    Start-Process -FilePath $claudePath -ArgumentList $args -NoNewWindow -Wait
                }
            } else {
                Write-DebugInfo "  Background image generation FAILED - bgImagePath is null/empty" -Color Red
                Write-Host ""
                Write-ColorText "Failed to generate background image. Launching terminal with default profile..." -Color Red
                Write-Host ""

                # Fallback to default profile
                Write-DebugInfo "  Launching terminal with default profile (no background image)" -Color Yellow
                $claudePath = Get-ClaudeCLIPath
                $args = "--resume", $Session.sessionId
                Start-Process -FilePath $claudePath -ArgumentList $args -NoNewWindow -Wait
            }
        } else {
            # User chose not to create profile - launch terminal with default profile
            Write-DebugInfo "  User chose NO - launching terminal with default profile" -Color Yellow
            Write-Host ""
            Write-ColorText "Launching terminal with default profile..." -Color Cyan
            Write-Host ""

            $claudePath = Get-ClaudeCLIPath
            $args = "--resume", $Session.sessionId
            Write-DebugInfo "  Starting process: $claudePath --resume $($Session.sessionId)"
            Start-Process -FilePath $claudePath -ArgumentList $args -NoNewWindow -Wait
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

    # Position cursor below main menu
    if ($Global:PromptEndY -gt 0) {
        try {
            $pos = $host.UI.RawUI.CursorPosition
            $pos.Y = $Global:PromptEndY
            $pos.X = 0
            $host.UI.RawUI.CursorPosition = $pos
        } catch {
            Write-Host ""  # Fallback
        }
    }

    Write-Host ""
    Write-ColorText "Windows Terminal Profile Management" -Color Cyan
    Write-ColorText "Session: $($Session.customTitle)" -Color DarkGray
    Write-ColorText "Profile: $WTProfileName" -Color DarkGray
    Write-Host ""
    Write-Host "1. Regenerate background image"
    Write-Host "2. Delete Windows Terminal profile"
    Write-Host "3. Remove background image from profile"
    Write-Host ""

    while ($true) {
        Write-ColorText "Enter choice [1-3], [A]bort: " -Color Yellow -NoNewline
        $choice = Read-Host

        switch ($choice) {
            '1' { return 'regenerate' }
            '2' { return 'delete' }
            '3' { return 'remove-background' }
            {$_ -eq 'A' -or $_ -eq 'a'} { return 'abort' }
            default {
                Write-ColorText "Invalid choice. Please enter 1, 2, 3, or A." -Color Red
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

    # Position cursor below main menu
    if ($Global:PromptEndY -gt 0) {
        try {
            $pos = $host.UI.RawUI.CursorPosition
            $pos.Y = $Global:PromptEndY
            $pos.X = 0
            $host.UI.RawUI.CursorPosition = $pos
        } catch {
            Write-Host ""  # Fallback
        }
    }

    Write-Host ""
    Write-ColorText "Regenerate Background Image Options" -Color Cyan
    Write-Host ""
    Write-Host "1. Regenerate/Refresh from session: $SessionName"
    Write-Host "2. Use custom image file"
    Write-Host "3. Generate from custom text"
    Write-Host ""

    while ($true) {
        Write-ColorText "Enter choice [1-3], [A]bort: " -Color Yellow -NoNewline
        $choice = Read-Host

        switch ($choice) {
            '1' { return 'refresh' }
            '2' { return 'file' }
            '3' { return 'text' }
            {$_ -eq 'A' -or $_ -eq 'a'} { return 'abort' }
            default {
                Write-ColorText "Invalid choice. Please enter 1, 2, 3, or A." -Color Red
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
        [string]$ProjectPath = ""
    )

    # Position cursor below main menu
    if ($Global:PromptEndY -gt 0) {
        try {
            $pos = $host.UI.RawUI.CursorPosition
            $pos.Y = $Global:PromptEndY
            $pos.X = 0
            $host.UI.RawUI.CursorPosition = $pos
        } catch {
            Write-Host ""  # Fallback
        }
    }

    Write-Host ""
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
    Write-Host ""

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
    if ($hasProfile) {
        Write-Host "1. Continue - Resume Claude Session with Windows Profile"
    } else {
        Write-Host "1. Continue - Create Windows Terminal Profile and Resume Claude Session"
    }
    Write-Host "2. Fork - Create new branch with custom Windows Terminal profile"
    Write-Host "   (Will fork session: $SessionId)"
    Write-Host "3. Delete session"
    Write-Host ""

    while ($true) {
        Write-ColorText "Enter choice [1-3], [A]bort: " -Color Yellow -NoNewline
        $choice = Read-Host

        if ($choice -eq '1') {
            return 'continue'
        } elseif ($choice -eq '2') {
            return 'fork'
        } elseif ($choice -eq '3') {
            return 'delete'
        } elseif ($choice -eq 'A' -or $choice -eq 'a') {
            return 'abort'
        } else {
            Write-ColorText "Invalid choice. Please enter 1, 2, 3, or A." -Color Red
        }
    }
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
    # Position cursor below main menu
    if ($Global:PromptEndY -gt 0) {
        try {
            $pos = $host.UI.RawUI.CursorPosition
            $pos.Y = $Global:PromptEndY
            $pos.X = 0
            $host.UI.RawUI.CursorPosition = $pos
        } catch {
            Write-Host ""  # Fallback
        }
    }

    Write-Host ""
    Write-ColorText "Select model:" -Color Cyan
    Write-Host ""
    Write-Host "1. Opus (most capable)"
    Write-Host "2. Sonnet (balanced) - Recommended"
    Write-Host "3. Haiku (fast)"
    Write-Host ""

    while ($true) {
        Write-ColorText "Enter choice [1-3], [A]bort: " -Color Yellow -NoNewline
        $choice = Read-Host

        switch ($choice) {
            '1' { return 'opus' }
            '2' { return 'sonnet' }
            '3' { return 'haiku' }
            {$_ -eq 'A' -or $_ -eq 'a'} { return 'abort' }
            default {
                Write-ColorText "Invalid choice. Please enter 1, 2, 3, or A." -Color Red
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
    # Position cursor below main menu
    if ($Global:PromptEndY -gt 0) {
        try {
            $pos = $host.UI.RawUI.CursorPosition
            $pos.Y = $Global:PromptEndY
            $pos.X = 0
            $host.UI.RawUI.CursorPosition = $pos
        } catch {
            Write-Host ""  # Fallback
        }
    }

    Write-Host ""
    Write-ColorText "Do you want a trusted session with no permission limits?" -Color Cyan
    Write-Host "  Y - Yes, bypass all permissions (trusted workspace)"
    Write-Host "  N - No, use default permission settings"
    Write-Host "  A - Abort"
    Write-Host ""

    while ($true) {
        Write-ColorText "Enter choice [Y/N/A]: " -Color Yellow -NoNewline
        $choice = Read-Host

        switch ($choice) {
            {$_ -eq 'Y' -or $_ -eq 'y'} { return 'yes' }
            {$_ -eq 'N' -or $_ -eq 'n'} { return 'no' }
            {$_ -eq 'A' -or $_ -eq 'a'} { return 'abort' }
            default {
                Write-ColorText "Invalid choice. Please enter Y, N, or A." -Color Red
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

    # Position cursor below main menu
    if ($Global:PromptEndY -gt 0) {
        try {
            $pos = $host.UI.RawUI.CursorPosition
            $pos.Y = $Global:PromptEndY
            $pos.X = 0
            $host.UI.RawUI.CursorPosition = $pos
        } catch {
            # Fallback - just add blank lines
            Write-Host ""
        }
    }

    Write-Host ""
    Write-ColorText "========================================" -Color Cyan
    Write-ColorText "  YOU ARE IN QUIET CLAUDE MODE" -Color Cyan
    Write-ColorText "========================================" -Color Cyan
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
    Write-ColorText "Are you sure you want to enable quiet mode (bypass permissions)? [Y/N]: " -Color Yellow -NoNewline
    $confirm = Read-Host

    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Host ""
        Write-ColorText "Operation cancelled." -Color Cyan
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

    Read-Host "Press Enter to continue"
}

function Disable-GlobalBypassPermissions {
    <#
    .SYNOPSIS
        Disables global bypass permissions in settings.json
    #>
    # Position cursor below main menu
    if ($Global:PromptEndY -gt 0) {
        try {
            $pos = $host.UI.RawUI.CursorPosition
            $pos.Y = $Global:PromptEndY
            $pos.X = 0
            $host.UI.RawUI.CursorPosition = $pos
        } catch {
            Write-Host ""  # Fallback
        }
    }

    Write-Host ""
    Write-ColorText "========================================" -Color Cyan
    Write-ColorText "  YOU ARE IN CHATTY CLAUDE MODE" -Color Cyan
    Write-ColorText "========================================" -Color Cyan
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

    # Check if settings file exists
    if (-not (Test-Path $Global:ClaudeSettingsPath)) {
        Write-ColorText "Settings file not found at:" -Color Red
        Write-Host "  $Global:ClaudeSettingsPath"
        Write-Host ""
        Write-ColorText "Nothing to disable." -Color Yellow
        Write-Host ""
        Read-Host "Press Enter to continue"
        return
    }

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
    Write-ColorText "Are you sure you want to enable chatty mode (disable bypass permissions)? [Y/N]: " -Color Yellow -NoNewline
    $confirm = Read-Host

    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Host ""
        Write-ColorText "Operation cancelled." -Color Cyan
        return
    }

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

    Read-Host "Press Enter to continue"
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
        Write-ColorText "Enter choice [Y/N]: " -Color Yellow -NoNewline
        $deleteChoice = Read-Host

        if ($deleteChoice -eq 'Y' -or $deleteChoice -eq 'y') {
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
        $oldName = if ($Session.customTitle) { $Session.customTitle } else { "(unnamed)" }

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

        # 5. Generate or use background image with model info
        if ($resolution.action -eq 'use') {
            # Use existing image
            $bgPath = $resolution.path
            Write-ColorText "Using existing background image." -Color Green
        } else {
            # Generate new image (either 'create' or 'overwrite')
            Write-Host ""
            Write-ColorText "Generating background image..." -Color Cyan

            # Detect git branch
            $gitBranch = Get-GitBranch -Path $Session.projectPath

            $bgPath = New-SessionBackgroundImage -NewName $finalNewName -OldName $oldName -IsFork -GitBranch $gitBranch -Model $model
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
        Add-SessionMapping -SessionId $newSessionId -WTProfileName $actualProfileName -ProjectPath $Session.projectPath -Model $model -ForkedFrom $Session.sessionId

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

        # Find the profile
        $profileToRemove = $settings.profiles.list | Where-Object { $_.name -eq $ProfileName }

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
        $branch = git rev-parse --abbrev-ref HEAD 2>$null

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
    Write-Host "Options:"
    Write-Host "  [O] Overwrite the existing image (affects all profiles using it)"
    Write-Host "  [U] Use the existing image"
    Write-Host "  [N] Create new session with different name"
    Write-Host "  [A] Abort"
    Write-Host ""

    while ($true) {
        Write-ColorText "Choice [O/U/N/A]: " -Color Yellow -NoNewline
        $choice = Read-Host

        switch ($choice.ToUpper()) {
            'O' {
                return @{ action = 'overwrite'; name = $SessionName }
            }
            'U' {
                return @{ action = 'use'; name = $SessionName; path = $outputPath }
            }
            'N' {
                # Find a unique name by appending numbers
                $baseName = $SessionName
                $counter = 1
                $newName = "$baseName$counter"

                while (Test-Path (Join-Path $Global:MenuPath "$newName\background.png")) {
                    $counter++
                    $newName = "$baseName$counter"
                }

                Write-Host ""
                Write-ColorText "Using new session name: $newName" -Color Green
                return @{ action = 'create'; name = $newName }
            }
            'A' {
                return @{ action = 'abort'; name = $SessionName }
            }
            default {
                Write-ColorText "Invalid choice. Please enter O, U, N, or A." -Color Red
            }
        }
    }
}

function New-SessionBackgroundImage {
    <#
    .SYNOPSIS
        Generates a PNG background image for a session
    .PARAMETER IsFork
        If true, displays "forked from:" text. If false, displays origin info without "forked from:"
    .PARAMETER GitBranch
        Optional git branch name to display
    .PARAMETER Model
        Optional model name to display
    #>
    param(
        [string]$NewName,
        [string]$OldName,
        [switch]$IsFork,
        [string]$GitBranch = $null,
        [string]$Model = $null
    )

    try {
        Write-DebugInfo "=== New-SessionBackgroundImage ===" -Color Cyan
        Write-DebugInfo "  NewName: $NewName" -Color Yellow
        Write-DebugInfo "  OldName: $OldName" -Color Yellow
        Write-DebugInfo "  IsFork: $IsFork" -Color Yellow
        Write-DebugInfo "  GitBranch: $GitBranch" -Color Yellow
        Write-DebugInfo "  Model: $Model" -Color Yellow

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

        # Fonts - larger and more visible
        $fontBig = New-Object System.Drawing.Font("Consolas", 48, [System.Drawing.FontStyle]::Bold)
        $fontSmall = New-Object System.Drawing.Font("Consolas", 32, [System.Drawing.FontStyle]::Italic)
        $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)

        # Draw text right of center (position at 60% of width, centered vertically)
        $xPosition = 1920 * 0.6  # 60% of width = 1152
        $yPosition = 400

        # Line 1: Session name
        $graphics.DrawString($NewName, $fontBig, $textBrush, $xPosition, $yPosition)
        $yPosition += 80

        # Line 2: Show "forked from:" only if this is actually a fork
        if ($IsFork) {
            $graphics.DrawString("forked from: $OldName", $fontSmall, $textBrush, $xPosition, $yPosition)
            $yPosition += 60
        } elseif ($OldName) {
            $graphics.DrawString($OldName, $fontSmall, $textBrush, $xPosition, $yPosition)
            $yPosition += 60
        }

        # Line 3: Show git branch if detected
        if ($GitBranch) {
            Write-DebugInfo "  Drawing git branch line: branch: $GitBranch" -Color Green
            $graphics.DrawString("branch: $GitBranch", $fontSmall, $textBrush, $xPosition, $yPosition)
            $yPosition += 60
        } else {
            Write-DebugInfo "  Skipping git branch line (GitBranch is null or empty)" -Color Yellow
        }

        # Line 4: Show model if provided
        if ($Model) {
            Write-DebugInfo "  Drawing model line: model: $Model" -Color Green
            $graphics.DrawString("model: $Model", $fontSmall, $textBrush, $xPosition, $yPosition)
            $yPosition += 60
        } else {
            Write-DebugInfo "  Skipping model line (Model is null or empty)" -Color Yellow
        }

        # Ensure output directory exists
        $outputDir = Join-Path $Global:MenuPath $NewName
        if (-not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        # Save PNG
        $outputPath = Join-Path $outputDir "background.png"
        $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)

        # Cleanup
        $graphics.Dispose()
        $bitmap.Dispose()
        $bgBrush.Dispose()
        $fontBig.Dispose()
        $fontSmall.Dispose()
        $textBrush.Dispose()

        # Save tracking
        if ($IsFork) {
            Save-BackgroundTracking -SessionName $NewName -BackgroundPath $outputPath -TextContent "forked from: $OldName" -ImageType "fork"
        } else {
            Save-BackgroundTracking -SessionName $NewName -BackgroundPath $outputPath -TextContent $OldName -ImageType "new"
        }

        Write-ColorText "Background image created: $outputPath" -Color Green

        return $outputPath

    } catch {
        Write-ColorText "Failed to generate background image: $_" -Color Red
        throw
    }
}

function New-ContinueSessionBackgroundImage {
    <#
    .SYNOPSIS
        Generates a PNG background image for a continued session (not a fork)
    .PARAMETER GitBranch
        Optional git branch name to display
    .PARAMETER Model
        Optional model name to display
    #>
    param(
        [string]$SessionName,
        [string]$GitBranch = $null,
        [string]$Model = $null
    )

    try {
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

        # Fonts - larger and more visible
        $fontBig = New-Object System.Drawing.Font("Consolas", 48, [System.Drawing.FontStyle]::Bold)
        $fontLabel = New-Object System.Drawing.Font("Consolas", 36, [System.Drawing.FontStyle]::Italic)
        $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)

        # Draw text right of center (position at 60% of width, centered vertically)
        $xPosition = 1920 * 0.6  # 60% of width = 1152
        $yPosition = 400
        $fontSmall = New-Object System.Drawing.Font("Consolas", 32, [System.Drawing.FontStyle]::Italic)

        # Line 1: Session label and name
        $graphics.DrawString("Session:", $fontLabel, $textBrush, $xPosition, $yPosition)
        $yPosition += 60
        $graphics.DrawString($SessionName, $fontBig, $textBrush, $xPosition, $yPosition)
        $yPosition += 80

        # Line 3: Show git branch if detected
        if ($GitBranch) {
            $graphics.DrawString("branch: $GitBranch", $fontSmall, $textBrush, $xPosition, $yPosition)
            $yPosition += 60
        }

        # Line 4: Show model if provided
        if ($Model) {
            $graphics.DrawString("model: $Model", $fontSmall, $textBrush, $xPosition, $yPosition)
            $yPosition += 60
        }

        # Ensure output directory exists
        $outputDir = Join-Path $Global:MenuPath $SessionName
        if (-not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        # Save PNG
        $outputPath = Join-Path $outputDir "background.png"
        $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)

        # Cleanup
        $graphics.Dispose()
        $bitmap.Dispose()
        $bgBrush.Dispose()
        $fontBig.Dispose()
        $fontSmall.Dispose()
        $fontLabel.Dispose()
        $textBrush.Dispose()

        # Save tracking
        Save-BackgroundTracking -SessionName $SessionName -BackgroundPath $outputPath -TextContent "Session:`n$SessionName" -ImageType "continue"

        Write-ColorText "Background image created: $outputPath" -Color Green

        return $outputPath

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
                "(deleted or unnamed)"
            }

            # Detect git branch
            $gitBranch = Get-GitBranch -Path $Session.projectPath

            # Get model from session mapping if available
            $sessionEntry = Get-SessionMappingEntry -SessionId $Session.sessionId
            $modelName = if ($sessionEntry -and $sessionEntry.model) { $sessionEntry.model } else { $null }

            $bgPath = New-SessionBackgroundImage -NewName $sessionName -OldName $parentName -IsFork -GitBranch $gitBranch -Model $modelName
        } else {
            # Not a fork - generate simple continue-style background
            Write-ColorText "Generating session background..." -Color Cyan

            # Detect git branch
            $gitBranch = Get-GitBranch -Path $Session.projectPath

            # Get model from session mapping if available
            $sessionEntry = Get-SessionMappingEntry -SessionId $Session.sessionId
            $modelName = if ($sessionEntry -and $sessionEntry.model) { $sessionEntry.model } else { $null }

            $bgPath = New-ContinueSessionBackgroundImage -SessionName $sessionName -GitBranch $gitBranch -Model $modelName
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
        [string]$ForkedFrom = ""
    )

    Initialize-SessionMapping

    try {
        $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json

        # Check if entry already exists
        $existingIndex = -1
        for ($i = 0; $i -lt $mapping.sessions.Count; $i++) {
            if ($mapping.sessions[$i].sessionId -eq $SessionId) {
                $existingIndex = $i
                break
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

            $mapping.sessions = @($mapping.sessions) + $newEntry
        }

        $mapping | ConvertTo-Json -Depth 10 | Set-Content $Global:SessionMappingPath -Encoding UTF8

    } catch {
        Write-ColorText "Failed to add session mapping: $_" -Color Red
        throw
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
        Extracts the model from a session's .jsonl file
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

        # Read file line by line looking for first assistant message with model
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
                        return "opus"
                    } elseif ($fullModel -match 'sonnet') {
                        return "sonnet"
                    } elseif ($fullModel -match 'haiku') {
                        return "haiku"
                    } else {
                        # Return first word of model name
                        if ($fullModel -match 'claude-([^-]+)') {
                            return $matches[1]
                        }
                        return $fullModel
                    }
                }
            }
        } finally {
            $reader.Close()
        }
    } catch {
        Write-ErrorLog "Error getting model from session file: $_"
    }

    return ""
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

function New-CustomTextBackgroundImage {
    <#
    .SYNOPSIS
        Generates a PNG background image with custom text
    #>
    param(
        [string]$SessionName,
        [string]$CustomText
    )

    try {
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

        # Fonts - larger and more visible
        $fontBig = New-Object System.Drawing.Font("Consolas", 48, [System.Drawing.FontStyle]::Bold)
        $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)

        # Draw text right of center (position at 60% of width, centered vertically)
        $xPosition = 1920 * 0.6  # 60% of width = 1152
        $graphics.DrawString($CustomText, $fontBig, $textBrush, $xPosition, 450)

        # Ensure output directory exists
        $outputDir = Join-Path $Global:MenuPath $SessionName
        if (-not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        # Save PNG
        $outputPath = Join-Path $outputDir "background.png"
        $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)

        # Cleanup
        $graphics.Dispose()
        $bitmap.Dispose()
        $bgBrush.Dispose()
        $fontBig.Dispose()
        $textBrush.Dispose()

        # Save tracking
        Save-BackgroundTracking -SessionName $SessionName -BackgroundPath $outputPath -TextContent $CustomText -ImageType "custom-text"

        Write-ColorText "Custom background image created: $outputPath" -Color Green

        return $outputPath

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
        $menuResult = Show-SessionMenu -Sessions $sessions -ShowUnnamed $showUnnamed -OnlyWithProfiles $onlyWithProfiles -Title $menuTitle -SelectedIndex $selectedIndex

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
                                            $bgPath = New-CustomTextBackgroundImage -SessionName $sessionName -CustomText $customText

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
                                Write-ColorText "Are you sure you want to delete profile: $wtProfileName? (Y/N): " -Color Yellow -NoNewline

                                $confirmed = Read-Host

                                if ($confirmed -eq 'Y' -or $confirmed -eq 'y') {
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
                                Write-ColorText "Are you sure you want to remove the background image from: $wtProfileName? (Y/N): " -Color Yellow -NoNewline

                                $confirmed = Read-Host

                                if ($confirmed -eq 'Y' -or $confirmed -eq 'y') {
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
                        Write-ColorText "Would you like to create one? (Y/N): " -Color Cyan -NoNewline
                        $createProfile = Read-Host

                        if ($createProfile -eq 'Y' -or $createProfile -eq 'y') {
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

                                $bgImagePath = New-SessionBackgroundImage -NewName $finalProfileName -OldName "" -GitBranch $gitBranch -Model $modelName
                            }

                            if ($bgImagePath) {
                                # Add profile to Windows Terminal
                                $profile = Add-WTProfile -Name $wtProfileName -BackgroundImage $bgImagePath -StartingDirectory $session.projectPath

                                if ($profile) {
                                    # Update session mapping (use actual profile name in case it was modified)
                                    $actualProfileName = $profile.name
                                    Add-SessionMapping -SessionId $session.sessionId -WTProfileName $actualProfileName -ProjectPath $session.projectPath

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

                # Ask: Fork, Continue, or Delete?
                $action = Get-ForkOrContinue -SessionId $session.sessionId -SessionTitle $sessionTitle -ProjectPath $session.projectPath

                if ($action -eq 'abort') {
                    # User aborted, go back to menu
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
                    Write-ColorText "Are you sure? (Y/N): " -Color Yellow -NoNewline
                    $confirmed = Read-Host

                    if ($confirmed -eq 'Y' -or $confirmed -eq 'y') {
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
