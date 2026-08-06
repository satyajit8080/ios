import json
from typing import Any, Optional

import redis

from app.core.config import settings

_pool = redis.ConnectionPool.from_url(settings.REDIS_URL, decode_responses=True)


def client() -> redis.Redis:
    return redis.Redis(connection_pool=_pool)


def cache_get(key: str) -> Optional[Any]:
    try:
        raw = client().get(key)
        return json.loads(raw) if raw else None
    except Exception:
        return None


def cache_set(key: str, value: Any, ttl: int = 300) -> None:
    try:
        client().setex(key, ttl, json.dumps(value, default=str))
    except Exception:
        pass


def cache_delete_prefix(prefix: str) -> None:
    try:
        r = client()
        for k in r.scan_iter(match=f"{prefix}*", count=500):
            r.delete(k)
    except Exception:
        pass


def rate_limit(key: str, limit: int, window_seconds: int) -> bool:
    """Returns True when the call is allowed."""
    try:
        r = client()
        current = r.incr(key)
        if current == 1:
            r.expire(key, window_seconds)
        return current <= limit
    except Exception:
        return True
