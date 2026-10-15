"""Retrieval: hybrid search, diversity reranking, and the coverage guard.

The fusion happens in Postgres (see the migration). This module owns the two
decisions that follow it.

**Diversity.** Fused relevance alone returns six chunks that all restate the
same definition, because a well-written set of notes says the important thing
several times. Six near-duplicates is one chunk of information spending six
chunks of context, and a question generated from them can only be shallow.
Maximal Marginal Relevance trades a little relevance for coverage, which is
what actually produces a viva that moves.

**Refusal.** If the corpus cannot support a viva, the honest answer is to say
so rather than let the model invent questions from parametric knowledge —
which would silently break FR-3.1, the requirement the whole product rests on.
"""

from __future__ import annotations

from dataclasses import dataclass

import asyncpg

from app.core.logging import get_logger
from app.domain.embedding import EmbeddingProvider, to_pgvector

log = get_logger(__name__)

# How much MMR favours relevance over novelty. 0.7 keeps the top hit and its
# strongest support while still displacing verbatim restatements.
MMR_LAMBDA = 0.7


@dataclass(frozen=True, slots=True)
class RetrievedChunk:
    chunk_id: str
    document_id: str
    content: str
    context_prefix: str | None
    page_number: int
    vector_rank: int | None
    lexical_rank: int | None
    fused_score: float

    @property
    def embedding_text(self) -> str:
        return f"{self.context_prefix}\n\n{self.content}" if self.context_prefix else self.content

    @property
    def retrieved_by(self) -> str:
        """Which retriever found it. Logged, because 'the vector index never
        contributes' is a thing you want to discover from data."""
        if self.vector_rank is not None and self.lexical_rank is not None:
            return "both"
        return "vector" if self.vector_rank is not None else "lexical"


@dataclass(frozen=True, slots=True)
class Coverage:
    ready_documents: int
    pending_documents: int
    failed_documents: int
    chunk_count: int
    embedded_count: int
    concept_count: int
    total_tokens: int

    @property
    def is_processing(self) -> bool:
        return self.pending_documents > 0 or self.embedded_count < self.chunk_count


class InsufficientMaterialError(Exception):
    """Raised instead of generating questions the notes cannot support.

    Carries a message written for the student, because this is a state they
    can fix and the fix is specific.
    """

    def __init__(self, reason: str, coverage: Coverage) -> None:
        self.reason = reason
        self.coverage = coverage
        super().__init__(reason)


async def get_coverage(conn: asyncpg.Connection, subject_id: str) -> Coverage:
    row = await conn.fetchrow("select * from app.subject_coverage($1)", subject_id)
    return Coverage(
        ready_documents=row["ready_documents"],
        pending_documents=row["pending_documents"],
        failed_documents=row["failed_documents"],
        chunk_count=row["chunk_count"],
        embedded_count=row["embedded_count"],
        concept_count=row["concept_count"],
        total_tokens=row["total_tokens"],
    )


def assert_examinable(coverage: Coverage, *, min_concepts: int) -> None:
    """Refuse to start a viva the material cannot support.

    Each branch names what the student should do next. "Not enough material"
    with no next step is a dead end, and the PRD forbids those.
    """
    if coverage.chunk_count == 0:
        if coverage.pending_documents:
            raise InsufficientMaterialError(
                "Your notes are still being processed. This usually takes under a minute.",
                coverage,
            )
        if coverage.failed_documents:
            raise InsufficientMaterialError(
                "None of the uploads for this subject could be read. "
                "Open the subject to see what went wrong with each file.",
                coverage,
            )
        raise InsufficientMaterialError(
            "Upload your notes for this subject and I can examine you on them.", coverage
        )

    if coverage.embedded_count == 0:
        raise InsufficientMaterialError(
            "Your notes are still being indexed. This usually takes under a minute.", coverage
        )

    if coverage.concept_count < min_concepts:
        raise InsufficientMaterialError(
            f"These notes cover {coverage.concept_count} "
            f"{'concept' if coverage.concept_count == 1 else 'concepts'} — too few for a "
            f"full viva. Upload more material for this subject and I will have more to "
            f"examine you on.",
            coverage,
        )


async def hybrid_search(
    conn: asyncpg.Connection,
    embedder: EmbeddingProvider,
    *,
    subject_id: str,
    query: str,
    concept_ids: list[str] | None = None,
    limit: int = 20,
) -> list[RetrievedChunk]:
    (vector,) = await embedder.embed([query])

    rows = await conn.fetch(
        "select * from app.hybrid_search($1, $2, $3::extensions.halfvec, $4::uuid[], $5)",
        subject_id,
        query,
        to_pgvector(vector),
        concept_ids,
        limit,
    )

    results = [
        RetrievedChunk(
            chunk_id=str(row["chunk_id"]),
            document_id=str(row["document_id"]),
            content=row["content"],
            context_prefix=row["context_prefix"],
            page_number=row["page_number"],
            vector_rank=row["vector_rank"],
            lexical_rank=row["lexical_rank"],
            fused_score=float(row["fused_score"]),
        )
        for row in rows
    ]

    log.info(
        "retrieval.hybrid",
        subject_id=subject_id,
        query_chars=len(query),
        returned=len(results),
        vector_only=sum(1 for r in results if r.retrieved_by == "vector"),
        lexical_only=sum(1 for r in results if r.retrieved_by == "lexical"),
        both=sum(1 for r in results if r.retrieved_by == "both"),
    )
    return results


async def select_diverse(
    conn: asyncpg.Connection,
    candidates: list[RetrievedChunk],
    *,
    top_n: int,
    lambda_: float = MMR_LAMBDA,
) -> list[RetrievedChunk]:
    """Maximal Marginal Relevance over the fused candidates.

    Picks greedily, each time taking the candidate that maximises

        lambda * relevance  -  (1 - lambda) * max similarity to anything picked

    so the second chunk has to say something the first did not.
    """
    if len(candidates) <= top_n:
        return candidates

    # Cosine similarity between candidates, computed in the database because
    # that is where the vectors already are — shipping 20 x 1024 floats to
    # Python to multiply them is pure waste.
    ids = [c.chunk_id for c in candidates]
    similarity_rows = await conn.fetch(
        """
        select a.id as a_id, b.id as b_id,
               1 - (a.embedding <=> b.embedding) as similarity
          from public.chunk a
          join public.chunk b on b.id = any($1::uuid[]) and b.id > a.id
         where a.id = any($1::uuid[])
        """,
        ids,
    )
    similarity: dict[tuple[str, str], float] = {}
    for row in similarity_rows:
        key = (str(row["a_id"]), str(row["b_id"]))
        similarity[key] = float(row["similarity"])

    def sim(one: str, two: str) -> float:
        if one == two:
            return 1.0
        return similarity.get((one, two)) or similarity.get((two, one)) or 0.0

    # Fused scores are tiny (~1/60) and their spread is what matters, so
    # normalise before mixing with a similarity in [0, 1].
    best = max(c.fused_score for c in candidates)
    relevance = {c.chunk_id: (c.fused_score / best if best else 0.0) for c in candidates}

    selected: list[RetrievedChunk] = [candidates[0]]
    remaining = candidates[1:]

    while len(selected) < top_n and remaining:
        scored = [
            (
                lambda_ * relevance[c.chunk_id]
                - (1 - lambda_) * max(sim(c.chunk_id, s.chunk_id) for s in selected),
                index,
            )
            for index, c in enumerate(remaining)
        ]
        _, pick = max(scored)
        selected.append(remaining.pop(pick))

    log.info(
        "retrieval.reranked",
        candidates=len(candidates),
        selected=len(selected),
        pages=sorted({c.page_number for c in selected}),
    )
    return selected


async def retrieve_for_question(
    conn: asyncpg.Connection,
    embedder: EmbeddingProvider,
    *,
    subject_id: str,
    query: str,
    concept_ids: list[str] | None = None,
    candidate_limit: int = 20,
    top_n: int = 6,
) -> list[RetrievedChunk]:
    """The full read path: hybrid retrieve, then diversify.

    The chunks this returns become the grounding set for a question, and
    therefore the only chunks its evaluation is allowed to cite — the citation
    trigger in the schema enforces exactly that.
    """
    candidates = await hybrid_search(
        conn,
        embedder,
        subject_id=subject_id,
        query=query,
        concept_ids=concept_ids,
        limit=candidate_limit,
    )
    if not candidates:
        return []
    return await select_diverse(conn, candidates, top_n=top_n)
