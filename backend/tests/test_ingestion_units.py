"""Extraction and embedding guarantees.

The failures these cover are the quiet ones: a scan silently ingested as an
empty document, a dimension mismatch that degrades retrieval without erroring,
and a test double reaching production where it would look like a quality
problem rather than a configuration one.
"""

from __future__ import annotations

from io import BytesIO
from zipfile import ZIP_DEFLATED, ZipFile

import pytest

from app.domain.embedding import (
    EMBEDDING_DIMENSION,
    DeterministicEmbedder,
    build_embedder,
    to_pgvector,
)
from app.domain.extraction import (
    ExtractionError,
    ExtractionFailed,
    extract,
    extract_docx,
    extract_pdf,
    extract_pptx,
    extract_text_file,
)


def _pdf(pages: list[str]) -> bytes:
    """A real PDF with a real text layer, built with pypdf."""
    from pypdf import PdfWriter

    try:
        from reportlab.pdfgen import canvas  # noqa: F401
    except ImportError:
        pytest.skip("reportlab not installed; PDF text-layer fixtures unavailable")

    from reportlab.lib.pagesizes import letter
    from reportlab.pdfgen.canvas import Canvas

    buffer = BytesIO()
    pdf = Canvas(buffer, pagesize=letter)
    for text in pages:
        y = 750
        for line in text.splitlines():
            pdf.drawString(72, y, line)
            y -= 14
        pdf.showPage()
    pdf.save()
    buffer.seek(0)

    writer = PdfWriter(clone_from=buffer)
    out = BytesIO()
    writer.write(out)
    return out.getvalue()


def _blank_pdf(page_count: int) -> bytes:
    """A PDF with pages but no text — what a scan looks like to pypdf."""
    from pypdf import PdfWriter

    writer = PdfWriter()
    for _ in range(page_count):
        writer.add_blank_page(width=612, height=792)
    out = BytesIO()
    writer.write(out)
    return out.getvalue()


class TestPdfExtraction:
    def test_a_scan_is_routed_to_ocr_not_reported_as_empty(self) -> None:
        """The important distinction: the file is fine, it just has no text
        layer. Failing it outright loses a legitimate upload."""
        result = extract_pdf(_blank_pdf(3), max_pages=300)
        assert result.needs_ocr is True
        assert result.page_count == 3

    def test_page_limit_is_enforced_with_actionable_advice(self) -> None:
        with pytest.raises(ExtractionFailed) as exc:
            extract_pdf(_blank_pdf(5), max_pages=2)
        assert exc.value.code is ExtractionError.TOO_MANY_PAGES
        assert "2-page limit" in exc.value.advice
        assert "Split it into chapters" in exc.value.advice

    def test_corrupt_input_is_unreadable_not_a_crash(self) -> None:
        with pytest.raises(ExtractionFailed) as exc:
            extract_pdf(b"this is not a pdf at all", max_pages=300)
        assert exc.value.code is ExtractionError.UNREADABLE
        assert exc.value.advice

    def test_every_failure_carries_student_facing_advice(self) -> None:
        """A `failed` status with no explanation is the silent bad result the
        PRD's risk table promised to avoid."""
        for code in ExtractionError:
            failure = ExtractionFailed(code, limit=300)
            assert failure.advice.strip()
            assert failure.code is code

    def test_text_layer_is_extracted_with_correct_page_numbers(self) -> None:
        data = _pdf(["Deadlock requires circular wait.", "Paging uses fixed size pages."])
        result = extract_pdf(data, max_pages=300)
        assert result.needs_ocr is False
        assert [p.number for p in result.pages] == [1, 2]
        assert "Deadlock" in result.pages[0].text
        assert "Paging" in result.pages[1].text


class TestTextExtraction:
    def test_plain_text_becomes_one_page(self) -> None:
        result = extract_text_file(b"A deadlock blocks progress indefinitely.")
        assert result.page_count == 1
        assert result.pages[0].number == 1

    def test_form_feeds_paginate(self) -> None:
        result = extract_text_file(b"page one content\x0cpage two content")
        assert [p.number for p in result.pages] == [1, 2]

    def test_empty_file_is_rejected(self) -> None:
        with pytest.raises(ExtractionFailed) as exc:
            extract_text_file(b"   \n\n  ")
        assert exc.value.code is ExtractionError.EMPTY

    def test_non_utf8_falls_back_rather_than_failing(self) -> None:
        result = extract_text_file("Résumé of scheduling".encode("latin-1"))
        assert result.pages

    def test_hyphenation_across_line_breaks_is_repaired(self) -> None:
        """'sched-\\nuler' must not become two unsearchable fragments."""
        result = extract_text_file(b"The sched-\nuler picks a process.")
        assert "scheduler" in result.pages[0].text

    def test_ragged_pdf_line_breaks_are_rejoined(self) -> None:
        result = extract_text_file(b"A deadlock is a situation in which\ntwo processes wait.")
        assert "which two processes" in result.pages[0].text

    def test_paragraph_breaks_survive(self) -> None:
        result = extract_text_file(b"First paragraph.\n\nSecond paragraph.")
        assert "\n" in result.pages[0].text


def _office_file(entries: dict[str, str]) -> bytes:
    output = BytesIO()
    with ZipFile(output, "w", ZIP_DEFLATED) as archive:
        for name, content in entries.items():
            archive.writestr(name, content)
    return output.getvalue()


class TestOfficeExtraction:
    def test_docx_text_is_extracted(self) -> None:
        data = _office_file({
            "word/document.xml": (
                '<w:document xmlns:w="urn:w"><w:body><w:p><w:r>'
                '<w:t>Grounded Word notes</w:t></w:r></w:p></w:body></w:document>'
            )
        })
        result = extract_docx(data)
        assert result.pages[0].text == "Grounded Word notes"

    def test_pptx_preserves_numeric_slide_order(self) -> None:
        def slide(text: str) -> str:
            return f'<p:sld xmlns:p="urn:p" xmlns:a="urn:a"><a:t>{text}</a:t></p:sld>'

        data = _office_file({
            "ppt/slides/slide10.xml": slide("Tenth"),
            "ppt/slides/slide2.xml": slide("Second"),
            "ppt/slides/slide1.xml": slide("First"),
        })
        result = extract_pptx(data, max_pages=20)
        assert [page.text for page in result.pages] == ["First", "Second", "Tenth"]
        assert [page.number for page in result.pages] == [1, 2, 3]

    def test_corrupt_office_file_is_actionable(self) -> None:
        with pytest.raises(ExtractionFailed) as exc:
            extract_docx(b"not a zip")
        assert exc.value.code is ExtractionError.UNREADABLE


class TestDispatch:
    def test_images_are_always_ocr_work(self) -> None:
        result = extract(b"\x89PNG fake", mime_type="image/png", max_pages=300)
        assert result.needs_ocr is True

    def test_unsupported_type_is_named(self) -> None:
        with pytest.raises(ExtractionFailed) as exc:
            extract(b"...", mime_type="application/zip", max_pages=300)
        assert exc.value.code is ExtractionError.UNSUPPORTED_TYPE


class TestEmbedding:
    async def test_dimension_matches_the_column(self) -> None:
        vectors = await DeterministicEmbedder().embed(["deadlock", "paging"])
        assert all(len(v) == EMBEDDING_DIMENSION for v in vectors)

    async def test_output_is_deterministic(self) -> None:
        first = await DeterministicEmbedder().embed(["deadlock"])
        second = await DeterministicEmbedder().embed(["deadlock"])
        assert first == second

    async def test_distinct_inputs_give_distinct_vectors(self) -> None:
        vectors = await DeterministicEmbedder().embed(["deadlock", "paging"])
        assert vectors[0] != vectors[1]

    async def test_vectors_are_normalised(self) -> None:
        (vector,) = await DeterministicEmbedder().embed(["semaphore"])
        magnitude = sum(c * c for c in vector) ** 0.5
        assert magnitude == pytest.approx(1.0, abs=1e-6)

    def test_test_double_is_refused_by_default(self) -> None:
        """A fake embedder in production reads as a quality problem, not a
        configuration one, so it must fail loudly at construction."""
        with pytest.raises(ValueError, match="must not be used outside"):
            build_embedder(provider="deterministic")

        assert isinstance(
            build_embedder(provider="deterministic", allow_test_double=True),
            DeterministicEmbedder,
        )

    def test_unknown_provider_is_rejected(self) -> None:
        with pytest.raises(ValueError, match="Unknown embedding provider"):
            build_embedder(provider="word2vec")

    def test_pgvector_rendering_round_trips_shape(self) -> None:
        rendered = to_pgvector([0.5] * EMBEDDING_DIMENSION)
        assert rendered.startswith("[") and rendered.endswith("]")
        assert rendered.count(",") == EMBEDDING_DIMENSION - 1

    def test_wrong_dimension_fails_before_the_database_sees_it(self) -> None:
        with pytest.raises(ValueError, match="Expected 1024 dimensions"):
            to_pgvector([0.1, 0.2, 0.3])
