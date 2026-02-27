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

## Phase 3: Platform Registry — Shared Infrastructure (Do This FIRST)

The current code has **~35+ hardcoded `if source == 'codex' ... else ...`** checks scattered across
both Windows and Linux. Adding a third platform means touching every one and turning binary if/else
into three-way branching. A platform registry eliminates this entirely — each new platform is just
a new entry in one table.

### 3.1 Platform Registry (Windows — `$Global:PlatformRegistry`)

Define a single hashtable that is the **sole source of truth** for every platform-specific value.
Every rendering, dispatch, and image generation function looks up from this registry instead of branching.

```powershell
$Global:PlatformRegistry = @{
    claude = @{
        Key          = 'C'                              # Src column letter
        DisplayName  = 'Claude Code'                    # Full display name (background images, prompts)
        Color        = 'Blue'                           # PowerShell console color name
        ColorRGB     = @(30, 144, 255)                  # RGB for System.Drawing (background images)
        WTPrefix     = 'Claude-'                        # Windows Terminal profile prefix
        CLIName      = 'claude'                         # Executable name for Get-Command / which
        ResumeCmd    = 'claude --resume {0}'            # Resume command template ({0} = session ID)
        ForkCmd      = $null                            # Fork command template ($null = not supported natively)
        NewCmd       = 'claude'                         # New session command
        CostFn       = 'Get-ClaudeSessionCost'          # Function name for cost calculation
    }
    codex = @{
        Key          = 'X'
        DisplayName  = 'Codex'
        Color        = 'Magenta'
        ColorRGB     = @(255, 0, 255)
        WTPrefix     = 'Codex-'
        CLIName      = 'codex'
        ResumeCmd    = 'codex resume {0}'
        ForkCmd      = 'codex fork {0}'
        NewCmd       = 'codex'
        CostFn       = 'Get-CodexSessionCost'
    }
    copilot = @{
        Key          = 'P'
        DisplayName  = 'Copilot'
        Color        = 'Green'
        ColorRGB     = @(0, 200, 83)
        WTPrefix     = 'Copilot-'
        CLIName      = 'copilot'
        ResumeCmd    = 'copilot --resume {0}'           # TBD — verify in Phase 1.1
        ForkCmd      = $null                            # Copilot has no native fork
        NewCmd       = 'copilot'
        CostFn       = 'Get-CopilotSessionCost'
    }
    opencode = @{
        Key          = 'O'
        DisplayName  = 'OpenCode'
        Color        = 'Cyan'
        ColorRGB     = @(0, 188, 212)
        WTPrefix     = 'OpenCode-'
        CLIName      = 'opencode'
        ResumeCmd    = 'opencode --session {0}'         # TBD — verify in Phase 2.1
        ForkCmd      = $null
        NewCmd       = 'opencode'
        CostFn       = 'Get-OpenCodeSessionCost'
    }
}
```

Tasks:

- [ ] Create `$Global:PlatformRegistry` hashtable (single source of truth)
- [ ] Create helper functions that look up from registry:
  - `Get-PlatformColor -Source <source>` → PowerShell color name
  - `Get-PlatformColorRGB -Source <source>` → System.Drawing.Color
  - `Get-PlatformKey -Source <source>` → single letter (`C`, `X`, `P`, `O`)
  - `Get-PlatformDisplayName -Source <source>` → "Claude Code", "Codex", etc.
  - `Get-PlatformWTPrefix -Source <source>` → "Claude-", "Codex-", etc.
  - `Get-PlatformResumeCmd -Source <source> -SessionId <id>` → formatted command string
  - `Get-PlatformForkCmd -Source <source> -SessionId <id>` → command string or `$null`
- [ ] Replace all ~35 hardcoded `if ($source -eq 'codex') { ... } else { ... }` with registry lookups
- [ ] Replace all hardcoded WT prefix logic (`"Claude-$name"`, `"Codex-$name"`) with `"$(Get-PlatformWTPrefix -Source $source)$name"`
- [ ] Replace all hardcoded color references in `Show-SessionMenu`, `Write-SingleMenuRow`, WT Config rows, title bar, cost analysis
- [ ] Replace hardcoded `platformText`/`platformColor` in `New-UniformBackgroundImage` with registry lookup
- [ ] Replace resume/fork command construction in `Start-ContinueSession`, `Start-ForkSession` with registry lookup
- [ ] Add validation test: every key in `$Global:PlatformRegistry` has all required fields

### 3.2 Platform Registry (Linux — `PLATFORM_REGISTRY` dict)

Same concept in Python for the Linux port.

```python
PLATFORM_REGISTRY = {
    'claude': {
        'key': 'C',
        'display_name': 'Claude Code',
        'curses_color': curses.COLOR_BLUE,
        'rgb': (30, 144, 255),
        'imagemagick_color': 'rgb(30,144,255)',
        'pil_color': (30, 144, 255, 255),
        'cli_name': 'claude',
        'resume_cmd': 'claude --resume {session_id}',
        'fork_cmd': None,
        'new_cmd': 'claude',
    },
    'codex': {
        'key': 'X',
        'display_name': 'Codex',
        'curses_color': curses.COLOR_MAGENTA,
        'rgb': (255, 0, 255),
        'imagemagick_color': 'rgb(255,0,255)',
        'pil_color': (255, 0, 255, 255),
        'cli_name': 'codex',
        'resume_cmd': 'codex resume {session_id}',
        'fork_cmd': 'codex fork {session_id}',
        'new_cmd': 'codex',
    },
    # copilot and opencode entries added when those integrations land
}
```

Tasks:

- [ ] Create `PLATFORM_REGISTRY` dict (in a new `linux/lib/platforms.py` or in `config.py`)
- [ ] Add curses color pair initialization from registry (replace hardcoded `init_pair` calls)
- [ ] Replace hardcoded source checks in `menu.py`, `image.py`, `claude-menu.py` with registry lookups
- [ ] Replace hardcoded color values in `_create_with_imagemagick` and `_create_with_pil` with registry lookup
- [ ] Replace hardcoded resume/fork commands in `handle_continue`, `handle_fork` with registry lookup

### 3.3 Refactor Python Availability Check

- [ ] Rename `Test-CodexPythonAvailable` → `Test-PythonAvailable` (used by Codex and OpenCode)
- [ ] Single Python availability check cached for the session

### 3.4 Generalize CLI Path Detection

- [ ] Create `Get-CLIPath -Source <source>` that reads `CLIName` from registry and wraps `Get-Command` with `.ps1` shim detection
- [ ] Replace `Get-ClaudeCLIPath` / `Get-CodexCLIPath` with `Get-CLIPath -Source claude` / `Get-CLIPath -Source codex`
- [ ] New tools just call `Get-CLIPath -Source copilot` / `Get-CLIPath -Source opencode`

### 3.5 Generalize New Session Prompt

- [ ] Auto-generate the CLI choice prompt from installed platforms in the registry
- [ ] E.g. if Claude + Codex + Copilot installed: `"[C]laude | code[X] | co[P]ilot | [A]bort"`
- [ ] If only Claude installed: skip the prompt entirely (current behavior)
- [ ] Use `Key` from registry as the hotkey letter

### 3.6 Generalize Title Bar and Stats Line

- [ ] Title bar: auto-generated from installed platforms — `"Codex (X), Copilot (P), and Claude Code (C) Session Manager..."`
- [ ] Stats line: one color-coded segment per installed platform, auto-generated from registry
- [ ] No hardcoded two-segment or three-segment layout — loop over platforms

### 3.7 Update Documentation

- [ ] Update CLAUDE.md, README.md, CHANGELOG.md, VERSION.md, PRODUCT_ANALYSIS.md
- [ ] Bump version (3.1.0 for Copilot, 3.2.0 for OpenCode, or 4.0.0 for both)

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| `copilot --resume <id>` doesn't accept direct IDs | Blocks integration | Verify in Phase 1.1 before coding |
| OpenCode requires running server daemon | Complicates launch | Test in Phase 2.1; may need to auto-start server |
| Copilot CLI file format changes (just went GA today) | Breaks parsing | Pin to known schema, add version detection |
| OpenCode not available on Windows | Limits to Linux only | Check in Phase 2.1; Windows may be fine (Go binary) |
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
