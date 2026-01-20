<#
.SYNOPSIS
    Claude Session Launcher - Interactive menu for managing Claude sessions with Windows Terminal integration

.DESCRIPTION
    Provides an interactive menu for:
    - Discovering all Claude sessions across projects
    - Starting new sessions
    - Continuing existing sessions
    - Forking sessions with custom Windows Terminal profiles and background images

.NOTES
    Author: Claude Code
    Version: 1.0
    Requires: PowerShell 5.1+, Windows Terminal, Claude CLI
#>

# Global error handling
$ErrorActionPreference = "Stop"
$Global:ScriptVersion = "1.0.0"
$Global:MenuPath = "$env:USERPROFILE\.claude-menu"
$Global:ProfileRegistryPath = "$Global:MenuPath\profile-registry.json"
$Global:SessionMappingPath = "$Global:MenuPath\session-mapping.json"
$Global:BackgroundTrackingPath = "$Global:MenuPath\background-tracking.json"
$Global:WTSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$Global:ClaudeProjectsPath = "$env:USERPROFILE\.claude\projects"

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
    .EXAMPLE
        ConvertTo-ClaudeprojectPath "C:\repos" returns "C--repos"
    #>
    param([string]$Path)

    $normalized = $Path.TrimEnd('\')
    return $normalized -replace ':', '-' -replace '\\', '--'
}

function ConvertFrom-ClaudeprojectPath {
    <#
    .SYNOPSIS
        Converts Claude's encoded project path back to Windows path format
    .EXAMPLE
        ConvertFrom-ClaudeprojectPath "C--repos" returns "C:\repos"
    #>
    param([string]$EncodedPath)

    # Replace first dash with colon, then all double-dashes with backslashes
    if ($EncodedPath -match '^([A-Za-z])-(.+)$') {
        $drive = $Matches[1]
        $rest = $Matches[2] -replace '--', '\'
        return "${drive}:\$rest"
    }
    return $EncodedPath
}

function Test-ClaudeCLI {
    <#
    .SYNOPSIS
        Checks if Claude CLI is available in PATH
    #>
    $claudePath = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claudePath) {
        $localPath = "$env:USERPROFILE\.local\bin\claude.exe"
        if (Test-Path $localPath) {
            return $true
        }
        return $false
    }
    return $true
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

    if (-not (Test-Path $projectsRoot)) {
        Write-ColorText "No Claude projects directory found at: $projectsRoot" -Color Yellow
        return @()
    }

    $allSessions = @()
    $sessionIdsSeen = @{}

    # First, get all sessions from Claude's index files
    Get-ChildItem $projectsRoot -Directory | ForEach-Object {
        $projectDir = $_.FullName
        $indexPath = Join-Path $projectDir "sessions-index.json"

        if (Test-Path $indexPath) {
            try {
                $indexContent = Get-Content $indexPath -Raw | ConvertFrom-Json

                foreach ($entry in $indexContent.entries) {
                    # Sessions already have projectPath in the JSON
                    $allSessions += $entry
                    $sessionIdsSeen[$entry.sessionId] = $true
                }
            } catch {
                Write-ColorText "Warning: Failed to parse $indexPath - $_" -Color Yellow
            }
        }
    }

    # Now, check session-mapping.json for sessions we've created that Claude hasn't indexed yet
    if (Test-Path $Global:SessionMappingPath) {
        try {
            $mapping = Get-Content $Global:SessionMappingPath -Raw | ConvertFrom-Json

            foreach ($mappedSession in $mapping.sessions) {
                # Skip if we already have this session from Claude's index
                if ($sessionIdsSeen.ContainsKey($mappedSession.sessionId)) {
                    continue
                }

                # Check if the session file exists
                $encodedPath = $mappedSession.projectPath.TrimEnd('\') -replace ':', '' -replace '\\', '--'
                $sessionFile = Join-Path $projectsRoot "$encodedPath\$($mappedSession.sessionId).jsonl"

                if (Test-Path $sessionFile) {
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
                }
            }
        } catch {
            Write-ColorText "Warning: Failed to read session mapping - $_" -Color Yellow
        }
    }

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
        # Silently ignore errors
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
        # Silently ignore errors
    }

    return $null
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
        $encodedPath = $ProjectPath.TrimEnd('\') -replace ':', '' -replace '\\', '--'
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
                # Silently ignore errors
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
        # Silently ignore errors
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
        [string]$Title = ""
    )

    Clear-Host
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

    Write-Host "Claude Code Session Forker, S. Rives, 2026" -ForegroundColor Cyan
    Write-Host "(Note: Newly forked sessions shown in [brackets] until Claude CLI indexes them)" -ForegroundColor DarkGray
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

        $rows += @{
            Num = $displayNum
            Title = $title
            Path = $session.projectPath
            Messages = $session.messageCount
            Created = $created.ToString('MM/dd HH:mm')
            Modified = $modified.ToString('MM/dd HH:mm')
            Profile = $wtProfile
            ColorScheme = $colorScheme
            Model = $model
            ForkTree = $forkTree
            Active = $activeMarker
            Session = $session
            OriginalIndex = $i
        }
        $displayNum++
    }

    # Display header - different format for profile mode
    if ($OnlyWithProfiles) {
        Write-Host ("{0,-3} {1,-30} {2,-20} {3,-8} {4,-12} {5,-12} {6,-20} {7,-20}" -f "#", "Session", "Path", "Messages", "Created", "Modified", "WT Profile", "Color Scheme") -ForegroundColor Cyan
        Write-Host ("{0,-3} {1,-30} {2,-20} {3,-8} {4,-12} {5,-12} {6,-20} {7,-20}" -f "-", "-------", "----", "--------", "-------", "--------", "----------", "------------") -ForegroundColor Cyan
    } else {
        Write-Host ("{0,-3} {1,-6} {2,-8} {3,-30} {4,-20} {5,-8} {6,-12} {7,-12} {8,-25} {9,-25}" -f "#", "Active", "Model", "Session", "Path", "Messages", "Created", "Modified", "Win Terminal", "Forked From") -ForegroundColor Cyan
        Write-Host ("{0,-3} {1,-6} {2,-8} {3,-30} {4,-20} {5,-8} {6,-12} {7,-12} {8,-25} {9,-25}" -f "-", "------", "-----", "-------", "----", "--------", "-------", "--------", "------------", "-----------") -ForegroundColor Cyan
    }

    # Display rows
    foreach ($row in $rows) {
        if ($OnlyWithProfiles) {
            Write-Host ("{0,-3} {1,-30} {2,-20} {3,-8} {4,-12} {5,-12} {6,-20} {7,-20}" -f $row.Num, $row.Title, $row.Path, $row.Messages, $row.Created, $row.Modified, $row.Profile, $row.ColorScheme) -ForegroundColor Green
        } else {
            Write-Host ("{0,-3} {1,-6} {2,-8} {3,-30} {4,-20} {5,-8} {6,-12} {7,-12} {8,-25} {9,-25}" -f $row.Num, $row.Active, $row.Model, $row.Title, $row.Path, $row.Messages, $row.Created, $row.Modified, $row.Profile, $row.ForkTree) -ForegroundColor Green
        }
    }

    Write-Host ""

    # Return the display rows for selection mapping
    # Use Write-Output to ensure clean return
    Write-Output -NoEnumerate $rows
}

function Get-UserSelection {
    <#
    .SYNOPSIS
        Gets user's menu selection with validation
    #>
    param(
        [int]$MinOption,
        [int]$MaxOption,
        [bool]$ShowUnnamed,
        [bool]$HasWTProfiles = $false,
        [bool]$DeleteMode = $false
    )

    while ($true) {
        # Build the range display
        if ($MinOption -eq $MaxOption) {
            $range = "[$MinOption]"
        } else {
            $range = "[$MinOption..$MaxOption]"
        }

        if ($DeleteMode) {
            Write-ColorText "Select Windows Terminal Profile $range, [R] Refresh, [A] Abort: " -Color Yellow -NoNewline
        } elseif ($ShowUnnamed) {
            $wtOption = if ($HasWTProfiles) { ", [W] Win Terminal Config" } else { "" }
            Write-ColorText "$range fork or join, [N] New Session$wtOption, [H] Hide unnamed sessions, [R] Refresh, [A] Abort: " -Color Yellow -NoNewline
        } else {
            $wtOption = if ($HasWTProfiles) { ", [W] Win Terminal Config" } else { "" }
            Write-ColorText "$range fork or join, [N] New Session$wtOption, [S] Show unnamed sessions, [R] Refresh, [A] Abort: " -Color Yellow -NoNewline
        }

        $input = Read-Host

        # Check for abort
        if ($input -eq 'A' -or $input -eq 'a') {
            if ($DeleteMode) {
                return @{ Type = 'ExitDeleteMode' }
            } else {
                return @{ Type = 'Quit' }
            }
        }

        # Check for old quit command - still support Q for backwards compatibility
        if ($input -eq 'Q' -or $input -eq 'q') {
            if ($DeleteMode) {
                # In delete mode, only A works for abort, Q is invalid
                Write-ColorText "Invalid selection. Use [A] to abort." -Color Red
                continue
            } else {
                return @{ Type = 'Quit' }
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

        # Check for refresh
        if ($input -eq 'R' -or $input -eq 'r') {
            return @{ Type = 'Refresh' }
        }

        # Check for delete mode
        if (($input -eq 'W' -or $input -eq 'w') -and $HasWTProfiles -and -not $DeleteMode) {
            return @{ Type = 'EnterDeleteMode' }
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

#region Session Launch

function Start-NewSession {
    <#
    .SYNOPSIS
        Starts a new Claude session in the current directory
    #>
    Write-Host ""
    Write-ColorText "Starting new Claude session..." -Color Cyan
    Write-Host ""
    Write-Host "Current directory: $PWD"
    Write-Host ""
    Write-ColorText "Would you like to create a Windows Terminal profile for this session?" -Color Cyan
    Write-Host "  1. Yes - Create custom profile with background image"
    Write-Host "  2. No - Launch in current terminal"
    Write-Host ""

    while ($true) {
        Write-ColorText "Enter choice [1-2], [A] Abort: " -Color Yellow -NoNewline
        $choice = Read-Host

        if ($choice -eq '1') {
            # Create session with Windows Terminal profile
            try {
                # 1. Get session name
                $sessionName = Get-SessionName

                # 2. Generate session ID
                $sessionId = [Guid]::NewGuid().ToString()

                # 3. Generate background image
                Write-Host ""
                Write-ColorText "Generating background image..." -Color Cyan
                $bgPath = New-SessionBackgroundImage -NewName $sessionName -OldName "new session"

                # 4. Create Windows Terminal profile
                Write-ColorText "Creating Windows Terminal profile..." -Color Cyan
                $wtProfileName = "Claude-$sessionName"
                $profile = Add-WTProfile -Name $wtProfileName -StartingDirectory $PWD.Path -BackgroundImage $bgPath

                # 5. Select model
                $model = Get-ModelChoice

                # Check if user aborted
                if ($model -eq 'abort') {
                    Write-Host ""
                    Write-ColorText "New session aborted. Cleaning up..." -Color Yellow
                    Remove-WTProfile -ProfileName $wtProfileName
                    $imageDir = Join-Path $Global:MenuPath $sessionName
                    if (Test-Path $imageDir) {
                        Remove-Item $imageDir -Recurse -Force
                    }
                    return
                }

                # 6. Store in session mapping
                Write-ColorText "Registering session..." -Color Cyan
                Add-SessionMapping -SessionId $sessionId -WTProfileName $wtProfileName -ProjectPath $PWD.Path -Model $model

                # 7. Launch Windows Terminal with the new profile
                Write-Host ""
                Write-ColorText "Launching new session in Windows Terminal..." -Color Green
                Write-Host ""

                $profileGuid = $profile.guid

                # Launch Windows Terminal with the new profile and session ID
                & wt.exe -p "$profileGuid" -d "$($PWD.Path)" -- claude --session-id $sessionId --model $model

                Write-ColorText "New session launched successfully!" -Color Green
                Write-Host ""
                Write-Host "Profile: $wtProfileName"
                Write-Host "Session ID: $sessionId"
                Write-Host "Model: $model"
                Write-Host ""
                Write-ColorText "Tip: Use /rename in Claude to give this session a custom title" -Color Yellow
                Write-Host ""

                exit 0

            } catch {
                Write-ColorText "Failed to create new session: $_" -Color Red
                throw
            }

        } elseif ($choice -eq '2') {
            # Launch in current terminal (simple mode)
            Write-Host ""
            Write-ColorText "Launching Claude in current terminal..." -Color Green
            Write-Host ""
            Start-Process -FilePath "claude" -NoNewWindow -Wait
            exit 0

        } elseif ($choice -eq 'A' -or $choice -eq 'a') {
            # User aborted
            return

        } else {
            Write-ColorText "Invalid choice. Please enter 1, 2, or A." -Color Red
        }
    }
}

function Start-ContinueSession {
    <#
    .SYNOPSIS
        Continues an existing Claude session
    #>
    param([object]$Session)

    Write-Host ""
    $sessionTitle = if ($Session.customTitle) { $Session.customTitle } else { '(unnamed)' }

    # Only create Windows Terminal profiles for named sessions
    if ($Session.customTitle -and $Session.customTitle -ne "") {
        Write-ColorText "Continuing session: $sessionTitle" -Color Green
        Write-Host ""

        # Check if Windows Terminal profile already exists
        $wtProfileName = "Claude-$sessionTitle"
        $existingProfile = $null

        try {
            if (Test-Path $Global:WTSettingsPath) {
                $settingsJson = Get-Content $Global:WTSettingsPath -Raw
                $settings = $settingsJson | ConvertFrom-Json
                $existingProfile = $settings.profiles.list | Where-Object { $_.name -eq $wtProfileName }
            }
        } catch {
            # Ignore errors, will create new profile if needed
        }

        # Generate/verify background image exists
        $bgPath = Join-Path $Global:MenuPath "$sessionTitle\background.png"
        if (-not (Test-Path $bgPath)) {
            Write-ColorText "Creating background image..." -Color Cyan
            $bgPath = New-ContinueSessionBackgroundImage -SessionName $sessionTitle
        }

        if ($existingProfile) {
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
            & wt.exe -p "$profileGuid" -d "$($Session.projectPath)" -- claude --resume $Session.sessionId

        } else {
            # Profile doesn't exist - create it
            Write-ColorText "Creating Windows Terminal profile..." -Color Cyan

            try {
                $profile = Add-WTProfile -Name $wtProfileName -StartingDirectory $Session.projectPath -BackgroundImage $bgPath

                # Add to session mapping
                Add-SessionMapping -SessionId $Session.sessionId -WTProfileName $wtProfileName -ProjectPath $Session.projectPath

                Write-ColorText "Windows Terminal profile created: $wtProfileName" -Color Green
                Write-Host ""

                # Launch in new Windows Terminal profile
                $profileGuid = $profile.guid
                & wt.exe -p "$profileGuid" -d "$($Session.projectPath)" -- claude --resume $Session.sessionId

            } catch {
                Write-ColorText "Failed to create Windows Terminal profile: $_" -Color Red
                Write-ColorText "Launching in current terminal instead..." -Color Yellow
                Write-Host ""

                # Fallback to current terminal
                $args = "--resume", $Session.sessionId
                Start-Process -FilePath "claude" -ArgumentList $args -NoNewWindow -Wait
            }
        }
    } else {
        # Unnamed session - launch in current terminal
        Write-ColorText "Continuing session: $sessionTitle" -Color Green
        Write-Host ""

        $args = "--resume", $Session.sessionId
        Start-Process -FilePath "claude" -ArgumentList $args -NoNewWindow -Wait
    }
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
    Write-Host "1. Regenerate background image"
    Write-Host "2. Delete Windows Terminal profile"
    Write-Host "3. Remove background image from profile"
    Write-Host ""

    while ($true) {
        Write-ColorText "Enter choice [1-3], [A] Abort: " -Color Yellow -NoNewline
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

    Write-Host ""
    Write-ColorText "Regenerate Background Image Options" -Color Cyan
    Write-Host ""
    Write-Host "1. Regenerate/Refresh from session: $SessionName"
    Write-Host "2. Use custom image file"
    Write-Host "3. Generate from custom text"
    Write-Host ""

    while ($true) {
        Write-ColorText "Enter choice [1-3], [A] Abort: " -Color Yellow -NoNewline
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
        [string]$SessionTitle = ""
    )

    Write-Host ""
    Write-ColorText "Session options" -Color Cyan
    if ($SessionTitle) {
        Write-ColorText "Session: $SessionTitle" -Color DarkGray
    }
    Write-ColorText "Session ID: $SessionId" -Color DarkGray
    Write-Host ""
    Write-Host "1. Continue - Resume in same terminal"
    Write-Host "2. Fork - Create new branch with custom Windows Terminal profile"
    Write-Host "   (Will fork session: $SessionId)"
    Write-Host "3. Delete session"
    Write-Host ""

    while ($true) {
        Write-ColorText "Enter choice [1-3], [A] Abort: " -Color Yellow -NoNewline
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

function Get-ModelChoice {
    <#
    .SYNOPSIS
        Prompts user to select a Claude model
    #>
    Write-Host ""
    Write-ColorText "Select model:" -Color Cyan
    Write-Host ""
    Write-Host "1. Opus (most capable)"
    Write-Host "2. Sonnet (balanced) - Recommended"
    Write-Host "3. Haiku (fast)"
    Write-Host ""

    while ($true) {
        Write-ColorText "Enter choice [1-3], [A] Abort: " -Color Yellow -NoNewline
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

function Start-ForkSession {
    <#
    .SYNOPSIS
        Handles the complete fork workflow
    #>
    param([object]$Session)

    try {
        # 1. Get old session name for display
        $oldName = if ($Session.customTitle) { $Session.customTitle } else { "(unnamed)" }

        # 2. Get new session name
        $newName = Get-SessionName -OldSessionName $oldName

        # 3. Generate background image
        Write-Host ""
        Write-ColorText "Generating background image..." -Color Cyan
        $bgPath = New-SessionBackgroundImage -NewName $newName -OldName $oldName

        # 4. Create Windows Terminal profile
        Write-ColorText "Creating Windows Terminal profile..." -Color Cyan
        $profile = Add-WTProfile -Name "Claude-$newName" -StartingDirectory $Session.projectPath -BackgroundImage $bgPath

        # 5. Select model
        $model = Get-ModelChoice

        # Check if user aborted
        if ($model -eq 'abort') {
            Write-Host ""
            Write-ColorText "Fork aborted. Cleaning up..." -Color Yellow
            # Remove the Windows Terminal profile we just created
            Remove-WTProfile -ProfileName "Claude-$newName"
            # Remove the background image
            $imageDir = Join-Path $Global:MenuPath $newName
            if (Test-Path $imageDir) {
                Remove-Item $imageDir -Recurse -Force
            }
            return
        }

        # 6. Generate new session ID for the forked session
        $newSessionId = [Guid]::NewGuid().ToString()

        # 7. Store in profile registry
        Write-ColorText "Registering profile..." -Color Cyan
        Add-ProfileRegistry -SessionName $newName -ProfileGuid $profile.guid -OriginalSessionId $Session.sessionId -projectPath $Session.projectPath -BackgroundImage $bgPath -Model $model

        # 8. Store in session mapping
        Add-SessionMapping -SessionId $newSessionId -WTProfileName "Claude-$newName" -ProjectPath $Session.projectPath -Model $model -ForkedFrom $Session.sessionId

        # 9. Launch Windows Terminal with new profile
        Write-Host ""
        Write-ColorText "Launching forked session in new Windows Terminal window..." -Color Green
        Write-Host ""

        # Build the command for Windows Terminal
        $profileGuid = $profile.guid
        $projectPath = $Session.projectPath
        $oldSessionId = $Session.sessionId

        # Launch Windows Terminal with the new profile
        # Using both --fork-session and --session-id to control the new session's ID
        & wt.exe -p "$profileGuid" -d "$projectPath" -- claude --resume $oldSessionId --fork-session --session-id $newSessionId --model $model

        Write-ColorText "Forked session launched successfully!" -Color Green
        Write-Host ""
        Write-Host "New Session: Claude-$newName"
        Write-Host "Forked From: $oldName (Session ID: $oldSessionId)"
        Write-Host "New Session ID: $newSessionId"
        Write-Host "Model: $model"
        Write-Host "Background: $bgPath"
        Write-Host ""
        Write-ColorText "Troubleshooting: If background image doesn't appear..." -Color Yellow
        Write-Host "  1. Check Windows Terminal Settings > Profiles > Claude-$newName"
        Write-Host "  2. Verify 'Background image path' is set correctly"
        Write-Host "  3. Adjust 'Background image opacity' slider (default: 30%)"
        Write-Host "  4. Ensure 'useAcrylic' is disabled (set by this script)"
        Write-Host "  5. Try changing 'Text antialiasing' to 'grayscale' (set by this script)"
        Write-Host ""

        exit 0

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

function Test-WTSettingsValid {
    <#
    .SYNOPSIS
        Validates Windows Terminal settings JSON
    #>
    try {
        $content = Get-Content $Global:WTSettingsPath -Raw
        $null = $content | ConvertFrom-Json
        return $true
    } catch {
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

        # Generate unique GUID
        $newGuid = "{$([Guid]::NewGuid().ToString())}"

        # Create new profile object with all properties
        if ($BackgroundImage) {
            # Ensure path uses forward slashes for JSON compatibility
            $imagePath = $BackgroundImage -replace '\\', '/'

            $newProfile = [PSCustomObject]@{
                guid = $newGuid
                name = $Name
                commandline = "%SystemRoot%\System32\cmd.exe"
                startingDirectory = $StartingDirectory
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
                name = $Name
                commandline = "%SystemRoot%\System32\cmd.exe"
                startingDirectory = $StartingDirectory
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

        Write-ColorText "Created Windows Terminal profile: $Name" -Color Green

        return $newProfile

    } catch {
        Write-ColorText "Failed to add profile, restoring from backup..." -Color Red
        Copy-Item $backupPath $Global:WTSettingsPath -Force
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
        return $true

    } catch {
        Write-ColorText "Failed to remove profile, restoring from backup..." -Color Red
        Copy-Item $backupPath $Global:WTSettingsPath -Force
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

#region Image Generation

function New-SessionBackgroundImage {
    <#
    .SYNOPSIS
        Generates a PNG background image for a forked session
    #>
    param(
        [string]$NewName,
        [string]$OldName
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
        $fontSmall = New-Object System.Drawing.Font("Consolas", 32, [System.Drawing.FontStyle]::Italic)
        $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)

        # Draw text right of center (position at 60% of width, centered vertically)
        $xPosition = 1920 * 0.6  # 60% of width = 1152
        $graphics.DrawString($NewName, $fontBig, $textBrush, $xPosition, 400)
        $graphics.DrawString("forked from: $OldName", $fontSmall, $textBrush, $xPosition, 480)

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
        Save-BackgroundTracking -SessionName $NewName -BackgroundPath $outputPath -TextContent "forked from: $OldName" -ImageType "fork"

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
    #>
    param([string]$SessionName)

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
        $graphics.DrawString("Session: $SessionName", $fontBig, $textBrush, $xPosition, 450)

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
        Save-BackgroundTracking -SessionName $SessionName -BackgroundPath $outputPath -TextContent "Session: $SessionName" -ImageType "continue"

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

            $bgPath = New-SessionBackgroundImage -NewName $sessionName -OldName $parentName
        } else {
            # Not a fork - generate simple continue-style background
            Write-ColorText "Generating session background..." -Color Cyan
            $bgPath = New-ContinueSessionBackgroundImage -SessionName $sessionName
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
        $existingEntry = $mapping.sessions | Where-Object { $_.sessionId -eq $SessionId }

        if ($existingEntry) {
            # Update existing entry
            $existingEntry.wtProfileName = $WTProfileName
            $existingEntry.projectPath = $ProjectPath
            $existingEntry.model = $Model
            if ($ForkedFrom) {
                $existingEntry.forkedFrom = $ForkedFrom
            }
            $existingEntry.updated = (Get-Date).ToString('o')
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
        # Silently ignore errors
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
        $encodedPath = $ProjectPath.TrimEnd('\') -replace ':', '' -replace '\\', '--'
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
        # Silently ignore errors
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
        $encodedPath = $projectPath.TrimEnd('\') -replace ':', '' -replace '\\', '--'
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
                    # Ignore errors
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
                            # Ignore errors
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
        $existingEntry = $tracking.backgrounds | Where-Object { $_.sessionName -eq $SessionName }

        if ($existingEntry) {
            # Update existing entry
            $existingEntry.backgroundPath = $BackgroundPath
            $existingEntry.textContent = $TextContent
            $existingEntry.imageType = $ImageType
            $existingEntry.updated = (Get-Date).ToString('o')
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

    # Menu loop with show/hide toggle and delete mode
    $showUnnamed = $false
    $deleteMode = $false

    while ($true) {
        # Reload sessions from disk each time through the loop
        # This ensures we see any new sessions, renamed sessions, etc.
        $sessions = Get-AllClaudeSessions

        # Show menu and get display rows
        $menuTitle = if ($deleteMode) { "WIN TERMINAL CONFIG" } else { "MAIN MENU" }
        $displayRows = Show-SessionMenu -Sessions $sessions -ShowUnnamed $showUnnamed -OnlyWithProfiles $deleteMode -Title $menuTitle

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

        # Get user selection
        $result = Get-UserSelection -MinOption $minOption -MaxOption $maxOption -ShowUnnamed $showUnnamed -HasWTProfiles $hasWTProfiles -DeleteMode $deleteMode

        # Handle result
        switch ($result.Type) {
            'Quit' {
                Write-Host ""
                Write-ColorText "Goodbye!" -Color Cyan
                Write-Host ""
                exit 0
            }

            'NewSession' {
                # New session
                Start-NewSession
                exit 0
            }

            'ShowUnnamed' {
                $showUnnamed = $true
                continue
            }

            'HideUnnamed' {
                $showUnnamed = $false
                continue
            }

            'Refresh' {
                # Refresh menu - just continue the loop to reload session data
                continue
            }

            'EnterDeleteMode' {
                $deleteMode = $true
                continue
            }

            'ExitDeleteMode' {
                $deleteMode = $false
                continue
            }

            'Select' {
                $selectedNum = $result.Value

                # Find the corresponding row
                $selectedRow = $displayRows | Where-Object { $_.Num -eq $selectedNum }

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
                $action = Get-ForkOrContinue -SessionId $session.sessionId -SessionTitle $sessionTitle

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
                    exit 0
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
