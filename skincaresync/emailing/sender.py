"""Outbound email.

The project had no email infrastructure, so this defines the seam rather than
picking a vendor. Two providers ship:

* `console`   - renders the message to the log and, if EMAIL_OUTBOX_DIR is set,
                writes it to a file. Sends nothing. The development default.
* `smtp`      - stdlib smtplib against any SMTP relay. Works with a self-hosted
                relay, a local capture tool such as Mailpit, or a commercial
                provider's SMTP endpoint, without this codebase committing to
                one or requiring a paid account.

Adding a vendor's HTTP API later means implementing `EmailSender` and
registering it in `build_sender`; nothing else changes.

`config.get_settings()` refuses to start a production process with the console
provider, so a deploy cannot silently swallow verification mail.
"""

from __future__ import annotations

import logging
import os
import smtplib
import uuid
from dataclasses import dataclass
from email.message import EmailMessage
from pathlib import Path
from typing import Protocol

from ..config import Settings, get_settings

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class OutboundEmail:
    to: str
    subject: str
    text_body: str
    html_body: str


class EmailSender(Protocol):
    def send(self, message: OutboundEmail) -> None: ...


def _build_mime(message: OutboundEmail, sender: str) -> EmailMessage:
    mime = EmailMessage()
    mime["Subject"] = message.subject
    mime["From"] = sender
    mime["To"] = message.to
    # Transactional mail should not be auto-replied to or filed as bulk.
    mime["Auto-Submitted"] = "auto-generated"
    mime.set_content(message.text_body)
    mime.add_alternative(message.html_body, subtype="html")
    return mime


class ConsoleEmailSender:
    """Development sender. Logs the message; optionally writes it to disk."""

    def __init__(self, sender: str, outbox_dir: str | None = None):
        self.sender = sender
        self.outbox_dir = Path(outbox_dir) if outbox_dir else None

    def send(self, message: OutboundEmail) -> None:
        # The body contains a single-use link, which is a credential. It is
        # acceptable in a local console sender because it is the only way to
        # complete the flow without a mailbox, but it must never be reachable in
        # production -- get_settings() enforces that.
        logger.info(
            "[console email] to=%s subject=%s\n%s",
            message.to,
            message.subject,
            message.text_body,
        )
        if self.outbox_dir is None:
            return
        self.outbox_dir.mkdir(parents=True, exist_ok=True)
        path = self.outbox_dir / f"{uuid.uuid4().hex}.eml"
        path.write_bytes(bytes(_build_mime(message, self.sender)))
        logger.info("[console email] written to %s", path)


class SmtpEmailSender:
    """Delivers through an SMTP relay."""

    def __init__(self, settings: Settings):
        if not settings.smtp_host:
            raise ValueError("SMTP_HOST is required for the smtp email provider")
        self.settings = settings
        self.host: str = settings.smtp_host

    def send(self, message: OutboundEmail) -> None:
        settings = self.settings
        mime = _build_mime(message, settings.email_from)
        with smtplib.SMTP(self.host, settings.smtp_port, timeout=10) as client:
            if settings.smtp_starttls:
                client.starttls()
            if settings.smtp_username and settings.smtp_password:
                client.login(settings.smtp_username, settings.smtp_password)
            client.send_message(mime)
        # Recipient only. Never the subject or body, which carry the token.
        logger.info("sent %s email to %s", message.subject, _redact(message.to))


def _redact(address: str) -> str:
    """`alice@example.com` -> `a***@example.com`, for logs."""
    local, _, domain = address.partition("@")
    if not domain:
        return "***"
    return f"{local[:1]}***@{domain}"


def build_sender(settings: Settings | None = None) -> EmailSender:
    settings = settings or get_settings()
    if settings.email_provider == "smtp":
        return SmtpEmailSender(settings)
    if settings.email_provider == "console":
        return ConsoleEmailSender(settings.email_from, os.getenv("EMAIL_OUTBOX_DIR"))
    raise ValueError(
        f"Unknown EMAIL_PROVIDER {settings.email_provider!r}; expected 'console' or 'smtp'"
    )


_sender: EmailSender | None = None


def get_sender() -> EmailSender:
    global _sender
    if _sender is None:
        _sender = build_sender()
    return _sender


def set_sender(sender: EmailSender | None) -> None:
    """Override the process-wide sender. Used by tests."""
    global _sender
    _sender = sender
