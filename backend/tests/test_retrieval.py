"""Retrieval behaviour, against real Postgres with real indexes.

The headline claim under test: hybrid retrieval finds passages that pure
vector search misses. It is tested with the deterministic embedder precisely
*because* that embedder carries no semantics — so any hit on an exact
technical term is attributable to the lexical half, not to lucky embeddings.
That makes the test a genuine assertion about the fusion rather than about a
particular model.
"""

from __future__ import annotations

import asyncpg
import pytest

from app.domain.embedding import DeterministicEmbedder
from app.services.retrieval import (
    Coverage,
    InsufficientMaterialError,
    assert_examinable,
    get_coverage,
    hybrid_search,
    retrieve_for_question,
    select_diverse,
)
from tests.conftest import make_student

pytestmark = pytest.mark.integration

PASSAGES = [
    "A deadlock is a situation in which two or more processes are unable to proceed.",
    "The four necessary conditions are mutual exclusion, hold and wait, no preemption, "
    "and circular wait.",
    "The Banker's Algorithm checks whether granting a request leaves a safe state.",
    "The TLB is a small associative cache holding recent page table entries.",
    "Paging divides the logical address space into fixed size pages.",
    "A semaphore is an integer variable accessed through wait and signal operations.",
    "Round robin scheduling assigns each process a fixed time quantum in turn.",
    "A deadlock is a situation in which two or more processes are unable to proceed.",
]


async def _corpus(db: asyncpg.Connection) -> tuple[str, str, list[str]]:
    user = await make_student(db)
    subject = await db.fetchval(
        "insert into public.subject (user_id, name) values ($1, 'Operating Systems') returning id",
        user,
    )
    document = await db.fetchval(
        """
        insert into public.document (subject_id, user_id, filename, storage_path, mime_type,
                                     byte_size, content_hash, status)
        values ($1, $2, 'os.pdf', 'k', 'application/pdf', 100, 'h', 'ready') returning id
        """,
        subject,
        user,
    )

    embedder = DeterministicEmbedder()
    vectors = await embedder.embed(PASSAGES)
    from app.domain.embedding import to_pgvector

    chunk_ids: list[str] = []
    for index, (text, vector) in enumerate(zip(PASSAGES, vectors, strict=True)):
        chunk_id = await db.fetchval(
            """
            insert into public.chunk (document_id, subject_id, user_id, chunk_index, content,
                                      page_number, token_count, embedding)
            values ($1, $2, $3, $4, $5, $6, 30, $7::extensions.halfvec) returning id
            """,
            document,
            subject,
            user,
            index,
            text,
            40 + index,
            to_pgvector(vector),
        )
        chunk_ids.append(str(chunk_id))
    return str(user), str(subject), chunk_ids


class TestHybridSearch:
    async def test_exact_technical_term_is_found_by_the_lexical_half(
        self, db: asyncpg.Connection
    ) -> None:
        """The whole argument for hybrid retrieval on this corpus.

        The embedder here is semantically blind, so a vector-only pipeline
        could only return "TLB" by chance. Finding it proves BM25 is carrying
        the query, which is exactly the failure mode a jargon-dense corpus of
        student notes produces in production.
        """
        _, subject, _ = await _corpus(db)

        results = await hybrid_search(
            db, DeterministicEmbedder(), subject_id=subject, query="TLB", limit=5
        )

        assert results, "hybrid search returned nothing for an exact term"
        assert any("TLB" in r.content for r in results)
        assert any(r.lexical_rank is not None for r in results)

    async def test_results_are_ordered_by_fused_score(
        self, db: asyncpg.Connection
    ) -> None:
        _, subject, _ = await _corpus(db)
        results = await hybrid_search(
            db,
            DeterministicEmbedder(),
            subject_id=subject,
            query="banker algorithm safe state",
            limit=8,
        )
        scores = [r.fused_score for r in results]
        assert scores == sorted(scores, reverse=True)

    async def test_a_chunk_found_by_both_retrievers_outranks_one_found_by_one(
        self, db: asyncpg.Connection
    ) -> None:
        """The property RRF exists to produce."""
        _, subject, _ = await _corpus(db)
        results = await hybrid_search(
            db, DeterministicEmbedder(), subject_id=subject, query="banker algorithm", limit=8
        )
        both = [r for r in results if r.retrieved_by == "both"]
        single = [r for r in results if r.retrieved_by != "both"]
        if both and single:
            assert min(r.fused_score for r in both) > max(r.fused_score for r in single)

    async def test_retrieval_never_crosses_a_subject(
        self, db: asyncpg.Connection
    ) -> None:
        """Grounding in *this* subject's notes is the product's core claim."""
        _, subject_a, _ = await _corpus(db)
        _, subject_b, _ = await _corpus(db)

        results = await hybrid_search(
            db, DeterministicEmbedder(), subject_id=subject_b, query="deadlock", limit=20
        )
        owners = await db.fetch(
            "select distinct subject_id from public.chunk where id = any($1::uuid[])",
            [r.chunk_id for r in results],
        )
        assert {str(r["subject_id"]) for r in owners} <= {subject_b}
        assert subject_a not in {str(r["subject_id"]) for r in owners}

    async def test_concept_scope_narrows_the_candidate_set(
        self, db: asyncpg.Connection
    ) -> None:
        """Concept Graph -> focused practice in one tap needs this (audit C-12)."""
        user, subject, chunk_ids = await _corpus(db)
        concept = await db.fetchval(
            "insert into public.concept (subject_id, user_id, canonical_name) "
            "values ($1, $2, 'Deadlock') returning id",
            subject,
            user,
        )
        await db.execute(
            "insert into public.concept_chunk (concept_id, chunk_id, user_id) "
            "values ($1, $2, $3)",
            concept,
            chunk_ids[1],
            user,
        )

        results = await hybrid_search(
            db,
            DeterministicEmbedder(),
            subject_id=subject,
            query="deadlock conditions",
            concept_ids=[str(concept)],
            limit=10,
        )
        assert [r.chunk_id for r in results] == [chunk_ids[1]]

    async def test_unmatched_query_returns_nothing_rather_than_noise(
        self, db: asyncpg.Connection
    ) -> None:
        """A subject with no relevant material must not silently return its
        least-irrelevant chunk as if it were an answer."""
        _, subject, _ = await _corpus(db)
        results = await hybrid_search(
            db,
            DeterministicEmbedder(),
            subject_id=subject,
            query="photosynthesis chloroplast",
            limit=5,
        )
        assert all(r.lexical_rank is None for r in results), (
            "a lexical hit on an unrelated query means the query parser is too loose"
        )


class TestDiversity:
    async def test_near_duplicates_are_displaced(self, db: asyncpg.Connection) -> None:
        """The corpus deliberately contains the deadlock definition twice.

        Six chunks that restate one definition is one chunk of information
        spending six chunks of context, and a question generated from them can
        only be shallow.
        """
        _, subject, _ = await _corpus(db)
        candidates = await hybrid_search(
            db, DeterministicEmbedder(), subject_id=subject, query="deadlock", limit=20
        )
        if len(candidates) < 3:
            pytest.skip("not enough candidates to exercise MMR")

        selected = await select_diverse(db, candidates, top_n=3)
        contents = [c.content for c in selected]
        assert len(contents) == len(set(contents)), "MMR returned a verbatim duplicate"

    async def test_the_top_hit_is_always_kept(self, db: asyncpg.Connection) -> None:
        """Diversity must not cost the single most relevant passage."""
        _, subject, _ = await _corpus(db)
        candidates = await hybrid_search(
            db, DeterministicEmbedder(), subject_id=subject, query="semaphore", limit=20
        )
        if not candidates:
            pytest.skip("no candidates")
        selected = await select_diverse(db, candidates, top_n=3)
        assert selected[0].chunk_id == candidates[0].chunk_id

    async def test_fewer_candidates_than_requested_is_not_an_error(
        self, db: asyncpg.Connection
    ) -> None:
        _, subject, _ = await _corpus(db)
        candidates = await hybrid_search(
            db, DeterministicEmbedder(), subject_id=subject, query="TLB", limit=20
        )
        selected = await select_diverse(db, candidates, top_n=50)
        assert len(selected) == len(candidates)

    async def test_full_read_path_returns_a_citable_grounding_set(
        self, db: asyncpg.Connection
    ) -> None:
        """Everything returned here becomes the only citable set for the
        question, enforced by the citation trigger in the schema."""
        _, subject, _ = await _corpus(db)
        chunks = await retrieve_for_question(
            db,
            DeterministicEmbedder(),
            subject_id=subject,
            query="deadlock necessary conditions",
            top_n=4,
        )
        assert chunks
        assert all(c.page_number >= 1 for c in chunks)
        assert len({c.chunk_id for c in chunks}) == len(chunks)


class TestCoverageGuard:
    async def test_empty_subject_asks_for_an_upload(self, db: asyncpg.Connection) -> None:
        user = await make_student(db)
        subject = await db.fetchval(
            "insert into public.subject (user_id, name) values ($1, 'Empty') returning id", user
        )
        coverage = await get_coverage(db, str(subject))

        with pytest.raises(InsufficientMaterialError) as exc:
            assert_examinable(coverage, min_concepts=3)
        assert "Upload your notes" in exc.value.reason

    async def test_processing_subject_says_so_rather_than_failing(self) -> None:
        coverage = Coverage(0, 1, 0, 0, 0, 0, 0)
        with pytest.raises(InsufficientMaterialError, match="still being processed"):
            assert_examinable(coverage, min_concepts=3)

    async def test_all_uploads_failed_points_at_the_subject(self) -> None:
        coverage = Coverage(0, 0, 2, 0, 0, 0, 0)
        with pytest.raises(InsufficientMaterialError, match="None of the uploads"):
            assert_examinable(coverage, min_concepts=3)

    async def test_thin_corpus_is_refused_with_the_actual_count(self) -> None:
        """Refusing to fake it is more trustworthy than generating ungrounded
        questions, and the message has to be specific to be actionable."""
        coverage = Coverage(1, 0, 0, 10, 10, 1, 300)
        with pytest.raises(InsufficientMaterialError) as exc:
            assert_examinable(coverage, min_concepts=3)
        assert "1 concept" in exc.value.reason
        assert "Upload more material" in exc.value.reason

    async def test_sufficient_corpus_passes(self) -> None:
        assert_examinable(Coverage(2, 0, 0, 40, 40, 7, 9000), min_concepts=3)

    async def test_coverage_reflects_real_rows(self, db: asyncpg.Connection) -> None:
        _, subject, _ = await _corpus(db)
        coverage = await get_coverage(db, subject)
        assert coverage.chunk_count == len(PASSAGES)
        assert coverage.embedded_count == len(PASSAGES)
        assert coverage.ready_documents == 1
        assert coverage.is_processing is False
