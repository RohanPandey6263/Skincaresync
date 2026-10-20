"""Outbound email: provider abstraction and authentication templates."""

from .sender import (
    ConsoleEmailSender,
    EmailDeliveryError,
    EmailSender,
    OutboundEmail,
    ResendEmailSender,
    SmtpEmailSender,
    build_sender,
    deliver,
    get_sender,
    set_sender,
)

__all__ = [
    "ConsoleEmailSender",
    "EmailDeliveryError",
    "EmailSender",
    "OutboundEmail",
    "ResendEmailSender",
    "SmtpEmailSender",
    "build_sender",
    "deliver",
    "get_sender",
    "set_sender",
]
