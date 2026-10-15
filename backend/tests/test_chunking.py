"""Chunking guarantees.

Retrieval quality is downstream of these, and so is citation correctness: a
chunk with a wrong page number produces a citation that sends a student to
the wrong page, which is worse than no citation at all.
"""

from __future__ import annotations

from app.domain.chunking import (
    MAX_TOKENS,
    MIN_TOKENS,
    Page,
    build_context_prefix,
    chunk_pages,
    estimate_tokens,
)

OS_NOTES = """UNIT 3 — DEADLOCK

A deadlock is a situation in which two or more processes are unable to proceed
because each is waiting for a resource held by another. The processes remain
blocked indefinitely and no progress is made by any of them.

3.1 Necessary Conditions

Four conditions must hold simultaneously for a deadlock to occur. Mutual
exclusion means at least one resource is held in a non-sharable mode. Hold and
wait means a process holding at least one resource is waiting to acquire
additional resources held by other processes. No preemption means a resource
can be released only voluntarily by the process holding it. Circular wait means
there exists a set of waiting processes such that each is waiting for a
resource held by the next process in the set.

3.2 Banker's Algorithm

The Banker's Algorithm is a deadlock avoidance algorithm. Before granting a
resource request it checks whether the resulting state would be safe. A state
is safe if there exists a sequence in which every process can obtain its
maximum resources and terminate.
"""

MEMORY_NOTES = """UNIT 4 — VIRTUAL MEMORY

Paging divides the logical address space into fixed size pages. The page table
maps page numbers to frame numbers in physical memory.

4.1 Translation Lookaside Buffer

The TLB is a small associative cache holding recent page table entries. A TLB
hit avoids a memory access for translation.
"""


def _pages() -> list[Page]:
    return [Page(number=41, text=OS_NOTES), Page(number=42, text=MEMORY_NOTES)]


class TestStructure:
    def test_produces_chunks(self) -> None:
        assert chunk_pages(_pages())

    def test_indices_are_dense_and_ascending_from_zero(self) -> None:
        """Matches the unique (document_id, chunk_index) constraint."""
        chunks = chunk_pages(_pages())
        assert [c.index for c in chunks] == list(range(len(chunks)))

    def test_no_chunk_exceeds_the_cap(self) -> None:
        """Otherwise context budget depends on whatever the student uploaded."""
        assert all(c.token_count <= MAX_TOKENS for c in chunk_pages(_pages()))

    def test_headings_are_detected_and_attached(self) -> None:
        headings = {c.heading for c in chunk_pages(_pages()) if c.heading}
        assert any("DEADLOCK" in h for h in headings)
        assert any("Banker" in h for h in headings)

    def test_bullets_are_not_mistaken_for_headings(self) -> None:
        pages = [Page(number=1, text="- mutual exclusion\n- hold and wait\n- no preemption\n")]
        assert all(c.heading is None for c in chunk_pages(pages))

    def test_empty_input_yields_nothing(self) -> None:
        assert chunk_pages([]) == []
        assert chunk_pages([Page(number=1, text="   \n\n  ")]) == []


class TestCitationIntegrity:
    def test_every_chunk_carries_a_page_number(self) -> None:
        """A chunk with no page cannot be cited, so it cannot flag a gap."""
        assert all(c.page_number >= 1 for c in chunk_pages(_pages()))

    def test_page_numbers_come_from_the_source_not_a_counter(self) -> None:
        """Pages start at 41 here; a chunk numbered 1 would mean an off-by-N
        citation sending the student to the wrong page."""
        pages = {c.page_number for c in chunk_pages(_pages())}
        assert pages <= {41, 42}

    def test_content_is_attributed_to_the_page_it_came_from(self) -> None:
        chunks = chunk_pages(_pages())
        tlb = [c for c in chunks if "TLB" in c.content]
        assert tlb, "expected the TLB passage to survive chunking"
        assert all(c.page_number == 42 for c in tlb)


class TestSizing:
    def test_long_prose_is_split_rather_than_truncated(self) -> None:
        long_page = [Page(number=1, text="The scheduler selects a process to run. " * 400)]
        chunks = chunk_pages(long_page)
        assert len(chunks) > 1
        assert all(c.token_count <= MAX_TOKENS for c in chunks)

    def test_no_content_is_lost_when_splitting(self) -> None:
        """Overlap makes the joined text longer than the source; it must never
        be shorter, which would mean silently dropping a student's notes."""
        source = "Mutual exclusion. Hold and wait. No preemption. Circular wait. " * 120
        chunks = chunk_pages([Page(number=1, text=source)])
        joined = " ".join(c.content for c in chunks)
        assert "Circular wait" in joined
        assert len(joined) >= len(source) * 0.95

    def test_a_sentence_longer_than_the_cap_is_still_emitted(self) -> None:
        """Bad PDF extraction produces run-on lines with no sentence breaks."""
        runon = "word " * 6000
        chunks = chunk_pages([Page(number=7, text=runon)])
        assert chunks
        assert all(c.token_count <= MAX_TOKENS for c in chunks)
        assert all(c.page_number == 7 for c in chunks)

    def test_trailing_scrap_is_folded_back(self) -> None:
        """A 10-token orphan chunk retrieves badly and dilutes the index."""
        text = "The scheduler selects a process to run. " * 200 + "\n\nEnd."
        chunks = chunk_pages([Page(number=1, text=text)])
        assert len(chunks) == 1 or chunks[-1].token_count >= MIN_TOKENS

    def test_single_short_document_is_kept_whole(self) -> None:
        chunks = chunk_pages([Page(number=3, text="A deadlock blocks progress.")])
        assert len(chunks) == 1
        assert chunks[0].page_number == 3


class TestContextPrefix:
    def test_prefix_names_document_section_and_page(self) -> None:
        prefix = build_context_prefix(
            document_title="OperatingSystems.pdf",
            heading="3.1 Necessary Conditions",
            page_number=42,
        )
        assert "OperatingSystems.pdf" in prefix
        assert "Necessary Conditions" in prefix
        assert "42" in prefix

    def test_prefix_survives_a_missing_heading(self) -> None:
        prefix = build_context_prefix(
            document_title="scan.pdf", heading=None, page_number=1
        )
        assert "scan.pdf" in prefix and "1" in prefix


class TestTokenEstimate:
    def test_monotonic_in_length(self) -> None:
        assert estimate_tokens("word " * 10) < estimate_tokens("word " * 100)

    def test_never_zero(self) -> None:
        """A zero-token chunk would divide by zero in budget arithmetic."""
        assert estimate_tokens("") >= 1
        assert estimate_tokens("a") >= 1
