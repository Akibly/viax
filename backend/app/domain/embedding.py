"""Embedding providers.

Audit RAG-02: the specified schema said `embedding vector` and nothing else —
no dimension, no model, no index. Both are pinned here and in the migration,
and they have to agree: `halfvec(1024)` rejects a vector of any other width,
which is the failure you want (loud, at write time) rather than a silent
dimension mismatch that degrades retrieval quality invisibly.

Providers are swappable behind one protocol so the choice can be revisited
against the retrieval eval set rather than by argument.
"""

from __future__ import annotations

import hashlib
import math
from typing import Protocol, runtime_checkable

EMBEDDING_DIMENSION = 1024


@runtime_checkable
class EmbeddingProvider(Protocol):
    """Batch-first, because embedding one chunk at a time is the single most
    common way to make ingestion slow."""

    name: str
    dimension: int

    async def embed(self, texts: list[str]) -> list[list[float]]: ...


def _l2_normalise(vector: list[float]) -> list[float]:
    norm = math.sqrt(sum(component * component for component in vector))
    if norm == 0.0:
        return vector
    return [component / norm for component in vector]


class SentenceTransformerEmbedder:
    """Local model. The production default.

    Runs on the machine rather than behind an API, which keeps a student's
    uploaded notes out of a third-party embedding service — relevant to the
    data-protection gap the audit raised (LEGAL-02), and it removes a
    per-chunk network cost from ingestion.

    `BAAI/bge-large-en-v1.5` is 1024-dimensional, which is what the column is
    declared as. Swapping the model means changing the column, so the
    dimension is asserted at construction rather than discovered in
    production.
    """

    name = "bge-large-en-v1.5"
    dimension = EMBEDDING_DIMENSION

    def __init__(self, model_name: str = "BAAI/bge-large-en-v1.5") -> None:
        from sentence_transformers import SentenceTransformer

        self._model = SentenceTransformer(model_name)
        actual = self._model.get_sentence_embedding_dimension()
        if actual != EMBEDDING_DIMENSION:
            raise ValueError(
                f"{model_name} produces {actual}-dimensional vectors, but the chunk.embedding "
                f"column is halfvec({EMBEDDING_DIMENSION}). Change both or neither."
            )

    async def embed(self, texts: list[str]) -> list[list[float]]:
        import anyio

        def _run() -> list[list[float]]:
            vectors = self._model.encode(
                texts, normalize_embeddings=True, show_progress_bar=False
            )
            return [list(map(float, v)) for v in vectors]

        return await anyio.to_thread.run_sync(_run)


class DeterministicEmbedder:
    """Test double. Never valid in production — see `build_embedder`.

    Produces stable, L2-normalised vectors from a hash of the text, so tests
    can exercise the full write path, the halfvec column, and the HNSW index
    without downloading a 1.3 GB model. It carries no semantics, so it is
    useless for measuring retrieval quality and must never be the thing a
    quality claim is based on.
    """

    name = "deterministic-test-embedder"
    dimension = EMBEDDING_DIMENSION

    async def embed(self, texts: list[str]) -> list[list[float]]:
        return [self._vector(text) for text in texts]

    def _vector(self, text: str) -> list[float]:
        raw = bytearray()
        counter = 0
        seed = text.encode("utf-8")
        while len(raw) < EMBEDDING_DIMENSION * 2:
            raw += hashlib.blake2b(seed + counter.to_bytes(4, "big"), digest_size=64).digest()
            counter += 1
        vector = [
            (int.from_bytes(raw[i * 2 : i * 2 + 2], "big") / 32767.5) - 1.0
            for i in range(EMBEDDING_DIMENSION)
        ]
        return _l2_normalise(vector)


def build_embedder(*, provider: str, allow_test_double: bool = False) -> EmbeddingProvider:
    """Resolve a provider by name, refusing the test double outside tests.

    A fake embedder reaching production would not raise an error — retrieval
    would simply return unrelated passages, questions would drift off
    syllabus, and citations would point at the wrong pages. It would look like
    a quality problem rather than a configuration one, so the guard is here.
    """
    if provider == "sentence-transformers":
        return SentenceTransformerEmbedder()
    if provider == "deterministic":
        if not allow_test_double:
            raise ValueError(
                "The deterministic embedder carries no semantics and must not be used outside "
                "tests. Set the provider to 'sentence-transformers'."
            )
        return DeterministicEmbedder()
    raise ValueError(f"Unknown embedding provider {provider!r}")


def to_pgvector(vector: list[float]) -> str:
    """Render a vector in the text form pgvector parses.

    asyncpg has no native codec for halfvec, and registering one for a type
    that only appears on the write path is more machinery than it earns.
    """
    if len(vector) != EMBEDDING_DIMENSION:
        raise ValueError(
            f"Expected {EMBEDDING_DIMENSION} dimensions, got {len(vector)}. "
            "The column would reject this at write time."
        )
    return "[" + ",".join(f"{component:.7g}" for component in vector) + "]"
