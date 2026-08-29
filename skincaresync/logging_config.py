"""Logging setup.

The application previously had no logging at all: every swallowed upstream
failure, cache-write collision and pool timeout was invisible in production.
Configuration is applied once, at API startup, and left alone when the host
process (gunicorn, a test runner) has already configured the root logger.
"""

from __future__ import annotations

import logging
import os

LOG_FORMAT = "%(asctime)s %(levelname)-8s %(name)s: %(message)s"


def configure_logging() -> None:
    level = os.getenv("LOG_LEVEL", "INFO").upper()
    if logging.getLogger().handlers:
        logging.getLogger("skincaresync").setLevel(level)
        return
    logging.basicConfig(level=level, format=LOG_FORMAT)
    logging.getLogger("skincaresync").setLevel(level)
