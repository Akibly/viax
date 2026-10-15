"""The examiner: grounded question generation and answer evaluation.

Two things make this different from a chat wrapper, and both are enforced here
rather than requested politely in a prompt.

**Citations are validated, not trusted.** A model asked to emit a page number
as free text will invent a plausible one, and a fabricated citation is worse
than none — the student turns to page 47, finds nothing, and stops believing
the product. So the model may only cite `chunk_id` values drawn from the
context it was given, and any citation outside that set is rejected before it
can reach a caller (audit AI-04).

**Free models rate-limit without warning.** A 429 was observed on the second
call during provider testing. A viva that dies mid-question is a worse failure
than a slow one, so every request walks a fallback chain and only raises once
every model has refused.
"""

from __future__ import annotations

import asyncio
import json
import logging
import re
from dataclasses import dataclass
from typing import Any, Final

import httpx
from pydantic import BaseModel, Field, ValidationError

from app.core.config import Settings

logger = logging.getLogger(__name__)

# Models sometimes wrap JSON in a fence despite being told not to. Stripping it
# is cheaper and more reliable than another round-trip.
_FENCE: Final = re.compile(r"^\s*```(?:json)?\s*(.*?)\s*```\s*$", re.S)

_RETRYABLE: Final = frozenset({408, 429, 500, 502, 503, 504})


class ExaminerError(RuntimeError):
    """Every candidate model failed, or the reply could not be trusted."""


class UngroundedCitationError(ExaminerError):
    """The model cited a chunk it was never shown."""


@dataclass(frozen=True, slots=True)
class Passage:
    """One retrieved chunk offered to the model as grounding."""

    chunk_id: str
    content: str
    page_number: int | None
    document_title: str


class GeneratedQuestion(BaseModel):
    question: str = Field(min_length=12, max_length=600)
    # What a complete answer must contain. Drives the gap analysis later, so
    # an empty list is not acceptable.
    expects: list[str] = Field(min_length=1, max_length=8)
    cites: list[str] = Field(min_length=1, max_length=6)
    difficulty: int = Field(ge=1, le=5)


class RubricScore(BaseModel):
    concept_accuracy: int = Field(ge=0, le=100)
    completeness: int = Field(ge=0, le=100)
    technical_vocabulary: int = Field(ge=0, le=100)
    logical_flow: int = Field(ge=0, le=100)
    depth: int = Field(ge=0, le=100)
    examples_used: int = Field(ge=0, le=100)

    # Confidence is deliberately absent. It is prosodic — carried by pace and
    # hesitation — and scoring it from typed text measures hedging vocabulary,
    # penalising exactly the students the product exists to help (audit
    # AI-02). It is supplied by the speech pipeline or not at all.

    @property
    def composite(self) -> int:
        weights = {
            "concept_accuracy": 0.30,
            "completeness": 0.20,
            "depth": 0.20,
            "logical_flow": 0.15,
            "technical_vocabulary": 0.10,
            "examples_used": 0.05,
        }
        total: float = sum(float(getattr(self, k)) * w for k, w in weights.items())
        return round(total)


class Gap(BaseModel):
    title: str = Field(min_length=3, max_length=160)
    body: str = Field(min_length=10, max_length=800)
    cites: list[str] = Field(min_length=1, max_length=4)


class Evaluation(BaseModel):
    verdict: str = Field(min_length=3, max_length=160)
    note: str = Field(min_length=10, max_length=1200)
    rubric: RubricScore
    gaps: list[Gap] = Field(default_factory=list, max_length=5)


_GENERATE_SYSTEM = """You are a viva voce examiner conducting an oral examination.

Rules you must not break:
- Ask about material present in the PASSAGES only. Never use outside knowledge.
- Cite the chunk_id of every passage your question draws on.
- One question. No preamble, no follow-up, no explanation.
- A viva question probes understanding, not recall. Prefer "why" and "under
  what conditions" over "define".

Reply with minified JSON only, no markdown fence:
{"question":string,"expects":[string],"cites":[chunk_id],"difficulty":1-5}"""

_EVALUATE_SYSTEM = """You are marking a student's spoken viva answer.

Rules you must not break:
- Judge only against the PASSAGES. If the answer is right but goes beyond
  them, do not penalise it; if it contradicts them, do.
- Every gap must cite the chunk_id proving it is a gap.
- Do not score confidence. You cannot hear the student.
- Be specific. "Needs more detail" is useless to a student.

Reply with minified JSON only, no markdown fence:
{"verdict":string,"note":string,
 "rubric":{"concept_accuracy":0-100,"completeness":0-100,
           "technical_vocabulary":0-100,"logical_flow":0-100,
           "depth":0-100,"examples_used":0-100},
 "gaps":[{"title":string,"body":string,"cites":[chunk_id]}]}"""


def _render(passages: list[Passage]) -> str:
    return "\n\n".join(
        f"[chunk_id={p.chunk_id} | {p.document_title}"
        f"{f' p.{p.page_number}' if p.page_number is not None else ''}]\n{p.content}"
        for p in passages
    )


def _extract_json(raw: str) -> dict[str, Any]:
    text = raw.strip()
    if m := _FENCE.match(text):
        text = m.group(1)
    try:
        parsed = json.loads(text)
        if not isinstance(parsed, dict):
            raise ExaminerError(f"expected a JSON object, got {type(parsed).__name__}")
        return parsed
    except json.JSONDecodeError:
        # Some models prepend reasoning before the object. Take the last
        # balanced {...} rather than giving up on an otherwise good answer.
        start, depth = None, 0
        for i, ch in enumerate(text):
            if ch == "{":
                if depth == 0:
                    start = i
                depth += 1
            elif ch == "}" and depth:
                depth -= 1
                if depth == 0 and start is not None:
                    try:
                        candidate = json.loads(text[start : i + 1])
                    except json.JSONDecodeError:
                        start = None
                    else:
                        if isinstance(candidate, dict):
                            return candidate
                        start = None
        raise ExaminerError(f"no JSON object in reply: {raw[:200]!r}") from None


class Examiner:
    """Talks to OpenRouter, and refuses to pass on anything it cannot verify."""

    def __init__(self, settings: Settings, client: httpx.AsyncClient) -> None:
        self._s = settings
        self._http = client
        key = settings.openrouter_api_key
        if key is None:  # pragma: no cover - config validator prevents this
            raise ExaminerError("openrouter_api_key is not configured")
        self._headers = {
            "Authorization": f"Bearer {key.get_secret_value()}",
            "Content-Type": "application/json",
            # OpenRouter attributes usage to these; without them requests are
            # ranked lower and are first to be shed under load.
            "HTTP-Referer": "https://vivax.app",
            "X-Title": "VivaX",
        }

    async def _chat(self, system: str, user: str, *, temperature: float) -> str:
        """Walk the fallback chain. Raises only when every model refuses."""
        # The configured model first, then the rest of the chain, deduplicated
        # while preserving order.
        chain: list[str] = []
        for m in (self._s.generation_model, *self._s.model_fallbacks):
            if m not in chain:
                chain.append(m)

        last: str = "no models configured"
        for model in chain:
            for attempt in range(3):
                try:
                    r = await self._http.post(
                        f"{self._s.openrouter_base_url}/chat/completions",
                        headers=self._headers,
                        json={
                            "model": model,
                            "messages": [
                                {"role": "system", "content": system},
                                {"role": "user", "content": user},
                            ],
                            "temperature": temperature,
                            "max_tokens": 1200,
                        },
                        timeout=90.0,
                    )
                except httpx.RequestError as e:
                    last = f"{model}: {type(e).__name__}"
                    await asyncio.sleep(1.5 * (attempt + 1))
                    continue

                if r.status_code in _RETRYABLE:
                    last = f"{model}: HTTP {r.status_code}"
                    logger.warning("examiner retrying", extra={"model": model,
                                                               "status": r.status_code})
                    # 429 means this model is shedding load; move on rather
                    # than hammer it.
                    if r.status_code == 429:
                        break
                    await asyncio.sleep(1.5 * (attempt + 1))
                    continue

                if r.status_code >= 400:
                    last = f"{model}: HTTP {r.status_code} {r.text[:160]}"
                    break  # not retryable, try the next model

                body = r.json()
                if "error" in body:
                    last = f"{model}: {str(body['error'])[:160]}"
                    break
                content = body["choices"][0]["message"]["content"]
                if isinstance(content, str) and content.strip():
                    return content
                last = f"{model}: empty reply"
                break

        raise ExaminerError(f"every model failed; last error was {last}")

    @staticmethod
    def _verify_citations(cited: list[str], allowed: set[str], what: str) -> None:
        invented = [c for c in cited if c not in allowed]
        if invented:
            raise UngroundedCitationError(
                f"{what} cited chunk(s) it was never shown: {invented}"
            )

    async def generate_question(
        self, passages: list[Passage], *, difficulty: int = 2
    ) -> GeneratedQuestion:
        if not passages:
            raise ExaminerError("cannot generate a question with no passages")

        raw = await self._chat(
            _GENERATE_SYSTEM,
            f"PASSAGES:\n{_render(passages)}\n\n"
            f"Ask one difficulty-{difficulty} viva question.",
            temperature=0.4,
        )
        try:
            q = GeneratedQuestion.model_validate(_extract_json(raw))
        except ValidationError as e:
            raise ExaminerError(f"question failed validation: {e}") from e

        self._verify_citations(q.cites, {p.chunk_id for p in passages}, "question")
        return q

    async def evaluate(
        self, question: str, answer: str, passages: list[Passage]
    ) -> Evaluation:
        if not answer.strip():
            raise ExaminerError("cannot evaluate an empty answer")

        raw = await self._chat(
            _EVALUATE_SYSTEM,
            f"PASSAGES:\n{_render(passages)}\n\n"
            f"QUESTION: {question}\n\nSTUDENT ANSWER: {answer}",
            temperature=0.1,
        )
        try:
            ev = Evaluation.model_validate(_extract_json(raw))
        except ValidationError as e:
            raise ExaminerError(f"evaluation failed validation: {e}") from e

        allowed = {p.chunk_id for p in passages}
        for gap in ev.gaps:
            self._verify_citations(gap.cites, allowed, "gap")
        return ev
