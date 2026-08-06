"""Firebase Cloud Messaging v1 sender."""
import json
import logging
from typing import Dict, List, Optional

import httpx
from google.auth.transport.requests import Request as GoogleRequest
from google.oauth2 import service_account

from app.core.config import settings

logger = logging.getLogger(__name__)
_SCOPES = ["https://www.googleapis.com/auth/firebase.messaging"]
_credentials = None


def _get_credentials():
    global _credentials
    if _credentials is None:
        if not settings.FIREBASE_SERVICE_ACCOUNT_JSON:
            return None
        try:
            _credentials = service_account.Credentials.from_service_account_file(
                settings.FIREBASE_SERVICE_ACCOUNT_JSON, scopes=_SCOPES
            )
        except Exception as exc:
            logger.warning("Firebase credentials unavailable: %s", exc)
            return None
    if not _credentials.valid:
        _credentials.refresh(GoogleRequest())
    return _credentials


def send_push(tokens: List[str], title: str, body: str, data: Optional[Dict[str, str]] = None) -> int:
    creds = _get_credentials()
    if not creds or not tokens:
        logger.info("push skipped (no creds or tokens): %s", title)
        return 0

    url = f"https://fcm.googleapis.com/v1/projects/{settings.FIREBASE_PROJECT_ID}/messages:send"
    headers = {"Authorization": f"Bearer {creds.token}", "Content-Type": "application/json"}
    sent = 0
    with httpx.Client(timeout=15) as client:
        for token in tokens:
            payload = {
                "message": {
                    "token": token,
                    "notification": {"title": title, "body": body},
                    "data": {k: str(v) for k, v in (data or {}).items()},
                    "apns": {
                        "payload": {"aps": {"sound": "default", "badge": 1, "content-available": 1}}
                    },
                }
            }
            try:
                resp = client.post(url, headers=headers, content=json.dumps(payload))
                if resp.status_code < 300:
                    sent += 1
                else:
                    logger.warning("FCM error %s: %s", resp.status_code, resp.text[:200])
            except Exception as exc:
                logger.warning("FCM send failed: %s", exc)
    return sent
