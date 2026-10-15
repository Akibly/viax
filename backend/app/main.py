"""VivaX API.

Every route lives under /v1. Unversioned paths make the first breaking change
a coordinated app-store release (audit API-04), and a mobile client cannot be
force-upgraded.
"""

from __future__ import annotations

import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import asyncpg
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.api.v1.health import router as health_router
from app.core.config import Settings, get_settings
from app.core.logging import bind_request, configure_logging, get_logger, new_request_id

log = get_logger(__name__)

REQUEST_ID_HEADER = "X-Request-ID"


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings: Settings = get_settings()
    configure_logging(settings.log_level, settings.log_format, settings.service_name)

    app.state.settings = settings
    app.state.pool = await asyncpg.create_pool(
        dsn=str(settings.database_url),
        min_size=1,
        max_size=10,
        command_timeout=30,
        # Session state lives in Postgres, not in process memory, so any
        # instance can serve any request and a reconnect can land anywhere
        # (audit SCALE-01).
        server_settings={"application_name": settings.service_name},
    )
    log.info("startup.complete", environment=str(settings.environment))
    try:
        yield
    finally:
        await app.state.pool.close()
        log.info("shutdown.complete")


app = FastAPI(
    title="VivaX API",
    version="0.1.0",
    lifespan=lifespan,
    docs_url="/v1/docs",
    openapi_url="/v1/openapi.json",
)


@app.middleware("http")
async def request_context(request: Request, call_next):  # type: ignore[no-untyped-def]
    """Assign a request ID, log the outcome, and return the ID to the client.

    The client echoes this into bug reports, which is the difference between
    "the app was slow" and a traceable request.
    """
    request_id = request.headers.get(REQUEST_ID_HEADER) or new_request_id()
    bind_request(request_id)
    started = time.perf_counter()

    try:
        response = await call_next(request)
    except Exception:
        duration_ms = round((time.perf_counter() - started) * 1000, 2)
        log.exception(
            "request.failed",
            method=request.method,
            path=request.url.path,
            duration_ms=duration_ms,
        )
        settings: Settings = request.app.state.settings
        body = {"error": "internal_error", "request_id": request_id}
        if settings.debug_errors:
            body["detail"] = "See server logs; traceback suppressed from the response body."
        return JSONResponse(body, status_code=500, headers={REQUEST_ID_HEADER: request_id})

    duration_ms = round((time.perf_counter() - started) * 1000, 2)
    response.headers[REQUEST_ID_HEADER] = request_id
    log.info(
        "request.completed",
        method=request.method,
        path=request.url.path,
        status=response.status_code,
        duration_ms=duration_ms,
    )
    return response


app.include_router(health_router, prefix="/v1", tags=["operations"])
