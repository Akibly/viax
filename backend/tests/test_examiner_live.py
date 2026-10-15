"""Live examiner tests against OpenRouter.

Marked `live` and skipped unless VIVAX_OPENROUTER_API_KEY is set, so CI and
offline runs stay green. These are the only tests that prove the thing the
product is actually sold on — a question grounded in the student's own text,
and a citation that cannot be faked.
"""

from __future__ import annotations

import os

import httpx
import pytest

from app.core.config import Settings
from app.services.examiner import (
    Evaluation,
    Examiner,
    ExaminerError,
    GeneratedQuestion,
    Passage,
)

pytestmark = pytest.mark.live

PASSAGES = [
    Passage(
        chunk_id="0x1F4",
        content=(
            "If the total number of resource units exceeds the sum of the "
            "maximum needs of all processes minus the number of processes, "
            "the system is deadlock-free by construction."
        ),
        page_number=47,
        document_title="OperatingSystems.pdf",
    ),
    Passage(
        chunk_id="0x1F5",
        content=(
            "A deadlock requires all four Coffman conditions to hold "
            "simultaneously: mutual exclusion, hold and wait, no preemption, "
            "and circular wait."
        ),
        page_number=46,
        document_title="OperatingSystems.pdf",
    ),
]


def _settings() -> Settings:
    os.environ.setdefault("VIVAX_SUPABASE_URL", "https://x.supabase.co")
    os.environ.setdefault("VIVAX_SUPABASE_ANON_KEY", "a")
    os.environ.setdefault("VIVAX_SUPABASE_SERVICE_ROLE_KEY", "b")
    os.environ.setdefault(
        "VIVAX_DATABASE_URL", "postgresql://u:p@h:5432/d"
    )
    return Settings()


@pytest.fixture
def settings() -> Settings:
    if not os.environ.get("VIVAX_OPENROUTER_API_KEY"):
        pytest.skip("VIVAX_OPENROUTER_API_KEY not set")
    return _settings()


@pytest.mark.asyncio
async def test_generates_a_question_grounded_in_the_passages(
    settings: Settings,
) -> None:
    async with httpx.AsyncClient() as http:
        q = await Examiner(settings, http).generate_question(PASSAGES)

    assert isinstance(q, GeneratedQuestion)
    # Every cited chunk must be one we supplied. This is the product promise.
    assert set(q.cites) <= {p.chunk_id for p in PASSAGES}
    assert q.question.strip().endswith("?")


@pytest.mark.asyncio
async def test_evaluation_separates_a_weak_answer_from_a_strong_one(
    settings: Settings,
) -> None:
    weak = "Deadlock is when processes wait for each other in a circle."
    strong = (
        "Each process may request at most one unit. Deadlock needs every "
        "process holding one while waiting for another, so with three units "
        "the fourth always finds one free. Generally the system is safe when "
        "total units exceed the sum of maximum needs minus the process count."
    )
    question = (
        "A system has four processes and three identical resource units. "
        "What is the maximum each may request while the system still cannot "
        "deadlock, and why?"
    )

    async with httpx.AsyncClient() as http:
        ex = Examiner(settings, http)
        weak_eval = await ex.evaluate(question, weak, PASSAGES)
        strong_eval = await ex.evaluate(question, strong, PASSAGES)

    assert isinstance(weak_eval, Evaluation)
    # The rubric has to actually discriminate, or it is decoration.
    assert strong_eval.rubric.composite > weak_eval.rubric.composite

    # Confidence is not a field at all — it cannot be scored from text.
    assert not hasattr(weak_eval.rubric, "confidence")

    # Any gap must point at a passage we supplied.
    allowed = {p.chunk_id for p in PASSAGES}
    for ev in (weak_eval, strong_eval):
        for gap in ev.gaps:
            assert set(gap.cites) <= allowed


@pytest.mark.asyncio
async def test_empty_answer_is_refused(settings: Settings) -> None:
    async with httpx.AsyncClient() as http:
        with pytest.raises(ExaminerError):
            await Examiner(settings, http).evaluate("Q?", "   ", PASSAGES)
