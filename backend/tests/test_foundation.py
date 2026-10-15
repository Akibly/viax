"""Day 1 foundation tests: configuration refuses to boot broken, probes are
honest, and request IDs are threaded.

These are deliberately unglamorous. They cover the failures that are silent
in production: a service that starts without a key, a readiness probe that
returns 200 while the database is unreachable, and a log line with no way
back to the request that produced it.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.core.config import Settings, get_settings
from app.core.logging import bind_request, configure_logging, current_request_id, new_request_id

REQUIRED = {
    "VIVAX_SUPABASE_URL": "http://127.0.0.1:55321",
    "VIVAX_SUPABASE_ANON_KEY": "anon-key",
    "VIVAX_SUPABASE_SERVICE_ROLE_KEY": "service-key",
    "VIVAX_DATABASE_URL": "postgresql://postgres:postgres@127.0.0.1:55322/postgres",
    "VIVAX_OPENROUTER_API_KEY": "sk-or-test",
}


@pytest.fixture(autouse=True)
def _clean_env(monkeypatch: pytest.MonkeyPatch, tmp_path):  # type: ignore[no-untyped-def]
    """Settings reads a .env relative to the cwd; run from a directory without one.

    The cache is cleared on the way out as well as in. `get_settings` is
    lru_cached, so without the teardown these tests leave placeholder
    credentials cached for the rest of the session and the integration tests
    fail against Storage with a 401 that looks like an infrastructure problem.
    """
    monkeypatch.chdir(tmp_path)
    for key in [*REQUIRED, "VIVAX_ENVIRONMENT"]:
        monkeypatch.delenv(key, raising=False)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _configure(monkeypatch: pytest.MonkeyPatch, **overrides: str) -> Settings:
    for key, value in {**REQUIRED, **overrides}.items():
        monkeypatch.setenv(key, value)
    monkeypatch.setenv("VIVAX_ENVIRONMENT", overrides.get("VIVAX_ENVIRONMENT", "ci"))
    get_settings.cache_clear()
    return get_settings()


class TestConfiguration:
    def test_missing_required_settings_exit_with_config_code(
        self, capsys: pytest.CaptureFixture[str]
    ) -> None:
        with pytest.raises(SystemExit) as exc:
            get_settings()

        assert exc.value.code == 78, "should exit EX_CONFIG, not crash with a traceback"
        message = capsys.readouterr().err
        assert "VIVAX_SUPABASE_URL" in message, "must name what is missing"

    def test_valid_configuration_loads(self, monkeypatch: pytest.MonkeyPatch) -> None:
        settings = _configure(monkeypatch)
        assert settings.evaluation_model == "minimax/minimax-m3:free"
        assert settings.embedding_dimension == 1024

    def test_secrets_do_not_render_in_repr(self, monkeypatch: pytest.MonkeyPatch) -> None:
        settings = _configure(monkeypatch)
        assert "service-key" not in repr(settings)
        assert settings.supabase_service_role_key.get_secret_value() == "service-key"

    def test_trailing_slash_is_normalised(self, monkeypatch: pytest.MonkeyPatch) -> None:
        settings = _configure(monkeypatch, VIVAX_SUPABASE_URL="https://x.supabase.co/")
        assert settings.supabase_url == "https://x.supabase.co"

    def test_schemeless_url_is_rejected(
        self, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
    ) -> None:
        """Invalid config fails as loudly as missing config, and says which setting."""
        with pytest.raises(SystemExit) as exc:
            _configure(monkeypatch, VIVAX_SUPABASE_URL="x.supabase.co")

        assert exc.value.code == 78
        message = capsys.readouterr().err
        assert "VIVAX_SUPABASE_URL" in message
        assert "scheme" in message

    def test_upload_cap_matches_the_database_constraint(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """A limit enforced in one layer and not the other is a 500, not a 413."""
        settings = _configure(monkeypatch)
        assert settings.max_upload_bytes == 26_214_400
        assert settings.max_document_pages == 300

    def test_confidence_is_excluded_from_the_composite_by_default(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Audit AI-02 / ADR-0001: prosodic, so not scorable from typed text."""
        assert _configure(monkeypatch).score_confidence_dimension is False

    def test_production_does_not_expose_error_detail(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        assert _configure(monkeypatch, VIVAX_ENVIRONMENT="production").debug_errors is False
        assert _configure(monkeypatch, VIVAX_ENVIRONMENT="local").debug_errors is True


class TestLoggingContext:
    def test_request_id_is_bound_and_readable(self) -> None:
        configure_logging("INFO", "console", "vivax-test")
        rid = new_request_id()
        bind_request(rid, user_id="11111111-1111-1111-1111-111111111111")
        assert current_request_id() == rid

    def test_ids_are_unique(self) -> None:
        assert len({new_request_id() for _ in range(1000)}) == 1000


class TestProbes:
    """Liveness must not touch dependencies; readiness must not lie."""

    def test_liveness_needs_no_database(self, monkeypatch: pytest.MonkeyPatch) -> None:
        _configure(monkeypatch)
        from fastapi import FastAPI

        from app.api.v1.health import router

        app = FastAPI()
        app.include_router(router, prefix="/v1")

        with TestClient(app) as client:
            response = client.get("/v1/health")

        assert response.status_code == 200
        assert response.json() == {"status": "ok"}

    def test_readiness_reports_503_when_the_pool_is_missing(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        _configure(monkeypatch)
        from fastapi import FastAPI

        from app.api.v1.health import router

        app = FastAPI()
        app.include_router(router, prefix="/v1")

        with TestClient(app) as client:
            response = client.get("/v1/ready")

        assert response.status_code == 503, "an unready service must not report 200"
        body = response.json()
        assert body["status"] == "not_ready"
        assert body["checks"]["database"]["status"] == "unavailable"
