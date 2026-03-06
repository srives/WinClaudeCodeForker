#!/usr/bin/env python3
"""
SessionForge (sf) - AI Coding Session Manager for Linux.

A terminal-based session manager for Claude Code and Codex CLI with support for:
- Session discovery and listing
- Fork/Continue workflows
- Background watermark images
- Kitty, Konsole, and Direct (WSL) terminal integration

Usage:
    python3 claude-menu.py [options]

Options:
    --help      Show this help message
    --version   Show version information
    --config    Open configuration
    --debug     Show debug information
"""

import sys
import os
import shutil
import argparse
import json
from pathlib import Path

# Add lib directory to path
lib_dir = Path(__file__).parent / 'lib'
sys.path.insert(0, str(lib_dir))

from lib.config import get_config_manager, get_config, get_claude_projects_path, get_all_claude_paths, setup_logging, log_debug, log_info, log_error, get_debug_log_path
from lib.session import get_all_sessions, get_all_codex_sessions, get_git_branch, get_session_model, get_session_cost, Session
from lib.menu import SessionMenu, SessionActionMenu, MenuAction
from lib.image import create_background_image, BackgroundInfo
from lib.terminal import get_adapter, detect_terminal, is_wsl
from lib.registry import get_platform, get_installed_platforms


VERSION = "3.1.1"


def check_dependencies() -> dict:
    """Check which dependencies are available."""
    deps = {
        'python': sys.version,
        'imagemagick': shutil.which('convert') is not None,
        'pillow': False,
        'kitty': shutil.which('kitty') is not None,
        'konsole': shutil.which('konsole') is not None,
        'claude': shutil.which('claude') is not None,
        'codex': shutil.which('codex') is not None,
        'wsl': is_wsl(),
    }

    # Check Pillow
    try:
        from PIL import Image
        deps['pillow'] = True
    except ImportError:
        pass

    return deps


def show_debug_menu():
    """Show the debug/info menu."""
    deps = check_dependencies()
    config = get_config()

    print("\n" + "=" * 50)
    print("Debug / System Information")
    print("=" * 50)

    print("\n[Environment]")
    print(f"  Python:       {deps['python'].split()[0]}")
    print(f"  WSL:          {'Yes' if deps['wsl'] else 'No'}")
    print(f"  Platform:     {sys.platform}")

    print("\n[Image Libraries]")
    if deps['imagemagick']:
        print("  ImageMagick:  ✓ Available")
    else:
        print("  ImageMagick:  ✗ Not found")
        print("                Install: sudo apt install imagemagick")

    if deps['pillow']:
        print("  Pillow/PIL:   ✓ Available")
    else:
        print("  Pillow/PIL:   ✗ Not found")
        print("                Install: sudo apt install python3-pil")
        print("                     or: pip3 install pillow")

    if not deps['imagemagick'] and not deps['pillow']:
        print("\n  ⚠ WARNING: No image library available!")
        print("    Background images will not work.")

    print("\n[Terminal Emulators]")
    if deps['kitty']:
        print("  Kitty:        ✓ Available")
    else:
        print("  Kitty:        ✗ Not found")
        print("                Install: sudo apt install kitty")

    if deps['konsole']:
        print("  Konsole:      ✓ Available")
    else:
        print("  Konsole:      ✗ Not found")
        print("                Install: sudo apt install konsole")

    if deps['wsl'] and not deps['kitty'] and not deps['konsole']:
        print("\n  ℹ WSL Mode: Using direct terminal (no GUI needed)")

    print("\n[CLI Tools]")
    if deps['claude']:
        print("  Claude:       ✓ Available")
    else:
        print("  Claude:       ✗ Not found")
        print("                Install from: https://claude.ai/download")

    if deps['codex']:
        print("  Codex:        ✓ Available")
    else:
        print("  Codex:        ✗ Not found")
        print("                Install from: https://openai.com/codex")

    print("\n[Configuration]")
    print(f"  Terminal:     {config.terminal}")
    print(f"  Shell:        {config.shell}")
    print(f"  Config file:  ~/.config/claude-menu/config.json")

    print("\n[Paths]")
    print(f"  Claude data:  {config.claude_path}")
    print(f"  Menu data:    {config.menu_path}")
    projects_path = get_claude_projects_path()
    print(f"  Projects:     {projects_path}")
    if projects_path.exists():
        project_count = len(list(projects_path.iterdir()))
        print(f"                ({project_count} project directories)")
    else:
        print("                (directory does not exist)")

    print("\n[Debug Logging]")
    debug_log = get_debug_log_path()
    print(f"  Debug mode:   {'Enabled' if config.debug else 'Disabled'}")
    print(f"  Log file:     {debug_log}")
    if debug_log.exists():
        log_size = debug_log.stat().st_size
        print(f"  Log size:     {log_size:,} bytes")

    print("\n" + "=" * 50)
    print("\n[Actions]")
    print("  1. Re-detect terminal")
    print("  2. Test image generation")
    print("  3. View config file")
    print("  4. Toggle debug logging")
    print("  5. View debug log (last 50 lines)")
    print("  6. Clear debug log")
    print("  7. Scan for sessions (verbose)")
    print("  8. Dump raw session JSONL (debug parsing)")
    print("  9. Back to main menu")
    print("")

    try:
        choice = input("Select [1-9]: ").strip()

        if choice == '1':
            detected = detect_terminal()
            print(f"\nDetected terminal: {detected}")
            config_mgr = get_config_manager()
            config_mgr.config.terminal = detected
            config_mgr.save()
            print(f"Configuration updated.")
            input("\nPress Enter to continue...")

        elif choice == '2':
            print("\nTesting image generation...")
            test_info = BackgroundInfo(
                session_name="Test Session",
                directory="/tmp/test",
                git_branch="main",
                model="sonnet",
            )
            result = create_background_image(test_info)
            if result:
                print(f"✓ Success! Image created at: {result}")
            else:
                print("✗ Failed to create image.")
                print("  Make sure ImageMagick or Pillow is installed.")
            input("\nPress Enter to continue...")

        elif choice == '3':
            config_file = Path.home() / '.config' / 'claude-menu' / 'config.json'
            if config_file.exists():
                print(f"\n{config_file}:\n")
                print(config_file.read_text())
            else:
                print("\nConfig file does not exist yet.")
            input("\nPress Enter to continue...")

        elif choice == '4':
            config_mgr = get_config_manager()
            config_mgr.config.debug = not config_mgr.config.debug
            config_mgr.save()
            setup_logging(config_mgr.config.debug)
            status = "enabled" if config_mgr.config.debug else "disabled"
            print(f"\nDebug logging {status}.")
            if config_mgr.config.debug:
                debug_path = get_debug_log_path()
                print(f"Log file: {debug_path}")
                log_debug(f"Debug log: {debug_path}")
            input("\nPress Enter to continue...")

        elif choice == '5':
            if debug_log.exists():
                print(f"\n=== Last 50 lines of {debug_log} ===\n")
                with open(debug_log, 'r') as f:
                    lines = f.readlines()
                    for line in lines[-50:]:
                        print(line.rstrip())
            else:
                print("\nNo debug log file exists yet.")
                print("Enable debug mode and run some operations first.")
            input("\nPress Enter to continue...")

        elif choice == '6':
            if debug_log.exists():
                debug_log.unlink()
                print("\nDebug log cleared.")
            else:
                print("\nNo debug log to clear.")
            input("\nPress Enter to continue...")

        elif choice == '7':
            print("\nScanning for sessions (verbose)...")

            # Show all possible paths
            print("\n[Checking all possible Claude data locations]")
            all_paths = get_all_claude_paths()
            for path_str, exists in all_paths:
                status = "✓ EXISTS" if exists else "✗ not found"
                print(f"  {status}: {path_str}")

            projects_path = get_claude_projects_path()
            print(f"\n[Using: {projects_path}]\n")

            if not projects_path.exists():
                print(f"ERROR: Projects path does not exist: {projects_path}")
                print("\nPossible causes:")
                print("  1. Claude CLI hasn't been run yet in this environment")
                print("  2. In WSL, Claude may store data in Windows home directory")
                print("  3. Claude data is in a non-standard location")
                print("\nTry running 'claude' once to create the directory.")
            else:
                for item in projects_path.iterdir():
                    print(f"\n[{item.name}]")
                    if item.is_dir():
                        index_file = item / 'sessions-index.json'
                        if index_file.exists():
                            print(f"  Has sessions-index.json: Yes")
                            try:
                                with open(index_file) as f:
                                    data = json.load(f)
                                entries = data.get('entries', [])
                                print(f"  Sessions in index: {len(entries)}")
                                for entry in entries[:5]:
                                    sid = entry.get('sessionId', 'unknown')[:8]
                                    summary = entry.get('summary', '')[:30]
                                    print(f"    - {sid}: {summary}")
                                if len(entries) > 5:
                                    print(f"    ... and {len(entries) - 5} more")
                            except Exception as e:
                                print(f"  Error reading index: {e}")
                        else:
                            print(f"  Has sessions-index.json: No")
                            jsonl_files = list(item.glob('*.jsonl'))
                            print(f"  JSONL files found: {len(jsonl_files)}")
                            for jf in jsonl_files[:3]:
                                print(f"    - {jf.name}")
                    else:
                        print(f"  (not a directory)")

            print("\n" + "=" * 50)
            sessions = get_all_sessions()
            print(f"\nTotal sessions discovered: {len(sessions)}")
            input("\nPress Enter to continue...")

        elif choice == '8':
            # Dump raw session content for debugging
            print("\nDump Raw Session JSONL Content")
            print("=" * 50)

            projects_path = get_claude_projects_path()
            if not projects_path.exists():
                print(f"Projects path does not exist: {projects_path}")
                input("\nPress Enter to continue...")
            else:
                # Find first session file
                session_files = list(projects_path.glob('**/*.jsonl'))
                if not session_files:
                    print("No session files found.")
                    input("\nPress Enter to continue...")
                else:
                    print(f"Found {len(session_files)} session file(s)")
                    for i, sf in enumerate(session_files[:5], 1):
                        print(f"  {i}. {sf} ({sf.stat().st_size:,} bytes)")

                    print("\nSelect file to dump (1-5), or press Enter for first:")
                    file_choice = input("> ").strip()
                    idx = int(file_choice) - 1 if file_choice.isdigit() else 0
                    idx = max(0, min(idx, len(session_files) - 1))

                    session_file = session_files[idx]
                    print(f"\n{'=' * 60}")
                    print(f"FILE: {session_file}")
                    print(f"SIZE: {session_file.stat().st_size:,} bytes")
                    print(f"{'=' * 60}\n")

                    print("First 10 lines (formatted JSON):\n")
                    try:
                        with open(session_file, 'r', encoding='utf-8') as f:
                            for line_num, line in enumerate(f, 1):
                                if line_num > 10:
                                    print(f"\n... ({line_num - 1}+ more lines)")
                                    break
                                try:
                                    entry = json.loads(line)
                                    print(f"--- Line {line_num} ---")
                                    print(f"Type: {entry.get('type', 'NO TYPE')}")
                                    print(f"Keys: {list(entry.keys())}")

                                    # Show relevant fields for debugging
                                    if 'model' in entry:
                                        print(f"model: {entry['model']}")
                                    if 'message' in entry:
                                        msg = entry['message']
                                        if isinstance(msg, dict):
                                            print(f"message keys: {list(msg.keys())}")
                                            if 'model' in msg:
                                                print(f"message.model: {msg['model']}")
                                            if 'usage' in msg:
                                                print(f"message.usage: {msg['usage']}")
                                    if 'usage' in entry:
                                        print(f"usage: {entry['usage']}")
                                    print()
                                except json.JSONDecodeError as e:
                                    print(f"Line {line_num}: JSON ERROR: {e}")
                                    print(f"  Raw: {line[:200]}...")
                    except IOError as e:
                        print(f"Error reading file: {e}")

                    input("\nPress Enter to continue...")

    except KeyboardInterrupt:
        print("\nCancelled.")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="SessionForge (sf) - AI Coding Session Manager for Linux"
    )
    parser.add_argument('--version', action='store_true', help='Show version')
    parser.add_argument('--config', action='store_true', help='Show configuration')
    parser.add_argument('--debug', action='store_true', help='Show debug info menu')
    parser.add_argument('--enable-debug', action='store_true', help='Enable debug logging to file')
    parser.add_argument('--terminal', choices=['kitty', 'konsole', 'direct'],
                        help='Terminal to use (kitty, konsole, or direct for WSL)')

    args = parser.parse_args()

    if args.version:
        print(f"SessionForge (sf) v{VERSION}")
        return 0

    # Initialize configuration
    config_mgr = get_config_manager()
    config = config_mgr.load()

    # Enable debug logging if requested
    if args.enable_debug:
        config.debug = True
        config_mgr.save()
        print(f"Debug logging enabled. Log file: {get_debug_log_path()}")

    # Setup logging based on config
    setup_logging(config.debug)
    log_info(f"Claude Menu v{VERSION} starting")
    log_debug(f"Terminal: {config.terminal}, Debug: {config.debug}")

    if args.debug:
        show_debug_menu()
        return 0

    # Set terminal from args or auto-detect
    if args.terminal:
        config.terminal = args.terminal
        config_mgr.save()
    elif not config.terminal:
        detected = detect_terminal()
        config.terminal = detected
        config_mgr.save()
        if detected == 'direct':
            print("No GUI terminal found. Using direct mode (sessions run in current terminal).")

    if args.config:
        show_config(config)
        return 0

    # Run main menu loop
    return run_menu_loop()


def run_menu_loop() -> int:
    """Run the main menu loop."""
    config = get_config()
    log_info("Entering main menu loop")
    hide_unnamed = False

    while True:
        # Load sessions
        log_debug("Loading sessions...")
        print("Loading sessions...")
        sessions = get_all_sessions()
        log_info(f"Loaded {len(sessions)} sessions")

        # Enrich sessions with additional info
        log_debug(f"Enriching {len(sessions)} sessions with model/cost data...")
        sessions_with_files = 0
        sessions_with_model = 0
        for session in sessions:
            # Verify session file exists
            if session._session_file and session._session_file.exists():
                sessions_with_files += 1
            else:
                log_debug(f"Session {session.session_id[:8]} has no valid _session_file")

            if not session.model:
                session.model = get_session_model(session)
            if session.model:
                sessions_with_model += 1
            if not session.git_branch:
                session.git_branch = get_git_branch(session.project_path)
            if session.cost == 0:
                session.cost = get_session_cost(session)

        log_debug(f"Enrichment complete: {sessions_with_files}/{len(sessions)} have valid files, {sessions_with_model}/{len(sessions)} have models")

        # Filter unnamed if toggled
        if hide_unnamed:
            sessions = [s for s in sessions if s.custom_title or s.first_prompt]

        # Show main menu
        menu = SessionMenu()
        menu.show_hidden = not hide_unnamed
        selected_session, action = menu.run(sessions)

        # Handle action
        if action == MenuAction.QUIT:
            print("Goodbye!")
            return 0

        elif action == MenuAction.DEBUG:
            show_debug_menu()

        elif action == MenuAction.NEW_SESSION:
            handle_new_session()

        elif action == MenuAction.REFRESH:
            continue  # Loop will reload sessions

        elif action == MenuAction.TOGGLE_HIDDEN:
            hide_unnamed = not hide_unnamed
            status = "hidden" if hide_unnamed else "shown"
            print(f"Unnamed sessions now {status}")

        elif action == MenuAction.COST_ANALYSIS:
            show_cost_analysis(sessions)

        elif action == MenuAction.CONFIG:
            show_column_config()

        elif action == MenuAction.ABOUT:
            show_about()

        elif action == MenuAction.CONTINUE and selected_session:
            handle_continue(selected_session)

        elif action == MenuAction.FORK and selected_session:
            handle_fork(selected_session)

        elif action == MenuAction.DELETE and selected_session:
            handle_delete(selected_session)

        elif action == MenuAction.RENAME and selected_session:
            handle_rename(selected_session)

        elif selected_session:
            # Show session action menu
            action_menu = SessionActionMenu()
            sub_action = action_menu.run(selected_session)

            if sub_action == MenuAction.CONTINUE:
                handle_continue(selected_session)
            elif sub_action == MenuAction.FORK:
                handle_fork(selected_session)
            elif sub_action == MenuAction.DELETE:
                handle_delete(selected_session)
            elif sub_action == MenuAction.RENAME:
                handle_rename(selected_session)


def handle_new_session():
    """Start a new Claude or Codex session."""
    log_info("handle_new_session() called")

    # If multiple platforms installed, offer CLI choice
    use_codex = False
    installed = get_installed_platforms()
    if len(installed) > 1:
        # Build prompt from registry
        options = []
        key_map = {}
        for p in installed.values():
            options.append(f"[{p['key']}]{p['display_name']}")
            key_map[p['key']] = p
        prompt_str = " / ".join(options) + " / [A]bort"
        print(f"\nWhich CLI? {prompt_str}:")
        try:
            choice = input("> ").strip().upper()
            if choice in key_map:
                selected_platform = key_map[choice]
                if selected_platform['cli_name'] == 'codex':
                    use_codex = True
            elif choice == 'A':
                print("Cancelled.")
                return
        except KeyboardInterrupt:
            print("\nCancelled.")
            return

    selected = get_platform('codex') if use_codex else get_platform('claude')
    print(f"\nStarting new {selected['display_name']} session...")
    print("Enter the project directory (or press Enter for current directory):")

    try:
        directory = input("> ").strip()
        if not directory:
            directory = os.getcwd()

        log_debug(f"New session directory: {directory}")

        if not os.path.isdir(directory):
            log_error(f"Directory does not exist: {directory}")
            print(f"Error: Directory does not exist: {directory}")
            input("Press Enter to continue...")
            return

        # Codex: just launch in directory (skip model/profile workflow)
        if use_codex:
            codex_cmd = get_platform('codex')['new_cmd']
            log_info(f"Launching {codex_cmd} in directory: {directory}")
            original_dir = os.getcwd()
            os.chdir(directory)
            os.system(codex_cmd)
            os.chdir(original_dir)
            log_info("handle_new_session() completed (codex)")
            return

        # Get optional session name
        print("Enter session name (optional):")
        name = input("> ").strip()
        log_debug(f"Session name: {name or '(none)'}")

        # Launch Claude
        config = get_config()
        adapter = get_adapter(config.terminal)
        log_debug(f"Using terminal adapter: {config.terminal}")

        if name:
            # Create profile with background
            log_debug(f"Creating profile with background for: {name}")
            bg_info = BackgroundInfo(
                session_name=name,
                directory=directory,
                git_branch=get_git_branch(directory),
            )
            bg_path = create_background_image(bg_info)
            log_debug(f"Background image path: {bg_path}")

            result = adapter.create_profile(name, directory, str(bg_path) if bg_path else None)
            log_debug(f"create_profile result: {result}")

            claude_cmd = get_platform('claude')['new_cmd']
            log_info(f"Launching session '{name}' with command '{claude_cmd}'")
            result = adapter.launch_session(name, command=claude_cmd, working_dir=directory)
            log_debug(f"launch_session result: {result}")
        else:
            # Just launch Claude without profile
            log_info(f"Launching claude in directory: {directory}")
            original_dir = os.getcwd()
            os.chdir(directory)
            log_debug(f"Changed to directory: {directory}")
            claude_cmd = get_platform('claude')['new_cmd']
            log_debug(f"Running: {claude_cmd}")
            exit_code = os.system(claude_cmd)
            log_debug(f"Claude exit code: {exit_code}")
            os.chdir(original_dir)
            log_debug(f"Restored directory: {original_dir}")

        log_info("handle_new_session() completed")

    except KeyboardInterrupt:
        log_debug("handle_new_session() cancelled by user")
        print("\nCancelled.")
    except Exception as e:
        log_error(f"handle_new_session() error: {e}")
        print(f"\nError: {e}")
        input("Press Enter to continue...")


def handle_continue(session: Session):
    """Continue an existing session (Claude or Codex)."""
    log_info(f"handle_continue() called for session: {session.session_id[:8]} (source={session.source})")
    print(f"\nContinuing session: {session.display_name}")

    config = get_config()
    log_debug(f"Terminal type: {config.terminal}")

    adapter = get_adapter(config.terminal)
    log_debug(f"Adapter: {adapter.name}, available: {adapter.is_available()}")

    # Build resume command based on source (from PlatformRegistry)
    platform = get_platform(session.source)
    cmd = platform['resume_cmd'].format(session_id=session.session_id)
    if session.source == 'codex':
        log_debug(f"Codex resume: dispatching to '{cmd}' in {session.project_path}")
    log_debug(f"Command: {cmd}")

    # For direct mode or if no profile exists, run directly
    if config.terminal == 'direct' or not adapter.is_available():
        log_debug(f"Direct mode: chdir to {session.project_path}")
        os.chdir(session.project_path)
        log_debug(f"Running: {cmd}")
        os.system(cmd)
    elif session.custom_title and adapter.profile_exists(session.custom_title):
        log_debug(f"Using existing profile: {session.custom_title}")
        result = adapter.launch_session(session.custom_title, command=cmd, working_dir=session.project_path)
        log_debug(f"Launch result: {result}")
        if not result:
            log_error("Failed to launch, falling back to direct")
            os.chdir(session.project_path)
            os.system(cmd)
    else:
        # Launch directly
        log_debug(f"No profile, running directly in {session.project_path}")
        os.chdir(session.project_path)
        os.system(cmd)


def handle_fork(session: Session):
    """Fork a session (Claude or Codex)."""
    log_info(f"handle_fork() called for session: {session.session_id[:8]} (source={session.source})")
    print(f"\nForking session: {session.display_name}")

    # Codex has native fork command
    if session.source == 'codex':
        platform = get_platform(session.source)
        cmd = platform['fork_cmd'].format(session_id=session.session_id)
        log_debug(f"Codex fork command: {cmd}")
        os.chdir(session.project_path)
        os.system(cmd)
        return

    print("Enter name for forked session:")

    try:
        name = input("> ").strip()
        if not name:
            print("Fork cancelled.")
            input("Press Enter to continue...")
            return

        log_debug(f"Fork name: {name}")
        config = get_config()
        log_debug(f"Terminal type: {config.terminal}")

        adapter = get_adapter(config.terminal)
        log_debug(f"Adapter: {adapter.name}, available: {adapter.is_available()}")

        # Check if adapter is available
        if not adapter.is_available():
            log_error(f"Terminal '{config.terminal}' is not available, falling back to direct mode")
            print(f"Warning: {config.terminal} not available, running in current terminal")
            cmd = get_platform('claude')['resume_cmd'].format(session_id=session.session_id)
            os.chdir(session.project_path)
            log_debug(f"Running command: {cmd} in {session.project_path}")
            os.system(cmd)
            return

        # Create background image
        log_debug(f"Creating background image for fork...")
        bg_info = BackgroundInfo(
            session_name=name,
            directory=session.project_path,
            forked_from=session.display_name,
            git_branch=session.git_branch or get_git_branch(session.project_path),
            model=session.model,
        )
        bg_path = create_background_image(bg_info)
        log_debug(f"Background image: {bg_path}")

        # Create profile
        log_debug(f"Creating profile: {name}")
        profile_result = adapter.create_profile(name, session.project_path, str(bg_path) if bg_path else None)
        log_debug(f"Profile created: {profile_result}")

        # Launch with Claude resume
        cmd = get_platform('claude')['resume_cmd'].format(session_id=session.session_id)
        log_debug(f"Launch command: {cmd}")

        if config.terminal == 'direct':
            print(f"Forked session '{name}' ready.")
            log_debug(f"Direct mode: chdir to {session.project_path}")
            os.chdir(session.project_path)
            log_debug(f"Running: {cmd}")
            os.system(cmd)
        else:
            log_debug(f"Launching via adapter: {adapter.name}")
            result = adapter.launch_session(name, command=cmd, working_dir=session.project_path)
            log_debug(f"Launch result: {result}")
            if result:
                print(f"Forked session '{name}' launched in new terminal.")
            else:
                log_error(f"Failed to launch session, falling back to direct mode")
                print(f"Failed to launch in {config.terminal}, running in current terminal...")
                os.chdir(session.project_path)
                os.system(cmd)
            input("Press Enter to continue...")

    except KeyboardInterrupt:
        print("\nFork cancelled.")
    except Exception as e:
        log_error(f"handle_fork() error: {e}")
        print(f"\nError during fork: {e}")
        import traceback
        traceback.print_exc()
        input("Press Enter to continue...")


def handle_delete(session: Session):
    """Delete a session."""
    print(f"\nDelete session: {session.display_name}")
    print(f"Path: {session.project_path}")
    print("\nAre you sure? This cannot be undone. (y/N)")

    try:
        confirm = input("> ").strip().lower()
        if confirm != 'y':
            print("Deletion cancelled.")
            input("Press Enter to continue...")
            return

        # Remove terminal profile if exists
        config = get_config()
        adapter = get_adapter(config.terminal)

        if session.custom_title:
            adapter.remove_profile(session.custom_title)

        # Note: We don't delete the actual session file
        # as that's managed by Claude CLI
        print("Session profile removed.")
        input("Press Enter to continue...")

    except KeyboardInterrupt:
        print("\nCancelled.")


def handle_rename(session: Session):
    """Rename a session."""
    print(f"\nRename session: {session.display_name}")
    print("Enter new name:")

    try:
        new_name = input("> ").strip()
        if not new_name:
            print("Rename cancelled.")
            input("Press Enter to continue...")
            return

        # Update terminal profile
        config = get_config()
        adapter = get_adapter(config.terminal)

        if session.custom_title:
            adapter.remove_profile(session.custom_title)

        # Create new profile with new name
        bg_info = BackgroundInfo(
            session_name=new_name,
            directory=session.project_path,
            git_branch=session.git_branch,
            model=session.model,
            source=session.source,
        )
        bg_path = create_background_image(bg_info)
        adapter.create_profile(new_name, session.project_path, str(bg_path) if bg_path else None)

        print(f"Session renamed to '{new_name}'.")
        input("Press Enter to continue...")

    except KeyboardInterrupt:
        print("\nCancelled.")


def show_config(config):
    """Display current configuration."""
    deps = check_dependencies()

    print(f"""
SessionForge (sf) Configuration
=========================================
Terminal:     {config.terminal}
Shell:        {config.shell}
Claude Path:  {config.claude_path}
Menu Path:    {config.menu_path}
Debug:        {config.debug}

Dependencies:
  ImageMagick: {'✓' if deps['imagemagick'] else '✗'}
  Pillow:      {'✓' if deps['pillow'] else '✗'}
  Kitty:       {'✓' if deps['kitty'] else '✗'}
  Konsole:     {'✓' if deps['konsole'] else '✗'}
  Claude CLI:  {'✓' if deps['claude'] else '✗'}
  WSL:         {'Yes' if deps['wsl'] else 'No'}

Config file: ~/.config/claude-menu/config.json
""")


def show_cost_analysis(sessions):
    """Display cost analysis for all sessions."""
    print("\n" + "=" * 70)
    print("Cost Analysis")
    print("=" * 70)
    print(f"{'Session':<30} {'Cost':>10} {'Model':<8} {'Messages':>8}")
    print("-" * 70)

    total_cost = 0.0
    for session in sorted(sessions, key=lambda s: s.cost, reverse=True):
        if session.cost > 0:
            name = session.display_name[:28]
            print(f"{name:<30} ${session.cost:>8.2f} {session.model:<8} {session.message_count:>8}")
            total_cost += session.cost

    print("-" * 70)
    print(f"{'TOTAL':<30} ${total_cost:>8.2f}")
    print("=" * 70)

    print("\nPricing (per 1M tokens):")
    print("  Sonnet: $3 input, $15 output, $3.75 cache write, $0.30 cache read")
    print("  Opus:   $15 input, $75 output, $18.75 cache write, $1.50 cache read")
    print("  Haiku:  $0.25 input, $1.25 output, $0.3125 cache write, $0.025 cache read")

    input("\nPress Enter to continue...")


def show_column_config():
    """Show column configuration menu - toggle columns on/off."""
    from lib.config import DEFAULT_COLUMNS

    config_mgr = get_config_manager()
    config = config_mgr.load()

    # Column display names
    column_names = {
        'row_num': '# (Row Number)',
        'source': 'Source (C=Claude, X=Codex)',
        'session': 'Session Name',
        'model': 'Model',
        'messages': 'Messages',
        'cost': 'Cost',
        'created': 'Created',
        'modified': 'Modified',
        'forked_from': 'Forked From',
        'git_branch': 'Git Branch',
        'notes': 'Notes',
        'path': 'Path',
    }

    # Get current columns or use defaults
    columns = config.columns if hasattr(config, 'columns') else DEFAULT_COLUMNS.copy()

    while True:
        print("\n" + "=" * 50)
        print("Column Configuration")
        print("=" * 50)
        print("\nToggle columns on/off (press number to toggle):\n")

        col_keys = list(column_names.keys())
        for i, key in enumerate(col_keys, 1):
            status = "[X]" if columns.get(key, True) else "[ ]"
            print(f"  {i:2}. {status} {column_names[key]}")

        print("\n  s. Save and exit")
        print("  c. Cancel")

        try:
            choice = input("\nSelect [1-11/s/c]: ").strip().lower()

            if choice == 's':
                # Save configuration
                config.columns = columns
                config_mgr.save()
                print("\nColumn configuration saved.")
                input("Press Enter to continue...")
                return
            elif choice == 'c':
                print("\nCancelled - changes not saved.")
                input("Press Enter to continue...")
                return
            elif choice.isdigit():
                idx = int(choice) - 1
                if 0 <= idx < len(col_keys):
                    key = col_keys[idx]
                    columns[key] = not columns.get(key, True)
                    status = "enabled" if columns[key] else "disabled"
                    print(f"\n{column_names[key]} {status}")
        except (ValueError, KeyboardInterrupt):
            print("\nCancelled.")
            return


def show_about():
    """Show about screen with ASCII art."""
    import os
    os.system('clear' if os.name != 'nt' else 'cls')

    print("\033[93mSessionForge (sf) - AI Coding Session Manager with Terminal Forking\033[0m")
    print(f"\033[90mVersion: {VERSION} (Linux)\033[0m")
    print()
    # ASCII art in cyan
    cyan = "\033[96m"
    reset = "\033[0m"
    print(f"{cyan}=**=---========--------===--=====--==-------=={reset}")
    print(f"{cyan}==*#*==-=====++==-==============-------======={reset}")
    print(f"{cyan}--==-----=+++**++++++##*=*##*%%+=-------===--={reset}")
    print(f"{cyan}---=-----+#*+=###%%#++++*#%@@@#==-=--==--=---={reset}")
    print(f"{cyan}--==-----=+=====%@@@@@@@%%@@@%*=-----==------={reset}")
    print(f"{cyan}---====--=-=======*%@@@@@@@@@@#====--========={reset}")
    print(f"{cyan}----------====+======+%@@@@@@@%+============={reset}")
    print(f"{cyan}---=---==--==++-=-==+%@@@@@@@@*====+*+=-======{reset}")
    print(f"{cyan}------=---==++++-====*@@@@@@@@@%+======++====={reset}")
    print(f"{cyan}-----==----=+++======*#@@%@@@@%%+======+======{reset}")
    print(f"{cyan}-=--=------==+++====*%%@@%%%@@%%+============={reset}")
    print(f"{cyan}----=------==++====+%@@@@@@%%%%%+============={reset}")
    print(f"{cyan}---=-------==++==*%#%%@@@@@@@@@@%============={reset}")
    print(f"{cyan}-----------==+++#@@@@%%%@@@@@@@@@#=======+++*+{reset}")
    print(f"{cyan}----------=-=+*%@@@@@@%*+#@@@@%@@@#=======+++={reset}")
    print(f"{cyan}-----=------==%@@@@@@@%**+#@%*+=+%@#=====+##+={reset}")
    print(f"{cyan}*#*+=--------*@@@%@@@@@@%%@@%+====+##*===+##*+{reset}")
    print(f"{cyan}--==#*=----==%@@@@@@@%%@@@@@@*====**%*+===+==={reset}")
    print(f"{cyan}==--=*#=----=*@@@@@@%%%%@@@@@%+=====+=====+==={reset}")
    print(f"{cyan}=----=*%*=---*%@@@@@@%%%@@@@@%+============+=={reset}")
    print(f"{cyan}--==--=+%#=--=#@@@@@@%%#%@@@@*======-========={reset}")
    print(f"{cyan}---=====+#@%*=+*@@@@@@%%%@@@#+================{reset}")
    print(f"{cyan}==========+#@@@%@@@@@@%%@@%*=================={reset}")
    print(f"{cyan}---====++===++*#@@@@%%%@@@%*+++=============++{reset}")
    print(f"{cyan} https://github.com/srives/SessionForge{reset}")
    print()
    print("\033[90mBy: S. Rives\033[0m")
    input()


if __name__ == '__main__':
    sys.exit(main() or 0)
