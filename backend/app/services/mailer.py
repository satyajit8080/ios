import logging
import smtplib
from email.message import EmailMessage

from app.core.config import settings

logger = logging.getLogger(__name__)


def send_email(to: str, subject: str, html: str, text: str) -> bool:
    if not settings.SMTP_HOST:
        logger.info("SMTP not configured; email to %s suppressed: %s", to, subject)
        return False
    msg = EmailMessage()
    msg["From"] = settings.SMTP_FROM
    msg["To"] = to
    msg["Subject"] = subject
    msg.set_content(text)
    msg.add_alternative(html, subtype="html")
    try:
        with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=15) as server:
            server.starttls()
            if settings.SMTP_USER:
                server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
            server.send_message(msg)
        return True
    except Exception as exc:
        logger.error("email send failed: %s", exc)
        return False


def send_password_reset(to: str, token: str) -> bool:
    link = f"{settings.FRONTEND_RESET_URL}?token={token}"
    return send_email(
        to,
        "Reset your password",
        f"""<p>Use the link below to set a new password. It expires in {settings.RESET_TOKEN_MINUTES} minutes.</p>
<p><a href="{link}">Set a new password</a></p>
<p>If you didn't ask for this, you can ignore this email.</p>""",
        f"Set a new password: {link}\nThe link expires in {settings.RESET_TOKEN_MINUTES} minutes.",
    )
