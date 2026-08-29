"""Outbound email: provider abstraction and authentication templates."""

from .sender import (
    ConsoleEmailSender,
    EmailSender,
    OutboundEmail,
    SmtpEmailSender,
    build_sender,
    get_sender,
    set_sender,
)

__all__ = [
    "ConsoleEmailSender",
    "EmailSender",
    "OutboundEmail",
    "SmtpEmailSender",
    "build_sender",
    "get_sender",
    "set_sender",
]
