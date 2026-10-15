"""Structure-aware chunking.

Audit RAG-03: the corpus specifies chunking by size only — "semantic,
~500-800 tokens with overlap". That is a dimension, not a strategy. It says
nothing about the formats that actually break chunkers: lecture slides,
numbered sections, tables, and the heading structure that carries most of the
meaning in student notes.

Two decisions drive everything here.

**Split on structure first, size second.** A heading boundary is a real
semantic boundary; a 700-token boundary is an arbitrary one. Splitting on
size alone routinely cuts a definition in half, and half a definition
retrieves for neither query.

**Every chunk records the page it starts on.** Citations resolve through this
(FR-4.3). A chunk with no page is a chunk that cannot be cited, which in this
product means it cannot be used to flag a gap at all.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

# Chunk sizing, in approximate tokens. The spec's 500-800 range is kept.
TARGET_TOKENS = 650
MAX_TOKENS = 800
MIN_TOKENS = 120
# Overlap carries a sentence or two of context across the boundary so a
# definition split across two chunks is still recoverable from either.
OVERLAP_TOKENS = 80

# Token estimation. Real tokenisation is a network call per chunk, which is
# absurd for sizing decisions that only need to be approximately right. ~3.6
# characters per token is a reasonable English-prose average; the caller
# stores the estimate and the true count is only needed for budgeting.
_CHARS_PER_TOKEN = 3.6

_HEADING_PATTERNS = (
    re.compile(r"^\s{0,3}#{1,6}\s+\S"),                      # markdown
    re.compile(r"^\s{0,3}(?:chapter|section|unit|module|lecture|topic)\b", re.I),
    # The dashes and bullets below are the real Unicode characters that appear
    # in exported PDFs and slide decks; ASCII substitutes would not match them.
    re.compile(r"^\s{0,3}[A-Z][A-Z0-9 \-/&(),.'–—]{5,70}\s*$"),  # ALL CAPS line
)

# "3.1 Necessary Conditions" and "4.2.1 Paging" — section numbering at any
# depth, with or without a trailing dot.
_NUMBERED = re.compile(r"^\s{0,3}\d+(?:\.\d+){0,3}\.?\s+\S")

_SENTENCE_END = re.compile(r"(?<=[.!?])\s+(?=[A-Z(\"'\[])")
_BULLET = re.compile(
    r"^\s{0,6}(?:[-*•‣◦⁃]|\(?[a-z0-9]{1,3}[.)])\s+"
)


def estimate_tokens(text: str) -> int:
    """Approximate token count. Deliberately cheap; see module docstring."""
    return max(1, round(len(text) / _CHARS_PER_TOKEN))


@dataclass(frozen=True, slots=True)
class Page:
    """One extracted page. `number` is 1-indexed to match what a reader sees."""

    number: int
    text: str


@dataclass(frozen=True, slots=True)
class Chunk:
    index: int
    content: str
    page_number: int
    token_count: int
    heading: str | None = None


@dataclass(slots=True)
class _Block:
    """A run of text under one heading, with the page it began on."""

    text: str
    page_number: int
    heading: str | None = None
    lines: list[str] = field(default_factory=list)


def _is_heading(line: str) -> bool:
    stripped = line.strip()
    if not stripped or len(stripped) > 90:
        return False

    # Section numbering is checked before bullets because the two overlap:
    # "3.1 Necessary Conditions" is a heading, "1. First, open the file."
    # is a list item. A trailing full stop is the reliable discriminator —
    # headings are noun phrases, list items are sentences.
    if _NUMBERED.match(line):
        return not stripped.endswith(".") and len(stripped.split()) >= 2

    if _BULLET.match(line):
        return False

    return any(p.match(line) for p in _HEADING_PATTERNS)


def _blocks_from_pages(pages: list[Page]) -> list[_Block]:
    """Group lines into heading-delimited blocks, remembering page origin."""
    blocks: list[_Block] = []
    current = _Block(text="", page_number=pages[0].number if pages else 1)

    for page in pages:
        for raw in page.text.splitlines():
            line = raw.rstrip()
            if _is_heading(line):
                if current.lines:
                    blocks.append(current)
                current = _Block(text="", page_number=page.number, heading=line.strip())
                continue
            if not line.strip() and not current.lines:
                # Skip leading blank lines so a block's page is the page its
                # content starts on, not the page its whitespace did.
                continue
            if not current.lines:
                current.page_number = page.number
            current.lines.append(line)

    if current.lines:
        blocks.append(current)

    for block in blocks:
        block.text = "\n".join(block.lines).strip()
    return [b for b in blocks if b.text]


def _split_oversized(text: str) -> list[str]:
    """Break a block that exceeds MAX_TOKENS, preferring sentence boundaries."""
    if estimate_tokens(text) <= MAX_TOKENS:
        return [text]

    pieces: list[str] = []
    buffer: list[str] = []
    size = 0

    for sentence in _SENTENCE_END.split(text):
        cost = estimate_tokens(sentence)

        # A single sentence longer than the cap (a table row, a run-on
        # paragraph from a bad PDF extraction) is split on whitespace as a
        # last resort rather than dropped.
        if cost > MAX_TOKENS:
            if buffer:
                pieces.append(" ".join(buffer))
                buffer, size = [], 0
            words = sentence.split()
            span = max(1, int(MAX_TOKENS * _CHARS_PER_TOKEN / 6))
            pieces.extend(
                " ".join(words[i : i + span]) for i in range(0, len(words), span)
            )
            continue

        if size + cost > TARGET_TOKENS and buffer:
            pieces.append(" ".join(buffer))
            buffer, size = [], 0

        buffer.append(sentence)
        size += cost

    if buffer:
        pieces.append(" ".join(buffer))
    return [p for p in pieces if p.strip()]


def _tail_overlap(text: str) -> str:
    """Last few sentences of a chunk, to prefix the next one.

    Hard-capped by character count. Text with no sentence boundaries — which
    is what a badly extracted PDF produces — would otherwise return the whole
    chunk as "overlap", so the next chunk starts already full and the size
    cap is silently exceeded.
    """
    budget_chars = int(OVERLAP_TOKENS * _CHARS_PER_TOKEN)

    sentences = _SENTENCE_END.split(text)
    carried: list[str] = []
    size = 0
    for sentence in reversed(sentences):
        cost = estimate_tokens(sentence)
        if size + cost > OVERLAP_TOKENS and carried:
            break
        carried.insert(0, sentence)
        size += cost

    overlap = " ".join(carried).strip()
    if len(overlap) > budget_chars:
        # Trim to the budget on a word boundary.
        overlap = overlap[-budget_chars:]
        if " " in overlap:
            overlap = overlap.split(" ", 1)[1]
    return overlap.strip()


def chunk_pages(pages: list[Page]) -> list[Chunk]:
    """Turn extracted pages into ordered, page-attributed chunks.

    Guarantees the rest of the pipeline relies on:

      * chunk_index is dense and ascending from 0, matching the unique
        constraint on (document_id, chunk_index);
      * every chunk carries a page number, so every chunk can be cited;
      * no chunk exceeds MAX_TOKENS, so retrieval never blows the context
        budget in a way that depends on the input document.
    """
    if not pages:
        return []

    chunks: list[Chunk] = []
    pending: list[str] = []
    pending_tokens = 0
    pending_page: int | None = None
    pending_heading: str | None = None

    def flush() -> None:
        nonlocal pending, pending_tokens, pending_page, pending_heading
        if not pending:
            return
        content = "\n\n".join(p for p in pending if p.strip()).strip()
        if content:
            chunks.append(
                Chunk(
                    index=len(chunks),
                    content=content,
                    page_number=pending_page or 1,
                    token_count=estimate_tokens(content),
                    heading=pending_heading,
                )
            )
        pending, pending_tokens, pending_page, pending_heading = [], 0, None, None

    for block in _blocks_from_pages(pages):
        # A heading is a semantic boundary, and the whole point of structure-
        # aware chunking is to cut there rather than at an arbitrary token
        # count. Cutting here also keeps page attribution honest: without it,
        # a section starting on page 42 can be packed into a chunk that began
        # on page 41 and would then cite the wrong page.
        if pending and block.heading is not None and block.heading != pending_heading:
            flush()

        for piece in _split_oversized(block.text):
            cost = estimate_tokens(piece)

            if pending and pending_tokens + cost > MAX_TOKENS:
                carried = _tail_overlap("\n\n".join(pending))
                boundary_page = block.page_number
                flush()
                if carried:
                    pending = [carried]
                    pending_tokens = estimate_tokens(carried)
                    pending_page = boundary_page

            if pending_page is None:
                pending_page = block.page_number
            if pending_heading is None:
                pending_heading = block.heading

            pending.append(piece)
            pending_tokens += cost

            if pending_tokens >= TARGET_TOKENS:
                carried = _tail_overlap("\n\n".join(pending))
                next_page = block.page_number
                flush()
                if carried:
                    pending = [carried]
                    pending_tokens = estimate_tokens(carried)
                    pending_page = next_page

    flush()

    # A trailing scrap shorter than MIN_TOKENS retrieves badly and dilutes the
    # index, so fold it back into its predecessor — but only when they share a
    # page and a section. Merging across either would give the combined chunk
    # the predecessor's page number, and a citation would then send the
    # student to the wrong page. A slightly weak chunk is a much smaller
    # problem than a confidently wrong citation.
    if (
        len(chunks) > 1
        and chunks[-1].token_count < MIN_TOKENS
        and chunks[-1].page_number == chunks[-2].page_number
        and chunks[-1].heading == chunks[-2].heading
    ):
        tail = chunks.pop()
        prev = chunks[-1]
        merged = f"{prev.content}\n\n{tail.content}"
        chunks[-1] = Chunk(
            index=prev.index,
            content=merged,
            page_number=prev.page_number,
            token_count=estimate_tokens(merged),
            heading=prev.heading,
        )

    return chunks


def build_context_prefix(
    *, document_title: str, heading: str | None, page_number: int
) -> str:
    """One sentence situating a chunk, prepended before embedding.

    This is the cheap half of contextual retrieval. A chunk reading "The four
    conditions are mutual exclusion, hold and wait..." does not retrieve for
    the query "deadlock" unless something in the embedded text says so.

    Deriving it from structure costs nothing. The richer variant — generating
    the sentence with a model — is a Day 3 upgrade measured against the
    retrieval eval set rather than assumed to be better.
    """
    parts = [f"From {document_title}"]
    if heading:
        parts.append(f", section {heading!r}")
    parts.append(f" (page {page_number}).")
    return "".join(parts)
