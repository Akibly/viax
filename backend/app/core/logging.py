"""Structured logging with a request ID threaded through every call.

Audit OPS-01: the word "monitoring" appears nowhere in the specification
corpus. For an LLM product that is not a maturity gap, it is blindness — you
cannot separate a prompt regression from a cohort change, a retrieval failure
from a hard question, or a cost spike from growth.

The minimum that makes the rest of the build debuggable:

  * one request ID, generated at the edge, present on every log line and
    returned to the client so a student's bug report is traceable;
  * token counts and cost on every model call;
  * which chunks were retrieved and at what score;
  * the score distribution, so drift after a prompt change is visible.
"""

from __future__ import annotations

import logging
import sys
from collections.abc import MutableMapping
from contextvars import ContextVar
from typing import Any, cast
from uuid import uuid4

import structlog

_request_id: ContextVar[str | None] = ContextVar("request_id", default=None)
_user_id: ContextVar[str | None] = ContextVar("user_id", default=None)


def new_request_id() -> str:
    return uuid4().hex


def bind_request(request_id: str, user_id: str | None = None) -> None:
    _request_id.set(request_id)
    _user_id.set(user_id)


def current_request_id() -> str | None:
    return _request_id.get()


def _inject_context(
    _logger: Any, _name: str, event: MutableMapping[str, Any]
) -> MutableMapping[str, Any]:
    if rid := _request_id.get():
        event["request_id"] = rid
    if uid := _user_id.get():
        event["user_id"] = uid
    return event


_REDACT_KEYS = frozenset(
    {"password", "token", "api_key", "anon_key", "service_role_key", "authorization", "secret"}
)


def _redact(
    _logger: Any, _name: str, event: MutableMapping[str, Any]
) -> MutableMapping[str, Any]:
    """Cheap insurance against a credential reaching a log aggregator."""
    for key in list(event):
        if any(marker in key.lower() for marker in _REDACT_KEYS):
            event[key] = "[redacted]"
    return event


def configure_logging(level: str = "INFO", fmt: str = "json", service: str = "vivax-api") -> None:
    renderer: Any = (
        structlog.processors.JSONRenderer()
        if fmt == "json"
        else structlog.dev.ConsoleRenderer(colors=True)
    )

    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            _inject_context,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            _redact,
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            renderer,
        ],
        wrapper_class=structlog.make_filtering_bound_logger(
            logging.getLevelNamesMapping()[level]
        ),
        logger_factory=structlog.PrintLoggerFactory(file=sys.stdout),
        cache_logger_on_first_use=True,
    )
    structlog.contextvars.bind_contextvars(service=service)

    # Route uvicorn and friends through the same pipeline so the output is
    # one stream, not three formats interleaved.
    logging.basicConfig(format="%(message)s", stream=sys.stdout, level=level)
    for noisy in ("uvicorn", "uvicorn.error", "uvicorn.access", "httpx"):
        logging.getLogger(noisy).handlers.clear()
        logging.getLogger(noisy).propagate = True


def get_logger(name: str | None = None) -> structlog.stdlib.BoundLogger:
    return cast(structlog.stdlib.BoundLogger, structlog.get_logger(name))
