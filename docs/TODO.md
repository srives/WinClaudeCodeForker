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

## Phase 3: Shared Infrastructure (Before or During Phase 1)

### 3.1 Refactor Python Availability Check

- [ ] Rename `Test-CodexPythonAvailable` → `Test-PythonAvailable` (used by Codex and OpenCode)
- [ ] Single Python availability check cached for the session

### 3.2 Generalize Source Column Colors

- [ ] Define a color map: `@{ claude = 'Blue'; codex = 'Magenta'; copilot = 'Green'; opencode = 'Cyan' }`
- [ ] Replace hardcoded `if source -eq 'codex' { Magenta } else { Blue }` with color map lookup
- [ ] Apply to: `Show-SessionMenu`, `Write-SingleMenuRow`, WT Config rows, title bar

### 3.3 Generalize CLI Path Detection

- [ ] Create `Get-CLIPath -Name <tool>` that wraps `Get-Command` with `.ps1` shim detection
- [ ] Replace `Get-ClaudeCLIPath` / `Get-CodexCLIPath` with `Get-CLIPath -Name claude` / `Get-CLIPath -Name codex`
- [ ] New tools just call `Get-CLIPath -Name copilot` / `Get-CLIPath -Name opencode`

### 3.4 Generalize WT Profile Prefix

- [ ] Profile prefix map: `@{ claude = 'Claude-'; codex = 'Codex-'; copilot = 'Copilot-'; opencode = 'OpenCode-' }`
- [ ] Single function: `Get-WTProfilePrefix -Source <source>`

### 3.5 Update Documentation

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
