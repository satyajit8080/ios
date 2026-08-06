from datetime import date, timedelta
from typing import Iterable, List, Tuple


def streaks(days: Iterable[date], today: date | None = None) -> Tuple[int, int]:
    """Returns (current_streak, longest_streak). Current allows today OR yesterday as the anchor."""
    today = today or date.today()
    unique = sorted(set(days))
    if not unique:
        return 0, 0

    longest = run = 1
    for prev, cur in zip(unique, unique[1:]):
        run = run + 1 if (cur - prev).days == 1 else 1
        longest = max(longest, run)

    current = 0
    anchor = today if unique[-1] == today else (today - timedelta(days=1) if unique[-1] == today - timedelta(days=1) else None)
    if anchor is not None:
        day_set = set(unique)
        cursor = anchor
        while cursor in day_set:
            current += 1
            cursor -= timedelta(days=1)
    return current, max(longest, current)


def date_range(start: date, end: date) -> List[date]:
    return [start + timedelta(days=i) for i in range((end - start).days + 1)]
