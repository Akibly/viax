"""Text extraction from uploaded documents.

Audit RAG-04: the specified `Document.status` includes `failed`, and the PRD
names low-quality scans as a risk with the mitigation "a clear
processing-failed state rather than a silent bad result". But the schema had
nowhere to put a reason, so the state could not say what went wrong.

The two failures need different advice and are therefore different codes:

  no_text_layer   a scan or photo — the file is fine, it just needs OCR
  unreadable      corrupt, encrypted, or not the format it claims to be

Anything that ends up as `failed` carries a message a student can act on.
"""

from __future__ import annotations

import html
import re
from dataclasses import dataclass
from enum import StrEnum
from io import BytesIO
from pathlib import PurePosixPath
from zipfile import BadZipFile, ZipFile

from app.domain.chunking import Page


class ExtractionError(StrEnum):
    NO_TEXT_LAYER = "no_text_layer"
    UNREADABLE = "unreadable"
    ENCRYPTED = "encrypted"
    TOO_MANY_PAGES = "too_many_pages"
    EMPTY = "empty"
    UNSUPPORTED_TYPE = "unsupported_type"


_ADVICE: dict[ExtractionError, str] = {
    ExtractionError.NO_TEXT_LAYER: (
        "This looks like a scan or a photo rather than a text PDF. "
        "Re-upload with text recognition enabled, or scan at a higher resolution."
    ),
    ExtractionError.UNREADABLE: (
        "This file could not be opened. It may be corrupt — try re-exporting it."
    ),
    ExtractionError.ENCRYPTED: (
        "This PDF is password-protected. Remove the password and upload it again."
    ),
    ExtractionError.TOO_MANY_PAGES: (
        "This document is longer than the {limit}-page limit. "
        "Split it into chapters and upload them separately."
    ),
    ExtractionError.EMPTY: (
        "No readable text was found in this file."
    ),
    ExtractionError.UNSUPPORTED_TYPE: (
        "That file type is not supported. Upload PDF, PPTX, DOCX, Markdown, text, or CSV."
    ),
}


# Named for how it reads at the call site (`raise ExtractionFailed(...)`).
class ExtractionFailed(Exception):  # noqa: N818
    """Raised with a code and student-facing advice, both stored on the row."""

    def __init__(self, code: ExtractionError, **fmt: object) -> None:
        self.code = code
        self.advice = _ADVICE[code].format(**fmt)
        super().__init__(f"{code}: {self.advice}")


@dataclass(frozen=True, slots=True)
class Extraction:
    pages: list[Page]
    page_count: int
    # True when the file parsed but carried no usable text layer, so the
    # caller can route it to OCR instead of failing outright.
    needs_ocr: bool


# A page carrying at least this much text has a real text layer. Below it,
# what pypdf returned is stray ligatures from a scan.
_MIN_CHARS_FOR_TEXT_PAGE = 20

# A long document where almost every page came back empty is a scan with a
# few stray text objects, even though a handful of pages extracted. Short
# documents are exempt: a genuine two-page summary is not a scan, and an
# average-characters-per-page rule wrongly routes one to OCR.
_MOSTLY_EMPTY_RATIO = 0.2
_MOSTLY_EMPTY_MIN_PAGES = 5


def extract_pdf(data: bytes, *, max_pages: int) -> Extraction:
    """Extract page-attributed text from a PDF.

    Page numbers are 1-indexed and preserved exactly, because every citation
    in the product resolves through them.
    """
    from pypdf import PdfReader
    from pypdf.errors import PdfReadError

    try:
        reader = PdfReader(BytesIO(data))
    except PdfReadError as exc:
        raise ExtractionFailed(ExtractionError.UNREADABLE) from exc
    except Exception as exc:  # pypdf raises a wide range on malformed input
        raise ExtractionFailed(ExtractionError.UNREADABLE) from exc

    if reader.is_encrypted:
        # An empty user password is common and harmless; a real one is not.
        try:
            if reader.decrypt("") == 0:
                raise ExtractionFailed(ExtractionError.ENCRYPTED)
        except ExtractionFailed:
            raise
        except Exception as exc:
            raise ExtractionFailed(ExtractionError.ENCRYPTED) from exc

    page_count = len(reader.pages)
    if page_count == 0:
        raise ExtractionFailed(ExtractionError.EMPTY)
    if page_count > max_pages:
        raise ExtractionFailed(ExtractionError.TOO_MANY_PAGES, limit=max_pages)

    pages: list[Page] = []
    text_pages = 0
    for index, page in enumerate(reader.pages, start=1):
        try:
            text = page.extract_text() or ""
        except Exception:
            # One unreadable page should not lose the other 299. Ingestion is
            # resumable and partial by design (audit OPS-03).
            text = ""
        text = _normalise(text)
        if text.strip():
            pages.append(Page(number=index, text=text))
            if len(text.strip()) >= _MIN_CHARS_FOR_TEXT_PAGE:
                text_pages += 1

    # No page carried a text layer: this is a scan, and the file is fine — it
    # just needs OCR. Returning `failed` here would lose a legitimate upload.
    if text_pages == 0:
        return Extraction(pages=pages, page_count=page_count, needs_ocr=True)

    mostly_empty = (
        page_count >= _MOSTLY_EMPTY_MIN_PAGES
        and text_pages < page_count * _MOSTLY_EMPTY_RATIO
    )
    # The extracted pages are still returned so OCR augments rather than
    # replaces what already worked.
    return Extraction(pages=pages, page_count=page_count, needs_ocr=mostly_empty)


def extract_text_file(data: bytes) -> Extraction:
    """Plain text and markdown. Paginated on form feeds, else one page."""
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        try:
            text = data.decode("latin-1")
        except Exception as exc:
            raise ExtractionFailed(ExtractionError.UNREADABLE) from exc

    if not text.strip():
        raise ExtractionFailed(ExtractionError.EMPTY)

    raw_pages = text.split("\f") if "\f" in text else [text]
    pages = [
        Page(number=i, text=_normalise(p))
        for i, p in enumerate(raw_pages, start=1)
        if p.strip()
    ]
    return Extraction(pages=pages, page_count=len(pages), needs_ocr=False)


def _xml_text(xml: bytes) -> str:
    try:
        source = xml.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ExtractionFailed(ExtractionError.UNREADABLE) from exc
    # Only consume Office's text-run elements. Avoiding a general-purpose XML
    # parser also avoids entity expansion and external-resource attacks on an
    # uploaded document.
    runs = re.findall(r"<(?:[a-z]+:)?t(?:\s[^>]*)?>(.*?)</(?:[a-z]+:)?t>", source, re.DOTALL)
    return _normalise("\n".join(html.unescape(run) for run in runs))


def extract_docx(data: bytes) -> Extraction:
    """Extract the visible document body from an Office Open XML Word file."""
    try:
        with ZipFile(BytesIO(data)) as archive:
            text = _xml_text(archive.read("word/document.xml"))
    except (BadZipFile, KeyError, OSError) as exc:
        raise ExtractionFailed(ExtractionError.UNREADABLE) from exc
    if not text.strip():
        raise ExtractionFailed(ExtractionError.EMPTY)
    return Extraction(pages=[Page(number=1, text=text)], page_count=1, needs_ocr=False)


def extract_pptx(data: bytes, *, max_pages: int) -> Extraction:
    """Extract one citation page per slide, in numeric slide order."""
    try:
        with ZipFile(BytesIO(data)) as archive:
            names = [
                name
                for name in archive.namelist()
                if PurePosixPath(name).parent.as_posix() == "ppt/slides"
                and PurePosixPath(name).name.startswith("slide")
                and PurePosixPath(name).suffix == ".xml"
            ]
            names.sort(key=lambda name: int(PurePosixPath(name).stem.removeprefix("slide")))
            if len(names) > max_pages:
                raise ExtractionFailed(ExtractionError.TOO_MANY_PAGES, limit=max_pages)
            pages = [
                Page(number=index, text=text)
                for index, name in enumerate(names, start=1)
                if (text := _xml_text(archive.read(name))).strip()
            ]
    except ExtractionFailed:
        raise
    except (BadZipFile, KeyError, OSError, ValueError) as exc:
        raise ExtractionFailed(ExtractionError.UNREADABLE) from exc
    if not names or not pages:
        raise ExtractionFailed(ExtractionError.EMPTY)
    return Extraction(pages=pages, page_count=len(names), needs_ocr=False)


def extract(data: bytes, *, mime_type: str, max_pages: int) -> Extraction:
    if mime_type == "application/pdf":
        return extract_pdf(data, max_pages=max_pages)
    if mime_type in ("text/plain", "text/markdown"):
        return extract_text_file(data)
    if mime_type == "text/csv":
        return extract_text_file(data)
    if mime_type == "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
        return extract_docx(data)
    if mime_type == "application/vnd.openxmlformats-officedocument.presentationml.presentation":
        return extract_pptx(data, max_pages=max_pages)
    if mime_type in ("image/png", "image/jpeg"):
        # A photo of a page is always an OCR job; there is no text layer to try.
        return Extraction(pages=[], page_count=1, needs_ocr=True)
    raise ExtractionFailed(ExtractionError.UNSUPPORTED_TYPE)


def _normalise(text: str) -> str:
    """Repair the artefacts PDF extraction reliably introduces."""
    # Hyphenation across a line break: "sched-\nuler" -> "scheduler".
    text = text.replace("-\n", "")
    # Collapse the ragged single newlines PDF text layers emit mid-sentence,
    # while preserving real paragraph breaks.
    lines = [ln.rstrip() for ln in text.replace("\r\n", "\n").replace("\r", "\n").split("\n")]
    out: list[str] = []
    for line in lines:
        if not line.strip():
            out.append("")
            continue
        if (
            out
            and out[-1]
            and not out[-1].endswith((".", "!", "?", ":", ";"))
            and line[:1].islower()
        ):
            out[-1] = f"{out[-1]} {line.lstrip()}"
        else:
            out.append(line)
    # Squeeze runs of blank lines down to one.
    squeezed: list[str] = []
    for line in out:
        if not line and squeezed and not squeezed[-1]:
            continue
        squeezed.append(line)
    return "\n".join(squeezed).strip()
