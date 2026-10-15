"""The ingestion pipeline: stored file -> extracted pages -> chunks -> vectors.

Two properties matter more than throughput here.

**Resumable.** Audit OPS-03 asked for partial ingestion to leave usable chunks
behind rather than roll back. A 300-page PDF that fails on page 280 should not
re-embed the first 279. The job's `cursor` records how far the embedding pass
got, and chunk rows are written before they are embedded, so a retry fills in
`embedding is null` rather than starting over.

**Idempotent.** A retry must not duplicate chunks. `(document_id, chunk_index)`
is unique, so re-running the chunk pass is a no-op by construction rather than
by the worker remembering what it did.
"""

from __future__ import annotations

from dataclasses import dataclass

import asyncpg

from app.core.logging import get_logger
from app.domain.chunking import build_context_prefix, chunk_pages
from app.domain.embedding import EmbeddingProvider, to_pgvector
from app.domain.extraction import ExtractionFailed, extract
from app.services.storage import StorageClient

log = get_logger(__name__)

EMBED_BATCH_SIZE = 32


@dataclass(frozen=True, slots=True)
class IngestionResult:
    document_id: str
    chunks_written: int
    chunks_embedded: int
    needs_ocr: bool


async def run_extract_and_chunk(
    conn: asyncpg.Connection,
    storage: StorageClient,
    *,
    document_id: str,
    max_pages: int,
) -> IngestionResult:
    """Extract text and persist chunks. Does not embed."""
    document = await conn.fetchrow(
        """
        select d.id, d.user_id, d.subject_id, d.filename, d.storage_path, d.mime_type
          from public.document d
         where d.id = $1 and d.deleted_at is null
        """,
        document_id,
    )
    if document is None:
        raise LookupError(f"document {document_id} not found")

    await conn.execute(
        "update public.document set status = 'processing' where id = $1", document_id
    )

    data = await storage.download(document["storage_path"])

    try:
        extraction = extract(
            data, mime_type=document["mime_type"], max_pages=max_pages
        )
    except ExtractionFailed as failure:
        # A failed document says what went wrong and what to do about it. The
        # PRD's risk table promised exactly this instead of a silent bad
        # result (audit RAG-04).
        await conn.execute(
            """
            update public.document
               set status = 'failed', error_code = $2, error_message = $3, processed_at = now()
             where id = $1
            """,
            document_id,
            str(failure.code),
            failure.advice,
        )
        log.warning(
            "ingestion.extraction_failed",
            document_id=str(document_id),
            error_code=str(failure.code),
        )
        raise

    chunks = chunk_pages(extraction.pages)

    if not chunks and extraction.needs_ocr:
        # Not a failure: the file is fine and OCR is the next step. Leaving it
        # `processing` would look like a hang, so it is recorded explicitly.
        await conn.execute(
            """
            update public.document
               set status = 'pending', page_count = $2,
                   error_code = 'awaiting_ocr',
                   error_message = 'No text layer found; queued for text recognition.'
             where id = $1
            """,
            document_id,
            extraction.page_count,
        )
        return IngestionResult(str(document_id), 0, 0, needs_ocr=True)

    title = document["filename"]
    rows = [
        (
            document_id,
            document["subject_id"],
            document["user_id"],
            chunk.index,
            chunk.content,
            build_context_prefix(
                document_title=title, heading=chunk.heading, page_number=chunk.page_number
            ),
            chunk.page_number,
            chunk.token_count,
        )
        for chunk in chunks
    ]

    # ON CONFLICT DO NOTHING is what makes a retry safe: the unique index on
    # (document_id, chunk_index) turns a re-run into a no-op instead of a
    # duplicate-key crash that would strand the document.
    await conn.executemany(
        """
        insert into public.chunk
            (document_id, subject_id, user_id, chunk_index, content,
             context_prefix, page_number, token_count)
        values ($1, $2, $3, $4, $5, $6, $7, $8)
        on conflict (document_id, chunk_index) do nothing
        """,
        rows,
    )

    await conn.execute(
        "update public.document set page_count = $2, error_code = null, error_message = null "
        "where id = $1",
        document_id,
        extraction.page_count,
    )

    log.info(
        "ingestion.chunked",
        document_id=str(document_id),
        chunks=len(rows),
        pages=extraction.page_count,
        needs_ocr=extraction.needs_ocr,
    )
    return IngestionResult(str(document_id), len(rows), 0, needs_ocr=extraction.needs_ocr)


async def run_embed(
    conn: asyncpg.Connection,
    embedder: EmbeddingProvider,
    *,
    document_id: str,
) -> IngestionResult:
    """Embed every chunk of a document that does not yet have a vector.

    Selecting on `embedding is null` is what makes this resumable: a crash
    halfway leaves the completed vectors in place, and the retry picks up
    exactly where it stopped without re-paying for them.
    """
    embedded = 0

    while True:
        batch = await conn.fetch(
            """
            select id, chunk_index, content, context_prefix
              from public.chunk
             where document_id = $1 and embedding is null
             order by chunk_index
             limit $2
            """,
            document_id,
            EMBED_BATCH_SIZE,
        )
        if not batch:
            break

        texts = [
            f"{row['context_prefix']}\n\n{row['content']}"
            if row["context_prefix"]
            else row["content"]
            for row in batch
        ]
        vectors = await embedder.embed(texts)

        if len(vectors) != len(batch):
            raise RuntimeError(
                f"embedder returned {len(vectors)} vectors for {len(batch)} chunks"
            )

        await conn.executemany(
            "update public.chunk set embedding = $2::extensions.halfvec where id = $1",
            [(row["id"], to_pgvector(vector)) for row, vector in zip(batch, vectors, strict=True)],
        )
        embedded += len(batch)

    remaining = await conn.fetchval(
        "select count(*) from public.chunk where document_id = $1 and embedding is null",
        document_id,
    )
    total = await conn.fetchval(
        "select count(*) from public.chunk where document_id = $1", document_id
    )

    if remaining == 0 and total > 0:
        await conn.execute(
            "update public.document set status = 'ready', processed_at = now() where id = $1",
            document_id,
        )

    log.info(
        "ingestion.embedded",
        document_id=str(document_id),
        embedded=embedded,
        total=total,
        model=embedder.name,
    )
    return IngestionResult(str(document_id), total, embedded, needs_ocr=False)
