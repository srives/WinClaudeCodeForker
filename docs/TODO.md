# TODO: Integrate GitHub Copilot CLI and OpenCode into Fork

**Created:** 2026-02-25
**Priority:** Copilot CLI first (#1), then OpenCode (#2)
**Prerequisite for both:** Install each tool, create a session, and verify file structures before coding.

---

## Phase 1: GitHub Copilot CLI Integration

### 1.1 Install and Verify File Structures

- [ ] Install GitHub Copilot CLI (`gh extension install github/copilot-cli` or standalone)
- [ ] Create at least 2 sessions in different directories
- [ ] Examine `~/.copilot/session-state/` — document directory layout
- [ ] For each session subdirectory, catalog the files: `events.jsonl`, `workspace.yaml`, `plan.md`, `checkpoints/`
- [ ] Parse `workspace.yaml` — document schema (project path, model, timestamps, session title)
- [ ] Parse `events.jsonl` — find token usage, model name, message count, cost data
- [ ] Test `copilot --resume <session-id>` — does it accept a direct UUID from the directory name?
- [ ] Test `copilot --continue` — does it resume the last session?
- [ ] Check if `copilot` is `.exe`, `.cmd`, `.ps1`, or something else on Windows
- [ ] Document: Does Copilot CLI work on Windows natively or require WSL?

**Decision gate:** If `copilot --resume <session-id>` does NOT accept a direct ID, we cannot dispatch from Fork. Stop and reassess.

### 1.2 Session Discovery (`Get-AllCopilotSessions`)

- [ ] Scan `~/.copilot/session-state/` — each subdirectory name is a session ID
- [ ] For each session, read `workspace.yaml` for metadata (project path, model, title)
- [ ] For each session, read `events.jsonl` for token usage and message count (read last N lines for model, or scan for usage entries)
- [ ] Map to session object: `sessionId`, `customTitle=""`, `firstPrompt`, `projectPath`, `created`, `modified`, `messageCount`, `model`, `source="copilot"`, `copilotTokensUsed`
- [ ] Handle missing/corrupt files gracefully (empty session dirs, partial writes)
- [ ] Add debug logging throughout (same pattern as Codex)

### 1.3 Display Integration

- [ ] Add `source = "copilot"` tagging
- [ ] Src column: `P` for Copilot — pick a color (suggest Green since Blue=Claude, Magenta=Codex)
- [ ] Title bar: update to include Copilot — `Codex (X), Copilot (P), and Claude Code (C) Session Manager...`
- [ ] Session stats line: add third color-coded segment for Copilot sessions + cost
- [ ] WT profiles use `Copilot-` prefix
- [ ] Copilot auto-titles shown in [brackets] like Codex (if Copilot generates titles)

### 1.4 Launch Dispatch

- [ ] `Start-ContinueSession`: if source is copilot, dispatch `copilot --resume <id>` with WT profile + background watermark
- [ ] `Start-ForkSession`: Copilot has no native fork — fork by creating a new session? Or skip fork for Copilot sessions and show a message?
- [ ] `Start-NewSession`: add Copilot to the CLI choice prompt (`Claude | codeX | coPilot | Abort`)
- [ ] Handle `.ps1` / `.cmd` / `.exe` shim detection (same `Start-WTClaude` logic)
- [ ] Determine Copilot's quiet/auto-approve CLI flag (if any) and set `QuietFlag` in registry
- [ ] Create `Test-CopilotQuietMode` function to check Copilot's config for auto-approve state

### 1.5 Cost and Model

- [ ] Determine Copilot pricing model: per-token, per-request (premium requests), or subscription-only
- [ ] If per-request: show `~N reqs` instead of `~$X.XX` in Cost column
- [ ] If per-token: calculate cost same as Claude/Codex
- [ ] Read actual model from `events.jsonl` (not a generic provider name)
- [ ] Display model as-is (e.g. `claude-sonnet-4.5`, `gpt-4o`) — Copilot supports multiple models

### 1.6 Linux Port

- [ ] Add `get_all_copilot_sessions()` to `linux/lib/session.py` — scan `~/.copilot/session-state/`, parse YAML+JSONL
- [ ] Add `copilot` to `check_dependencies()` in `claude-menu.py`
- [ ] Update `handle_continue()`, `handle_fork()`, `handle_new_session()` dispatch
- [ ] Add `P` marker and color to `menu.py`
- [ ] Note: Python has `yaml` module in some installs but not all — may need `pip install pyyaml` or parse YAML manually for simple key:value files

### 1.7 Testing

- [ ] Test with 0 Copilot sessions (graceful skip)
- [ ] Test with Copilot not installed (no errors)
- [ ] Test continue — session launches in WT with watermark
- [ ] Test new session — Copilot chosen, launches correctly
- [ ] Test with stale/dead Copilot sessions (missing events.jsonl)

---

## Phase 2: OpenCode Integration

### 2.1 Install and Verify File Structures

- [ ] Install OpenCode (`go install` or download binary)
- [ ] Create at least 2 sessions in different directories
- [ ] Examine `~/.local/share/opencode/opencode.db` — open with SQLite browser or `sqlite3` CLI
- [ ] Document the `sessions` table schema (columns, types, sample data)
- [ ] Document the `messages` table schema if it exists (for token/cost data)
- [ ] Test `opencode --session <id>` or equivalent resume-by-ID command
- [ ] Check if OpenCode requires a running server daemon or can launch standalone
- [ ] Check if OpenCode works on Windows natively or is Linux/macOS only
- [ ] Document: is it a single binary? `.exe` on Windows?

**Decision gate:** If OpenCode requires a running server daemon that we can't launch from Fork, the integration is impractical. Stop and reassess.

### 2.2 Session Discovery (`Get-AllOpenCodeSessions`)

- [ ] Open `opencode.db` read-only (same SQLite pattern as Codex)
- [ ] Query sessions table for: id, project_path, created_at, updated_at, title, model, tokens_used
- [ ] Windows: use Python subprocess for SQLite (same as Codex). Reuse `Test-CodexPythonAvailable` (rename to `Test-PythonAvailable`)
- [ ] Linux: use built-in `sqlite3` module
- [ ] Map to session object with `source="opencode"`
- [ ] Handle: database doesn't exist, table schema changed, empty database
- [ ] Add debug logging

### 2.3 Display Integration

- [ ] Src column: `O` for OpenCode — pick a color (suggest Cyan or White)
- [ ] Title bar: update to include OpenCode
- [ ] Session stats line: add fourth color-coded segment
- [ ] WT profiles use `OpenCode-` prefix

### 2.4 Launch Dispatch

- [ ] Continue: dispatch to `opencode --session <id>` (verify exact flag)
- [ ] Fork: OpenCode has no native fork — same approach as Copilot
- [ ] New session: add to CLI choice prompt
- [ ] Handle binary path detection
- [ ] Determine OpenCode's auto-approve CLI flag (if any) and set `QuietFlag` in registry
- [ ] Create `Test-OpenCodeQuietMode` function

### 2.5 Cost and Model

- [ ] Read cost from SQLite (OpenCode uses LiteLLM pricing, may store calculated cost)
- [ ] Read model from sessions table or messages table
- [ ] Display model as-is

### 2.6 Linux Port

- [ ] Add `get_all_opencode_sessions()` to `session.py` — identical SQLite pattern to Codex
- [ ] Update dispatch handlers
- [ ] Add `O` marker to menu

### 2.7 Testing

- [ ] Same test matrix as Copilot (0 sessions, not installed, continue, new, dead sessions)

---

## Phase 3: Platform Registry — Shared Infrastructure (DONE ✓)

The Platform Registry (`$Global:PlatformRegistry`) is implemented and is the single source of truth
for all platform-specific values. Adding a new platform requires only: (1) a new entry in the registry,
(2) a session discovery function, and (3) a quiet-mode check function.

### 3.1 Platform Registry — Current State (Windows)

**Status: IMPLEMENTED** in `Claude-Menu.ps1` lines 76-102.

```powershell
$Global:PlatformRegistry = @{
    claude = @{
        Key            = 'C'                  # Src column letter
        DisplayName    = 'Claude Code'        # Full display name
        Color          = 'Blue'               # PowerShell console color
        ColorRGB       = @(30, 144, 255)      # RGB for System.Drawing
        WTPrefix       = 'Claude-'            # Windows Terminal profile prefix
        CLIName        = 'claude'             # Executable name for Get-Command
        ResumeCmd      = '--resume {0}'       # Resume args template ({0} = session ID)
        ForkCmd        = '--resume {0} --fork-session'
        CLIPathFunc    = 'Get-ClaudeCLIPath'  # Function name to resolve CLI path
        QuietFlag      = $null                # No CLI flag (config-based via bypassPermissions)
        QuietCheckFunc = 'Test-ClaudeQuietMode'
    }
    codex = @{
        Key            = 'X'
        DisplayName    = 'Codex'
        Color          = 'Magenta'
        ColorRGB       = @(255, 0, 255)
        WTPrefix       = 'Codex-'
        CLIName        = 'codex'
        ResumeCmd      = 'resume {0}'
        ForkCmd        = 'fork {0}'
        CLIPathFunc    = 'Get-CodexCLIPath'
        QuietFlag      = '--danger'           # CLI flag for danger mode (disables all prompts)
        QuietCheckFunc = 'Test-CodexQuietMode'
    }
}
```

**Helper functions (implemented):**
- `Get-PlatformProperty -Source <source> -Property <name>` — generic single-field lookup
- `Get-PlatformEntry -Source <source>` — returns full platform hashtable
- `Get-PlatformByKey -Key <letter>` — reverse lookup by Src column letter
- `Get-InstalledPlatforms` — returns registry entries whose CLI is in PATH
- `Get-AllWTProfilePrefixes` — array of all WT prefixes
- `Get-SessionNameFromWTProfile` — strips any known platform prefix
- `Get-PlatformQuietArgs -Source <source>` — returns quiet-mode CLI flag if platform is in quiet mode

**Validation tests (implemented):**
- Test 159: PlatformRegistry has all required fields (Key, DisplayName, Color, ColorRGB, WTPrefix, CLIName, ResumeCmd, ForkCmd, CLIPathFunc, QuietCheckFunc)
- Tests 160-170: Platform field validation (ColorRGB elements, Key uniqueness, ResumeCmd/ForkCmd placeholders, etc.)
- Tests 251-258: QuietFlag architecture validation

### 3.2 QuietFlag Architecture (DONE ✓)

**What it does:** When a platform is in "Quiet" mode and has a `QuietFlag`, that flag is automatically
appended to the CLI command line at launch time. This happens inside `Start-WTClaude` via the `-Source`
parameter — no per-platform branching needed at call sites.

**How it works:**
1. `Start-WTClaude` receives `-Source 'codex'` (or `'claude'`, etc.)
2. Calls `Get-PlatformQuietArgs -Source $Source`
3. That function looks up `QuietFlag` and `QuietCheckFunc` from the registry
4. If `QuietFlag` is non-null AND `QuietCheckFunc` returns `$true`, the flag is appended to `$Arguments`
5. For Claude: `QuietFlag = $null` → no CLI flag (quiet mode is config-based in `~/.claude/settings.json`)
6. For Codex: `QuietFlag = '--danger'` → appended when `approval_mode = "full-auto"` in `~/.codex/config.toml`

**Key functions:**
- `Test-ClaudeQuietMode` — checks `bypassPermissions` in Claude settings.json
- `Test-CodexQuietMode` — checks `approval_mode` in Codex config.toml
- `Get-PlatformQuietArgs -Source` — orchestrator that calls the check func and returns the flag

**All 21 `Start-WTClaude` call sites pass `-Source`** (enforced by validation test 257).

### 3.3 How to Add a New Platform (e.g., Aider)

Adding a new platform to SessionForge requires these steps:

#### Step 1: Add PlatformRegistry Entry (~line 76 in Claude-Menu.ps1)

```powershell
    aider = @{
        Key            = 'A'                  # Must be unique across all platforms
        DisplayName    = 'Aider'
        Color          = 'Green'              # PowerShell console color for Src column
        ColorRGB       = @(0, 200, 83)        # RGB for background watermark images
        WTPrefix       = 'Aider-'             # WT profile prefix (e.g. "Aider-MySession")
        CLIName        = 'aider'              # Executable name (what you type to launch it)
        ResumeCmd      = '--restore-chat-history {0}'  # TBD — verify actual flag
        ForkCmd        = $null                # $null if platform has no native fork
        CLIPathFunc    = 'Get-AiderCLIPath'   # Function name to resolve CLI executable path
        QuietFlag      = '--yes-always'       # TBD — verify actual flag for auto-approve mode
        QuietCheckFunc = 'Test-AiderQuietMode'
    }
```

#### Step 2: Create CLI Path Function

```powershell
function Get-AiderCLIPath {
    $cmd = Get-Command aider -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}
```

#### Step 3: Create Quiet Mode Check Function

```powershell
function Test-AiderQuietMode {
    # Check aider's config for auto-approve setting
    # Return $true if aider is in quiet/auto mode, $false otherwise
    $configPath = "$env:USERPROFILE\.aider\config.yaml"  # TBD — verify location
    if (Test-Path $configPath) {
        $content = Get-Content $configPath -Raw
        if ($content -match 'auto_commits:\s*true') { return $true }
    }
    return $false
}
```

#### Step 4: Create Session Discovery Function

```powershell
function Get-AllAiderSessions {
    # Scan aider's session storage (TBD — verify location and format)
    # Return array of session objects matching the standard schema:
    # @{ sessionId; customTitle; firstPrompt; projectPath; created; modified;
    #    messageCount; model; source='aider'; ... }
}
```

#### Step 5: Wire Into Main Loop

- Add `$aiderSessions = @(Get-AllAiderSessions)` alongside Claude/Codex discovery
- Merge into `$allSessions` array
- Everything else (display, colors, WT profiles, backgrounds, launch) works automatically via the registry

#### Step 6: Add Validation Tests

- Test that the new platform entry has all required fields (automatic via test 159)
- Test that `QuietCheckFunc` is callable (automatic via test 252)
- Test that `QuietFlag` is valid string or null (automatic via test 253)
- Add platform-specific tests if needed (e.g., "Aider QuietFlag Is --yes-always")

#### What You Do NOT Need to Do

Thanks to the Platform Registry architecture, you do NOT need to:
- Touch `Start-WTClaude` — it reads from registry automatically
- Touch `Show-SessionMenu` or `Write-SingleMenuRow` — colors/keys come from registry
- Touch background image generation — colors/display names come from registry
- Touch the WT profile naming — prefixes come from registry
- Add `if ($source -eq 'aider')` branches anywhere — the registry eliminates this
- Touch quiet/chatty toggle — `Get-PlatformQuietArgs` handles it generically

### 3.4 Remaining Platform Registry Work (Linux Port)

- [ ] Create `PLATFORM_REGISTRY` dict in Linux port (`linux/lib/platforms.py` or `config.py`)
- [ ] Add curses color pair initialization from registry
- [ ] Replace hardcoded source checks in `menu.py`, `image.py`, `claude-menu.py`
- [ ] Add `quiet_flag` and `quiet_check_func` to Linux registry entries

### 3.5 Remaining Generalization Work

- [ ] Auto-generate CLI choice prompt from installed platforms (currently hardcoded Claude/Codex)
- [ ] Auto-generate title bar from installed platforms (currently hardcoded)
- [ ] Auto-generate stats line segments from installed platforms (currently hardcoded 2-segment)
- [ ] Generalize `Get-CLIPath` to use `CLIPathFunc` from registry (reduce per-platform functions)

---

## Phase 4: Aider Integration (Lower Priority)

**Priority:** Lower than Copilot (#1) and OpenCode (#2) due to fundamental architecture mismatch.

### Why Aider Is Harder

Aider is **repo-centric, not session-centric**. Its mental model is "I'm editing this git repo," not "I'm in session X." This creates significant friction for a session manager:

| Factor | Copilot CLI / OpenCode | Aider |
|--------|----------------------|-------|
| **Centralized sessions** | Yes (`~/.copilot/session-state/`, SQLite) | None — `.aider.*` files scattered per-repo |
| **Session IDs** | Yes (directory names, SQLite IDs) | None — one history file per repo |
| **Resume by ID** | `--resume <id>` / `--session <id>` | No. Only `--restore-chat-history` (replays single file in cwd) |
| **Multiple sessions per repo** | Yes | No — one history per directory |
| **Token/cost data on disk** | JSONL / SQLite | Not persisted (in-memory only, shown via `/tokens`) |
| **Data format** | Structured (JSONL, SQLite, YAML) | Markdown chat log + YAML config |
| **Fork** | No native (same as others) | No native |

### What We'd Have to Build Ourselves

1. **Session registry** — Aider has no centralized session directory. We'd need to maintain our own registry of repos where Aider has been used (in `session-mapping.json` or a new `aider-repos.json`)
2. **Session discovery** — Scan registered repos for `.aider.chat.history.md` existence
3. **Multi-session support** — Aider only has one history per repo. To support multiple sessions, we'd need to manage renamed history files (e.g., `.aider.chat.history.MySession.md`) and launch with `--chat-history-file <path>`
4. **Cost tracking** — Zero structured cost data on disk. Options: (a) parse markdown chat log for token mentions, (b) require `--analytics-log` to be enabled, or (c) accept no cost data for Aider sessions

### Aider Technical Details

**Installation:** Python package (`pip install aider-chat`). PowerShell one-liner: `irm https://aider.chat/install.ps1 | iex`

**Files created per-repo:**
| File | Format | Purpose |
|------|--------|---------|
| `.aider.chat.history.md` | Markdown | Full chat transcript |
| `.aider.input.history` | Plain text | User input history (readline) |
| `.aider.tags.cache.v3/` | Directory | Code indexing cache |
| `.aider.conf.yml` | YAML | Per-repo configuration |

**Key CLI flags:**
| Flag | Purpose |
|------|---------|
| `--restore-chat-history` | Replay prior conversation into LLM context (closest to "resume") |
| `--chat-history-file <path>` | Use alternate history file (enables multi-session) |
| `--yes-always` | Auto-approve all changes (danger mode / QuietFlag) |
| `--auto-commits` | Auto-commit changes to git (default: true) |
| `--model <model>` | Specify LLM (supports any model via LiteLLM) |
| `--analytics-log <path>` | Log analytics events to file (opt-in) |

**No SQLite. No JSONL. No session IDs. No centralized data store.**

### 4.1 Install and Verify

- [ ] Install Aider (`pip install aider-chat`)
- [ ] Run in 2+ different repos, examine `.aider.*` files created
- [ ] Test `--restore-chat-history` — does it reliably restore context?
- [ ] Test `--chat-history-file <path>` — can we point to a custom history file?
- [ ] Test `--analytics-log <path>` — what data is logged? Is it structured enough for token extraction?
- [ ] Verify `aider` is a Python script or .exe on Windows (for `.ps1` shim detection in `Start-WTClaude`)

**Decision gate:** If `--chat-history-file` doesn't work reliably for multi-session, Aider integration is limited to one session per repo (much less useful).

### 4.2 Session Discovery (`Get-AllAiderSessions`)

- [ ] Design session registry: where do we track which repos have Aider sessions?
  - Option A: Scan all known project paths from Claude/Codex session-mapping for `.aider.chat.history.md`
  - Option B: Maintain a separate `aider-repos.json` registry updated when user launches Aider from SessionForge
  - Option C: Let user configure watched directories
- [ ] For each discovered repo, read `.aider.chat.history.md` for: first user message (title), message count, last modified date
- [ ] Read `.aider.conf.yml` for model if present
- [ ] Map to session object: `sessionId` (hash of repo path?), `projectPath`, `created`, `modified`, `source='aider'`
- [ ] No native session ID — we generate one (hash or GUID mapped to repo path)

### 4.3 Launch Dispatch

- [ ] Continue: `aider --restore-chat-history` in the repo's working directory
- [ ] For multi-session: `aider --chat-history-file <path> --restore-chat-history`
- [ ] New session: launch `aider` in target directory (creates new `.aider.*` files)
- [ ] Fork: copy `.aider.chat.history.md` to a new file, launch with `--chat-history-file` pointing to copy
- [ ] QuietFlag: `--yes-always` (already defined in registry docs above)

### 4.4 Cost and Tokens

- [ ] Investigate `--analytics-log` output format — can we extract token counts?
- [ ] If no structured data: show "N/A" in Cost column for Aider sessions
- [ ] If analytics log is parseable: calculate costs using LiteLLM pricing

### 4.5 Platform Registry Entry

```powershell
aider = @{
    Key            = 'A'
    DisplayName    = 'Aider'
    Color          = 'Green'
    ColorRGB       = @(0, 200, 83)
    WTPrefix       = 'Aider-'
    CLIName        = 'aider'
    ResumeCmd      = '--restore-chat-history'    # No session ID — launches in cwd
    ForkCmd        = $null
    CLIPathFunc    = 'Get-AiderCLIPath'
    QuietFlag      = '--yes-always'
    QuietCheckFunc = 'Test-AiderQuietMode'
}
```

Note: `ResumeCmd` has no `{0}` placeholder because Aider has no session IDs. This breaks the current pattern — `Start-ContinueSession` would need a special path for platforms with no session ID (launch in working directory with flags only).

### 4.6 Testing

- [ ] Same test matrix as other platforms (0 sessions, not installed, continue, new)
- [ ] Test multi-session via `--chat-history-file` if supported
- [ ] Test that missing `.aider.chat.history.md` is handled gracefully

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| `copilot --resume <id>` doesn't accept direct IDs | Blocks integration | Verify in Phase 1.1 before coding |
| OpenCode requires running server daemon | Complicates launch | Test in Phase 2.1; may need to auto-start server |
| Copilot CLI file format changes (just went GA today) | Breaks parsing | Pin to known schema, add version detection |
| OpenCode not available on Windows | Limits to Linux only | Check in Phase 2.1; Windows may be fine (Go binary) |
| Aider has no session IDs | Can't resume specific sessions | Generate synthetic IDs from repo path hash; track in session-mapping |
| Aider has no centralized session directory | Session discovery is expensive | Maintain our own registry of Aider repos |
| Aider has no structured cost/token data | Cost column empty for Aider | Accept N/A, or parse `--analytics-log` if user opts in |
| `--chat-history-file` may not work for multi-session | Limited to 1 session per repo | Test in Phase 4.1; fall back to single-session if broken |
| Too many CLI sources clutter the display | UX degradation | Consider grouping/filtering by source |
| Python dependency grows (Windows) | Install friction | Already required for Codex; no incremental cost |

---

## Definition of Done

Each integration is complete when:
- [ ] Sessions appear in the unified menu with correct source marker and color
- [ ] Continue launches the correct CLI with the correct session ID in a WT profile with watermark
- [ ] New session prompts include the new CLI option
- [ ] Works when the tool is not installed (graceful skip, no errors)
- [ ] Works on both Windows and Linux
- [ ] Debug logging covers all discovery and dispatch paths
- [ ] Documentation updated (all .md files)
