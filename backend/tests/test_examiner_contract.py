"""Offline tests for the examiner's two hard guarantees.

These need no network and no key, so they run in CI on every commit — which
matters, because they cover the invariant the product is sold on. A live test
that only runs when a key is present is not where you protect a promise.
"""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.services.examiner import (
    Evaluation,
    Examiner,
    ExaminerError,
    Passage,
    UngroundedCitationError,
    _extract_json,
    _render,
)

PASSAGES = [
    Passage("0x1F4", "Deadlock-free by construction when …", 47, "OS.pdf"),
    Passage("0x1F5", "The four Coffman conditions …", 46, "OS.pdf"),
]
ALLOWED = {p.chunk_id for p in PASSAGES}


class TestCitationVerification:
    """A fabricated citation must never reach a student."""

    def test_citations_inside_the_supplied_set_pass(self) -> None:
        Examiner._verify_citations(["0x1F4"], ALLOWED, "question")
        Examiner._verify_citations(["0x1F4", "0x1F5"], ALLOWED, "question")

    def test_an_invented_chunk_id_is_rejected(self) -> None:
        # The realistic failure: the model emits a plausible-looking id it was
        # never shown. A student turning to that page finds nothing.
        with pytest.raises(UngroundedCitationError, match="0x999"):
            Examiner._verify_citations(["0x1F4", "0x999"], ALLOWED, "gap")

    def test_the_error_names_every_invented_id(self) -> None:
        with pytest.raises(UngroundedCitationError) as e:
            Examiner._verify_citations(["0xAAA", "0xBBB"], ALLOWED, "gap")
        assert "0xAAA" in str(e.value)
        assert "0xBBB" in str(e.value)


class TestJsonExtraction:
    """Models wrap, prefix and ramble. The parser copes without a retry."""

    def test_plain_object(self) -> None:
        assert _extract_json('{"a":1}') == {"a": 1}

    def test_markdown_fence_is_stripped(self) -> None:
        assert _extract_json('```json\n{"a":1}\n```') == {"a": 1}
        assert _extract_json('```\n{"a":1}\n```') == {"a": 1}

    def test_leading_reasoning_is_skipped(self) -> None:
        # Observed live: nemotron emitted its chain of thought before the
        # object rather than replying with JSON only.
        raw = 'The user wants a question. Let me think.\n{"question":"why?"}'
        assert _extract_json(raw) == {"question": "why?"}

    def test_a_bare_array_is_not_an_object(self) -> None:
        with pytest.raises(ExaminerError):
            _extract_json("[1,2,3]")

    def test_prose_with_no_object_raises(self) -> None:
        with pytest.raises(ExaminerError, match="no JSON object"):
            _extract_json("I cannot answer that.")


class TestRubric:
    """The composite has to discriminate, or the rubric is decoration."""

    @staticmethod
    def _eval(**scores: int) -> Evaluation:
        base = dict(
            concept_accuracy=50,
            completeness=50,
            technical_vocabulary=50,
            logical_flow=50,
            depth=50,
            examples_used=50,
        )
        base.update(scores)
        return Evaluation.model_validate(
            {
                "verdict": "adequate",
                "note": "a note long enough to pass validation",
                "rubric": base,
                "gaps": [],
            }
        )

    def test_all_fifties_is_fifty(self) -> None:
        assert self._eval().rubric.composite == 50

    def test_concept_accuracy_outweighs_examples(self) -> None:
        # 30% vs 5%: knowing the concept must matter more than citing an
        # example of it.
        accurate = self._eval(concept_accuracy=100, examples_used=0)
        illustrated = self._eval(concept_accuracy=0, examples_used=100)
        assert accurate.rubric.composite > illustrated.rubric.composite

    def test_confidence_is_not_a_rubric_field(self) -> None:
        # Prosodic, so it cannot come from typed text (audit AI-02).
        assert "confidence" not in Evaluation.model_fields["rubric"].annotation.model_fields

    def test_a_gap_without_a_citation_is_invalid(self) -> None:
        with pytest.raises(ValidationError):
            Evaluation.model_validate(
                {
                    "verdict": "adequate",
                    "note": "a note long enough to pass validation",
                    "rubric": {
                        "concept_accuracy": 50,
                        "completeness": 50,
                        "technical_vocabulary": 50,
                        "logical_flow": 50,
                        "depth": 50,
                        "examples_used": 50,
                    },
                    "gaps": [{"title": "Missing", "body": "something here", "cites": []}],
                }
            )


class TestPassageRendering:
    def test_every_chunk_id_reaches_the_prompt(self) -> None:
        # The model can only cite what it can see labelled.
        rendered = _render(PASSAGES)
        for p in PASSAGES:
            assert f"chunk_id={p.chunk_id}" in rendered

    def test_page_number_is_included_when_known(self) -> None:
        assert "p.47" in _render(PASSAGES[:1])

    def test_missing_page_number_is_omitted_not_faked(self) -> None:
        rendered = _render([Passage("0x1", "text", None, "OS.pdf")])
        assert "p.None" not in rendered
        assert "chunk_id=0x1" in rendered
