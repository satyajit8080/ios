"""Verify Sign in with Apple identity tokens against Apple's JWKS."""
import time
from typing import Any, Dict, Optional

import httpx
import jwt
from jwt import PyJWKClient

from app.core.config import settings

_jwk_client: Optional[PyJWKClient] = None
_jwk_fetched_at: float = 0.0


def _client() -> PyJWKClient:
    global _jwk_client, _jwk_fetched_at
    if _jwk_client is None or time.time() - _jwk_fetched_at > 86400:
        _jwk_client = PyJWKClient(settings.APPLE_KEYS_URL, cache_keys=True)
        _jwk_fetched_at = time.time()
    return _jwk_client


def verify_identity_token(identity_token: str) -> Dict[str, Any]:
    signing_key = _client().get_signing_key_from_jwt(identity_token)
    claims = jwt.decode(
        identity_token,
        signing_key.key,
        algorithms=["RS256"],
        audience=settings.APPLE_BUNDLE_ID,
        issuer=settings.APPLE_ISSUER,
    )
    if not claims.get("sub"):
        raise ValueError("apple token missing sub")
    return claims


async def fetch_apple_keys_raw() -> Dict[str, Any]:
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.get(settings.APPLE_KEYS_URL)
        resp.raise_for_status()
        return resp.json()
