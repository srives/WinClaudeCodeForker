"""
Curses-based interactive menu for Claude Code Session Manager (Linux).
Provides arrow-key navigation and session management interface.
"""

import curses
from typing import List, Optional, Callable, Tuple
from dataclasses import dataclass
from enum import Enum, auto

from .session import Session


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
        curses.init_pair(1, curses.COLOR_CYAN, -1)      # Title
        curses.init_pair(2, curses.COLOR_GREEN, -1)     # Selected
        curses.init_pair(3, curses.COLOR_YELLOW, -1)    # Warning
        curses.init_pair(4, curses.COLOR_WHITE, curses.COLOR_BLUE)  # Highlight
        curses.init_pair(5, curses.COLOR_MAGENTA, -1)   # Model

    def _draw_header(self, stdscr):
        """Draw the menu header."""
        max_y, max_x = stdscr.getmaxyx()

        # Title
        title = "Claude Code Session Manager"
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

        # Get visible sessions
        visible = self._get_visible_sessions()

        for i, session in enumerate(visible):
            if start_y + i >= max_y - 3:
                break

            is_selected = (self.page_start + i) == self.selected_index
            self._draw_session_row(stdscr, start_y + i, session, is_selected, max_x)

    def _draw_session_row(self, stdscr, y: int, session: Session, is_selected: bool, max_x: int):
        """Draw a single session row."""
        # Build row data
        row_data = [
            session.display_name[:25],
            session.model[:8] if session.model else '',
            str(session.message_count),
            session.modified.strftime('%m/%d %H:%M'),
            session.project_path[-30:] if len(session.project_path) > 30 else session.project_path,
        ]

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

        # Key hints - two lines for more options
        hints1 = "↑↓:Nav | Enter:Select | n:New | c:Continue | f:Fork | x:Delete"
        hints2 = "r:Refresh | i:Debug/Info | q:Quit | 1-5:Sort"

        try:
            stdscr.addstr(max_y - 3, 2, hints1, curses.color_pair(1))
            stdscr.addstr(max_y - 2, 2, hints2, curses.color_pair(1))
        except curses.error:
            pass

    def _get_column_headers(self) -> List[str]:
        """Get column header labels."""
        return ['Session', 'Model', 'Msgs', 'Modified', 'Path']

    def _format_row(self, columns: List[str], max_width: int, is_header: bool = False) -> str:
        """Format a row with fixed column widths."""
        widths = [25, 8, 5, 12, 35]  # Column widths
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

        # Sort by column (1-5)
        elif ord('1') <= key <= ord('5'):
            col = key - ord('1')
            if self.sort_column == col:
                self.sort_descending = not self.sort_descending
            else:
                self.sort_column = col
                self.sort_descending = True
            self._sort_sessions()

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
        """Sort sessions by the current sort column."""
        sort_keys = [
            lambda s: s.display_name.lower(),
            lambda s: s.model.lower() if s.model else '',
            lambda s: s.message_count,
            lambda s: s.modified,
            lambda s: s.project_path.lower(),
        ]

        if 0 <= self.sort_column < len(sort_keys):
            self.sessions.sort(key=sort_keys[self.sort_column], reverse=self.sort_descending)


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
