"""
Curses-based interactive menu for SessionForge (Linux).
Provides arrow-key navigation and session management interface.
"""

import curses
from typing import List, Optional, Callable, Tuple, Dict
from dataclasses import dataclass
from enum import Enum, auto

from .session import Session
from .config import get_config, DEFAULT_COLUMNS
from .registry import get_platform


class MenuAction(Enum):
    """Actions that can be performed on a session."""
    CONTINUE = auto()
    FORK = auto()
    DELETE = auto()
    RENAME = auto()
    NOTES = auto()
    BACK = auto()
    QUIT = auto()
    NEW_SESSION = auto()
    REFRESH = auto()
    TOGGLE_HIDDEN = auto()
    COST_ANALYSIS = auto()
    DEBUG = auto()
    CONFIG = auto()
    ABOUT = auto()


@dataclass
class MenuItem:
    """A menu item with a key and label."""
    key: str
    label: str
    action: MenuAction


class SessionMenu:
    """
    Interactive curses-based menu for session management.
    """

    def __init__(self):
        self.sessions: List[Session] = []
        self.selected_index: int = 0
        self.page_start: int = 0
        self.page_size: int = 10
        self.show_hidden: bool = False
        self.sort_column: int = 0
        self.sort_descending: bool = True

    def run(self, sessions: List[Session]) -> Tuple[Optional[Session], MenuAction]:
        """
        Run the interactive menu.

        Args:
            sessions: List of sessions to display

        Returns:
            Tuple of (selected session, action to perform)
        """
        self.sessions = sessions

        try:
            return curses.wrapper(self._main_loop)
        except KeyboardInterrupt:
            return (None, MenuAction.QUIT)

    def _main_loop(self, stdscr) -> Tuple[Optional[Session], MenuAction]:
        """Main curses loop."""
        # Setup
        curses.curs_set(0)  # Hide cursor
        curses.use_default_colors()
        self._init_colors()

        # Calculate page size based on terminal height
        max_y, _ = stdscr.getmaxyx()
        self.page_size = max(5, max_y - 10)  # Leave room for header/footer

        while True:
            stdscr.clear()
            self._draw_header(stdscr)
            self._draw_sessions(stdscr)
            self._draw_footer(stdscr)
            stdscr.refresh()

            # Handle input
            key = stdscr.getch()
            result = self._handle_key(key)

            if result is not None:
                return result

    def _init_colors(self):
        """Initialize color pairs."""
        curses.init_pair(1, curses.COLOR_CYAN, -1)      # Title / menu text
        curses.init_pair(2, curses.COLOR_GREEN, -1)     # Selected
        curses.init_pair(3, curses.COLOR_YELLOW, -1)    # Warning
        curses.init_pair(4, curses.COLOR_WHITE, curses.COLOR_BLUE)  # Highlight row
        curses.init_pair(5, curses.COLOR_MAGENTA, -1)   # Model
        curses.init_pair(6, curses.COLOR_WHITE, -1)     # Menu key letter (bright)

    def _draw_menu_item(self, stdscr, y: int, x: int, word: str, key_char: str) -> int:
        """
        Draw a menu item with the key character highlighted.
        Returns the new x position after drawing.

        Args:
            stdscr: curses window
            y: row position
            x: column position
            word: the word to display (e.g., "New", "Continue")
            key_char: the character that activates it (e.g., "n", "c")

        Example: _draw_menu_item(stdscr, 10, 5, "New", "n")
                 displays "New" with "N" in white and "ew" in cyan

        If key is not in word, shows "key:word" format (e.g., "x:Delete")
        """
        key_lower = key_char.lower()
        word_lower = word.lower()

        # Find position of key in word
        key_pos = word_lower.find(key_lower)

        try:
            if key_pos == -1:
                # Key not in word, show as "key:word" format
                stdscr.addstr(y, x, key_char, curses.color_pair(6) | curses.A_BOLD)
                stdscr.addstr(y, x + 1, ":", curses.color_pair(1))
                stdscr.addstr(y, x + 2, word, curses.color_pair(1))
                return x + 2 + len(word)
            else:
                # Draw parts: before key, key (highlighted), after key
                if key_pos > 0:
                    stdscr.addstr(y, x, word[:key_pos], curses.color_pair(1))
                stdscr.addstr(y, x + key_pos, word[key_pos], curses.color_pair(6) | curses.A_BOLD)
                if key_pos < len(word) - 1:
                    stdscr.addstr(y, x + key_pos + 1, word[key_pos + 1:], curses.color_pair(1))
                return x + len(word)
        except curses.error:
            return x + len(word)

    def _draw_header(self, stdscr):
        """Draw the menu header."""
        max_y, max_x = stdscr.getmaxyx()

        # Title
        title = "S E S S I O N   F O R G E"
        stdscr.addstr(0, 2, title, curses.color_pair(1) | curses.A_BOLD)

        # Session count
        count_str = f"Sessions: {len(self.sessions)}"
        stdscr.addstr(0, max_x - len(count_str) - 2, count_str)

        # Column headers
        headers = self._get_column_headers()
        header_line = self._format_row(headers, max_x - 4, is_header=True)
        stdscr.addstr(2, 2, header_line, curses.A_BOLD | curses.A_UNDERLINE)

    def _draw_sessions(self, stdscr):
        """Draw the session list."""
        max_y, max_x = stdscr.getmaxyx()
        start_y = 4

        # Leave room for footer (1 line if wide, 2 if narrow)
        hints_full_len = 140  # Approximate length of single-line hints
        footer_lines = 1 if max_x >= hints_full_len else 2

        # Get visible sessions
        visible = self._get_visible_sessions()

        for i, session in enumerate(visible):
            if start_y + i >= max_y - (footer_lines + 1):
                break

            is_selected = (self.page_start + i) == self.selected_index
            row_num = self.page_start + i + 1  # 1-indexed row number
            self._draw_session_row(stdscr, start_y + i, session, is_selected, max_x, row_num)

    def _draw_session_row(self, stdscr, y: int, session: Session, is_selected: bool, max_x: int, row_num: int = 0):
        """Draw a single session row based on column config."""
        # Build row data dynamically based on visible columns
        visible_cols = self._get_visible_columns()
        row_data = []

        for key, header, width in visible_cols:
            if key == 'row_num':
                row_data.append(str(row_num))
            elif key == 'source':
                row_data.append(get_platform(session.source)['key'])
            elif key == 'session':
                row_data.append(session.display_name[:width])
            elif key == 'model':
                row_data.append(session.model[:width] if session.model else '')
            elif key == 'messages':
                row_data.append(str(session.message_count))
            elif key == 'cost':
                row_data.append(f"${session.cost:.2f}" if session.cost > 0 else '')
            elif key == 'created':
                row_data.append(session.created.strftime('%m/%d %H:%M'))
            elif key == 'modified':
                row_data.append(session.modified.strftime('%m/%d %H:%M'))
            elif key == 'forked_from':
                row_data.append(session.forked_from[:width] if session.forked_from else '')
            elif key == 'git_branch':
                row_data.append(session.git_branch[:width] if session.git_branch else '')
            elif key == 'notes':
                row_data.append(session.notes[:width] if session.notes else '')
            elif key == 'path':
                path = session.project_path
                row_data.append(path[-width:] if len(path) > width else path)
            else:
                row_data.append('')

        row_str = self._format_row(row_data, max_x - 4)

        # Apply styling
        if is_selected:
            attr = curses.color_pair(4) | curses.A_BOLD
        else:
            attr = curses.A_NORMAL

        try:
            stdscr.addstr(y, 2, row_str, attr)
        except curses.error:
            pass  # Ignore errors from writing at edge of screen

    def _draw_footer(self, stdscr):
        """Draw the menu footer with key hints."""
        max_y, max_x = stdscr.getmaxyx()

        # Menu items: (word, key_char) - key_char will be highlighted
        # Using descriptive words where the key letter is part of the word
        menu_items_row1 = [
            ("↑↓", None),      # Special - no key highlight
            ("Enter", None),   # Special - no key highlight
            ("New", "n"),
            ("Continue", "c"),
            ("Fork", "f"),
            ("Delete", "x"),   # x key for delete
            ("Rename", "e"),   # e key for edit/rename
        ]
        menu_items_row2 = [
            ("Hide", "h"),
            ("Cost", "o"),     # o is in Cost
            ("Debug", "d"),
            ("Refresh", "r"),
            ("About", "a"),
            ("Quit", "q"),
        ]

        # Calculate if we can fit on one line
        # Rough estimate: each item + separator
        total_len = sum(len(w) + 3 for w, _ in menu_items_row1 + menu_items_row2)

        try:
            if max_x >= total_len + 4:
                # Single line
                y = max_y - 2
                x = 2
                all_items = menu_items_row1 + menu_items_row2
                for i, (word, key) in enumerate(all_items):
                    if key:
                        x = self._draw_menu_item(stdscr, y, x, word, key)
                    else:
                        stdscr.addstr(y, x, word, curses.color_pair(1))
                        x += len(word)
                    # Add separator except after last item
                    if i < len(all_items) - 1:
                        stdscr.addstr(y, x, " | ", curses.color_pair(1))
                        x += 3
            else:
                # Two lines
                for row_num, items in enumerate([menu_items_row1, menu_items_row2]):
                    y = max_y - 3 + row_num
                    x = 2
                    for i, (word, key) in enumerate(items):
                        if key:
                            x = self._draw_menu_item(stdscr, y, x, word, key)
                        else:
                            stdscr.addstr(y, x, word, curses.color_pair(1))
                            x += len(word)
                        # Add separator except after last item in row
                        if i < len(items) - 1:
                            stdscr.addstr(y, x, " | ", curses.color_pair(1))
                            x += 3
        except curses.error:
            pass

    # Column definitions: (config_key, header, width)
    COLUMN_DEFS = [
        ('row_num', '#', 3),
        ('source', 'Src', 4),
        ('session', 'Session', 25),
        ('model', 'Model', 8),
        ('messages', 'Msgs', 5),
        ('cost', 'Cost', 8),
        ('created', 'Created', 12),
        ('modified', 'Modified', 12),
        ('forked_from', 'Forked From', 20),
        ('git_branch', 'Git', 15),
        ('notes', 'Notes', 15),
        ('path', 'Path', 30),
    ]

    def _get_visible_columns(self) -> List[Tuple[str, str, int]]:
        """Get list of visible columns based on config."""
        config = get_config()
        columns = config.columns if hasattr(config, 'columns') else DEFAULT_COLUMNS

        visible = []
        for key, header, width in self.COLUMN_DEFS:
            if columns.get(key, True):  # Default to visible
                visible.append((key, header, width))
        return visible

    def _get_column_headers(self) -> List[str]:
        """Get column header labels based on config."""
        return [header for _, header, _ in self._get_visible_columns()]

    def _get_column_widths(self) -> List[int]:
        """Get column widths based on config."""
        return [width for _, _, width in self._get_visible_columns()]

    def _format_row(self, columns: List[str], max_width: int, is_header: bool = False) -> str:
        """Format a row with column widths from config."""
        widths = self._get_column_widths()
        parts = []

        for i, (col, width) in enumerate(zip(columns, widths)):
            if len(col) > width:
                col = col[:width-1] + '…'
            parts.append(col.ljust(width))

        return ' '.join(parts)[:max_width]

    def _get_visible_sessions(self) -> List[Session]:
        """Get the sessions visible on the current page."""
        end = min(self.page_start + self.page_size, len(self.sessions))
        return self.sessions[self.page_start:end]

    def _handle_key(self, key: int) -> Optional[Tuple[Optional[Session], MenuAction]]:
        """Handle a keypress. Returns result if menu should exit."""

        # Navigation
        if key == curses.KEY_UP or key == ord('k'):
            self._move_selection(-1)
        elif key == curses.KEY_DOWN or key == ord('j'):
            self._move_selection(1)
        elif key == curses.KEY_PPAGE:  # Page Up
            self._move_selection(-self.page_size)
        elif key == curses.KEY_NPAGE:  # Page Down
            self._move_selection(self.page_size)
        elif key == curses.KEY_HOME:
            self.selected_index = 0
            self.page_start = 0
        elif key == curses.KEY_END:
            self.selected_index = len(self.sessions) - 1
            self._adjust_page()

        # Selection
        elif key == ord('\n') or key == curses.KEY_ENTER:
            if self.sessions:
                return (self.sessions[self.selected_index], MenuAction.CONTINUE)

        # Actions
        elif key == ord('n') or key == ord('N'):
            return (None, MenuAction.NEW_SESSION)
        elif key == ord('c') or key == ord('C'):
            if self.sessions:
                return (self.sessions[self.selected_index], MenuAction.CONTINUE)
        elif key == ord('f') or key == ord('F'):
            if self.sessions:
                return (self.sessions[self.selected_index], MenuAction.FORK)
        elif key == ord('x') or key == ord('X'):
            # Changed from 'd' to 'x' for delete
            if self.sessions:
                return (self.sessions[self.selected_index], MenuAction.DELETE)
        elif key == ord('r') or key == ord('R'):
            return (None, MenuAction.REFRESH)
        elif key == ord('i') or key == ord('I') or key == ord('d') or key == ord('D'):
            # 'i' for Info/Debug, 'd' also works
            return (None, MenuAction.DEBUG)
        elif key == ord('q') or key == ord('Q') or key == 27:  # 27 = ESC
            return (None, MenuAction.QUIT)

        # Sort by column (1-7)
        elif ord('1') <= key <= ord('7'):
            col = key - ord('1')
            if self.sort_column == col:
                self.sort_descending = not self.sort_descending
            else:
                self.sort_column = col
                self.sort_descending = True
            self._sort_sessions()

        # Hide unnamed toggle
        elif key == ord('h') or key == ord('H'):
            return (None, MenuAction.TOGGLE_HIDDEN)

        # Cost analysis
        elif key == ord('o') or key == ord('O'):
            return (None, MenuAction.COST_ANALYSIS)

        # Column config
        elif key == ord('g') or key == ord('G'):
            return (None, MenuAction.CONFIG)

        # About
        elif key == ord('a') or key == ord('A'):
            return (None, MenuAction.ABOUT)

        # Rename (e for edit)
        elif key == ord('e') or key == ord('E'):
            if self.sessions:
                return (self.sessions[self.selected_index], MenuAction.RENAME)

        return None

    def _move_selection(self, delta: int):
        """Move the selection by delta rows."""
        if not self.sessions:
            return

        self.selected_index = max(0, min(len(self.sessions) - 1, self.selected_index + delta))
        self._adjust_page()

    def _adjust_page(self):
        """Adjust the page start to keep selection visible."""
        if self.selected_index < self.page_start:
            self.page_start = self.selected_index
        elif self.selected_index >= self.page_start + self.page_size:
            self.page_start = self.selected_index - self.page_size + 1

    def _sort_sessions(self):
        """Sort sessions by the current sort column based on visible columns."""
        # Map column keys to sort functions
        sort_key_map = {
            'row_num': lambda s: 0,  # No sort
            'source': lambda s: s.source,
            'session': lambda s: s.display_name.lower(),
            'model': lambda s: s.model.lower() if s.model else '',
            'messages': lambda s: s.message_count,
            'cost': lambda s: s.cost,
            'created': lambda s: s.created,
            'modified': lambda s: s.modified,
            'forked_from': lambda s: s.forked_from.lower() if s.forked_from else '',
            'git_branch': lambda s: s.git_branch.lower() if s.git_branch else '',
            'notes': lambda s: s.notes.lower() if s.notes else '',
            'path': lambda s: s.project_path.lower(),
        }

        visible_cols = self._get_visible_columns()
        if 0 <= self.sort_column < len(visible_cols):
            col_key = visible_cols[self.sort_column][0]
            sort_fn = sort_key_map.get(col_key, lambda s: 0)
            self.sessions.sort(key=sort_fn, reverse=self.sort_descending)


class SessionActionMenu:
    """
    Secondary menu for actions on a selected session.
    """

    def run(self, session: Session) -> MenuAction:
        """Show action menu for a session."""
        try:
            return curses.wrapper(lambda stdscr: self._main_loop(stdscr, session))
        except KeyboardInterrupt:
            return MenuAction.BACK

    def _main_loop(self, stdscr, session: Session) -> MenuAction:
        """Main loop for action menu."""
        curses.curs_set(0)
        curses.use_default_colors()

        actions = [
            MenuItem('c', 'Continue session', MenuAction.CONTINUE),
            MenuItem('f', 'Fork session', MenuAction.FORK),
            MenuItem('r', 'Rename', MenuAction.RENAME),
            MenuItem('x', 'Delete', MenuAction.DELETE),
            MenuItem('n', 'Edit notes', MenuAction.NOTES),
            MenuItem('b', 'Back', MenuAction.BACK),
        ]

        selected = 0

        while True:
            stdscr.clear()

            # Header
            stdscr.addstr(1, 2, f"Session: {session.display_name}", curses.A_BOLD)
            stdscr.addstr(2, 2, f"Path: {session.project_path}")

            # Actions
            for i, action in enumerate(actions):
                y = 5 + i
                if i == selected:
                    attr = curses.A_REVERSE
                else:
                    attr = curses.A_NORMAL

                stdscr.addstr(y, 4, f"[{action.key}] {action.label}", attr)

            stdscr.refresh()

            # Handle input
            key = stdscr.getch()

            if key == curses.KEY_UP:
                selected = max(0, selected - 1)
            elif key == curses.KEY_DOWN:
                selected = min(len(actions) - 1, selected + 1)
            elif key == ord('\n') or key == curses.KEY_ENTER:
                return actions[selected].action
            elif key == 27:  # ESC
                return MenuAction.BACK
            else:
                # Check for direct key press
                for action in actions:
                    if key == ord(action.key) or key == ord(action.key.upper()):
                        return action.action

        return MenuAction.BACK
