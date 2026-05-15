"""Tests for the core window-inference logic.

Run: python -m unittest test_claudex_roller.py
"""
from __future__ import annotations

import unittest
from datetime import datetime, timedelta, timezone

from claudex_roller import WINDOW, infer_window_start


def t(hours: float) -> datetime:
    """Build a UTC datetime at `hours` past a fixed epoch, for readable tests."""
    base = datetime(2026, 1, 1, 0, 0, tzinfo=timezone.utc)
    return base + timedelta(hours=hours)


class InferWindowStartTests(unittest.TestCase):
    def test_no_timestamps_returns_none(self) -> None:
        self.assertIsNone(infer_window_start([], t(10)))

    def test_single_recent_timestamp_starts_window(self) -> None:
        # One message at hour 8, now at hour 10 — window opened at 8, still open.
        self.assertEqual(infer_window_start([t(8)], t(10)), t(8))

    def test_single_stale_timestamp_no_open_window(self) -> None:
        # One message 6h ago — window already closed.
        self.assertIsNone(infer_window_start([t(4)], t(10)))

    def test_messages_within_one_window(self) -> None:
        # Three messages spread over 3h — all in the same window starting at first.
        timestamps = [t(7), t(8.5), t(9.5)]
        self.assertEqual(infer_window_start(timestamps, t(10)), t(7))

    def test_gap_starts_new_window(self) -> None:
        # First message at hour 0, gap > 5h, new message at hour 6.
        # Current window started at 6, not 0.
        timestamps = [t(0), t(6)]
        self.assertEqual(infer_window_start(timestamps, t(7)), t(6))

    def test_message_at_exactly_5h_starts_new_window(self) -> None:
        # The first window is [0, 5). A message AT hour 5 falls outside it,
        # opening a new window.
        timestamps = [t(0), t(5)]
        self.assertEqual(infer_window_start(timestamps, t(6)), t(5))

    def test_message_just_inside_5h_stays_in_window(self) -> None:
        # 4h59m is still inside the first window.
        timestamps = [t(0), t(0) + timedelta(hours=4, minutes=59)]
        self.assertEqual(infer_window_start(timestamps, t(2)), t(0))

    def test_overnight_idle_returns_none(self) -> None:
        # Last activity 8h ago — no window open. This is the scenario the tool
        # exists to prevent.
        self.assertIsNone(infer_window_start([t(2)], t(10)))

    def test_walks_through_multiple_old_windows_to_current(self) -> None:
        # Three separate windows; the current one starts at the last gap.
        timestamps = [t(0), t(1), t(6), t(7), t(13)]
        self.assertEqual(infer_window_start(timestamps, t(14)), t(13))

    def test_real_world_mid_window_detection(self) -> None:
        # The original bug: latest message is mid-window, not at the start.
        # Walk-back finds the true window start.
        start = t(5)
        timestamps = [start, t(7), t(8), t(9)]  # all within [5, 10)
        now = t(9.5)
        self.assertEqual(infer_window_start(timestamps, now), start)


class WindowConstantTests(unittest.TestCase):
    def test_window_is_5_hours(self) -> None:
        self.assertEqual(WINDOW, timedelta(hours=5))


if __name__ == "__main__":
    unittest.main()
