"""Application configuration.

Audit OPS-04: the corpus specified "secure secrets" and no validation. A
service that boots with a missing key and fails on the first request that
needs it is worse than one that refuses to boot — the failure surfaces in
front of a user instead of in front of a deploy.

Everything required is validated at import time and the process exits with a
readable message naming exactly what is missing.
"""

from __future__ import annotations

import sys
from enum import StrEnum
from functools import lru_cache
from typing import Annotated, Literal

from pydantic import (
    Field,
    PostgresDsn,
    SecretStr,
    ValidationError,
    field_validator,
    model_validator,
)
from pydantic_settings import BaseSettings, SettingsConfigDict


class Environment(StrEnum):
    LOCAL = "local"
    CI = "ci"
    STAGING = "staging"
    PRODUCTION = "production"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        env_prefix="VIVAX_",
        extra="ignore",
        frozen=True,
    )

    # -- Runtime ------------------------------------------------------------
    environment: Environment = Environment.LOCAL
    service_name: str = "vivax-api"
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR"] = "INFO"
    log_format: Literal["json", "console"] = "json"

    # -- Supabase -----------------------------------------------------------
    supabase_url: str
    supabase_anon_key: SecretStr
    # RLS does not apply to this key. Every query made with it must scope
    # itself explicitly; see ADR-0001 and the RLS migration header.
    supabase_service_role_key: SecretStr
    database_url: PostgresDsn

    # -- Model provider -----------------------------------------------------
    # OpenRouter is the default because it fronts many providers behind one
    # key, which is what makes the fallback chain below possible at all.
    llm_provider: Literal["openrouter", "anthropic"] = "openrouter"
    openrouter_api_key: SecretStr | None = None
    anthropic_api_key: SecretStr | None = None

    openrouter_base_url: str = "https://openrouter.ai/api/v1"

    # Evaluation is the call where correctness matters most and volume is
    # lowest, so it does not get downgraded for cost without a measured
    # reason (audit AI-09).
    evaluation_model: str = "minimax/minimax-m3:free"
    generation_model: str = "minimax/minimax-m3:free"

    # Free models rate-limit without warning — a 429 was observed on the
    # second test call. A viva that dies mid-question is worse than a slower
    # one, so every request walks this list until something answers.
    model_fallbacks: tuple[str, ...] = (
        "minimax/minimax-m3:free",
        "thinkingmachines/inkling:free",
        "nvidia/nemotron-3.5-lightning:free",
    )

    # -- Guardrails ---------------------------------------------------------
    # Audit SEC-04: unbounded spend is a denial-of-wallet vector, and the SRS
    # requires operating inside free-tier quotas. Enforced before the call,
    # not after.
    daily_token_budget_per_user: Annotated[int, Field(gt=0)] = 250_000
    max_questions_per_session: Annotated[int, Field(gt=0, le=50)] = 20
    # 25 MiB. Must stay in step with the document_size_limit CHECK constraint.
    max_upload_bytes: Annotated[int, Field(gt=0)] = 26_214_400
    max_document_pages: Annotated[int, Field(gt=0)] = 300

    # The provider's key is required at boot, not at first request. A service
    # that starts without it fails in front of a student instead of in front
    # of a deploy — which is the whole point of validating here (OPS-04).
    @model_validator(mode="after")
    def _provider_key_present(self) -> Settings:
        needed = {
            "openrouter": ("openrouter_api_key", "VIVAX_OPENROUTER_API_KEY"),
            "anthropic": ("anthropic_api_key", "VIVAX_ANTHROPIC_API_KEY"),
        }[self.llm_provider]
        if getattr(self, needed[0]) is None:
            raise ValueError(
                f"llm_provider is '{self.llm_provider}' but {needed[1]} is not set"
            )
        return self

    # -- Retrieval ----------------------------------------------------------
    embedding_dimension: Literal[1024] = 1024
    retrieval_top_k: Annotated[int, Field(gt=0, le=100)] = 20
    rerank_top_n: Annotated[int, Field(gt=0, le=50)] = 6
    # Below this many concepts, refuse to start a session rather than let the
    # model invent questions the notes cannot support (audit AI-07).
    min_concepts_for_session: Annotated[int, Field(ge=1)] = 3

    # -- Evaluation ---------------------------------------------------------
    rubric_version: str = "rubric-v1"
    # Confidence is prosodic and cannot be scored from typed text. It stays
    # out of the composite until voice ships (audit AI-02, ADR-0001).
    score_confidence_dimension: bool = False
    # Release gate: the eval suite fails the build below this agreement with
    # the human-scored gold set (audit AI-01).
    min_gold_set_kappa: float = 0.60

    @field_validator("supabase_url")
    @classmethod
    def _must_be_https_off_localhost(cls, v: str) -> str:
        if not v.startswith(("http://", "https://")):
            raise ValueError("must be a full URL including scheme")
        return v.rstrip("/")

    @property
    def is_production(self) -> bool:
        return self.environment is Environment.PRODUCTION

    @property
    def debug_errors(self) -> bool:
        """Never leak internals to a client in production."""
        return self.environment in (Environment.LOCAL, Environment.CI)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    try:
        return Settings()
    except ValidationError as exc:
        missing = [
            f"VIVAX_{'_'.join(str(p) for p in err['loc']).upper()}"
            for err in exc.errors()
            if err["type"] == "missing"
        ]
        invalid = [
            f"VIVAX_{'_'.join(str(p) for p in err['loc']).upper()}: {err['msg']}"
            for err in exc.errors()
            if err["type"] != "missing"
        ]
        lines = ["", "VivaX cannot start: configuration is incomplete.", ""]
        if missing:
            lines += ["  Missing required settings:", *(f"    - {n}" for n in missing), ""]
        if invalid:
            lines += ["  Invalid settings:", *(f"    - {n}" for n in invalid), ""]
        lines += ["  Copy .env.example to .env and fill it in.", ""]
        print("\n".join(lines), file=sys.stderr)
        raise SystemExit(78) from exc  # EX_CONFIG
