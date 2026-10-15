"""Liveness and readiness probes.

Audit API-04: the architecture specifies a managed container host and no
health endpoint. These are not the same check and conflating them causes an
orchestrator to kill a healthy process because its database blipped:

  /v1/health  liveness  — the process is running. No dependencies touched.
                          A failure here means restart me.
  /v1/ready   readiness — dependencies are reachable. A failure here means
                          stop sending me traffic, but do not restart me.
"""

from __future__ import annotations

import time
from typing import Any

import asyncpg
from fastapi import APIRouter, Request, Response, status

from app.core.logging import get_logger

router = APIRouter()
log = get_logger(__name__)


@router.get("/health", summary="Liveness probe")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/ready", summary="Readiness probe")
async def ready(request: Request, response: Response) -> dict[str, Any]:
    checks: dict[str, Any] = {}
    healthy = True

    pool: asyncpg.Pool | None = getattr(request.app.state, "pool", None)
    if pool is None:
        checks["database"] = {"status": "unavailable", "detail": "pool not initialised"}
        healthy = False
    else:
        started = time.perf_counter()
        try:
            async with pool.acquire() as conn:
                await conn.fetchval("select 1")
            checks["database"] = {
                "status": "ok",
                "latency_ms": round((time.perf_counter() - started) * 1000, 2),
            }
        except Exception as exc:
            log.warning("readiness.database_failed", error=str(exc))
            checks["database"] = {"status": "error", "detail": exc.__class__.__name__}
            healthy = False

    if not healthy:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE

    return {"status": "ready" if healthy else "not_ready", "checks": checks}
