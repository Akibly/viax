"""End-to-end ingestion against real Postgres and real Supabase Storage.

The properties under test are the ones that only appear when something goes
wrong halfway: resumability and idempotence. A pipeline that works on the
happy path and re-embeds 300 pages after a blip is a pipeline that will empty
the API budget the first time a worker restarts.
"""

from __future__ import annotations

import asyncpg
import pytest

from app.core.config import get_settings
from app.domain.embedding import DeterministicEmbedder
from app.services.ingestion import run_embed, run_extract_and_chunk
from app.services.storage import StorageClient, object_key, safe_filename
from tests.conftest import make_student

pytestmark = pytest.mark.integration

NOTES = """UNIT 3 — DEADLOCK

A deadlock is a situation in which two or more processes are unable to proceed
because each is waiting for a resource held by another.

3.1 Necessary Conditions

Mutual exclusion, hold and wait, no preemption, and circular wait must all
hold simultaneously for a deadlock to occur.

3.2 Banker's Algorithm

The Banker's Algorithm checks whether granting a request leaves the system in
a safe state before allowing it to proceed.
"""


@pytest.fixture
def storage() -> StorageClient:
    settings = get_settings()
    return StorageClient(
        base_url=settings.supabase_url,
        service_role_key=settings.supabase_service_role_key.get_secret_value(),
    )


async def _seed(
    db: asyncpg.Connection, storage: StorageClient, body: bytes = NOTES.encode()
) -> tuple[str, str, str]:
    """Create a subject and document, and put a real object in the bucket."""
    user = await make_student(db)
    subject = await db.fetchval(
        "insert into public.subject (user_id, name) values ($1, 'Operating Systems') returning id",
        user,
    )
    document = await db.fetchval(
        """
        insert into public.document (subject_id, user_id, filename, storage_path,
                                     mime_type, byte_size, content_hash, status)
        values ($1, $2, 'os-notes.txt', 'placeholder', 'text/plain', $3, $4, 'pending')
        returning id
        """,
        subject,
        user,
        len(body),
        f"sha256:{abs(hash(body))}",
    )
    key = object_key(user_id=str(user), document_id=str(document), filename="os-notes.txt")
    await db.execute(
        "update public.document set storage_path = $2 where id = $1", document, key
    )
    await storage.upload(key, body, "text/plain")
    return str(user), str(subject), str(document)


class TestKeyConstruction:
    def test_traversal_is_stripped_from_filenames(self) -> None:
        """A filename comes from the client and lands in an object key whose
        first segment is the security boundary."""
        assert "/" not in safe_filename("../../victim/notes.pdf")
        assert safe_filename("../../victim/notes.pdf") == "notes.pdf"
        assert safe_filename("...") == "upload"
        assert safe_filename("") == "upload"

    def test_key_is_prefixed_with_the_owner(self) -> None:
        key = object_key(user_id="u1", document_id="d1", filename="a b.pdf")
        assert key.startswith("u1/")
        assert key == "u1/d1/a_b.pdf"


class TestPipeline:
    async def test_full_pass_leaves_the_document_ready(
        self, db: asyncpg.Connection, storage: StorageClient
    ) -> None:
        _, _, document = await _seed(db, storage)

        chunked = await run_extract_and_chunk(
            db, storage, document_id=document, max_pages=300
        )
        assert chunked.chunks_written > 0

        # Not ready until every chunk is embedded — a half-embedded document
        # would retrieve unpredictably.
        assert (
            await db.fetchval("select status from public.document where id = $1", document)
            != "ready"
        )

        embedded = await run_embed(db, DeterministicEmbedder(), document_id=document)
        assert embedded.chunks_embedded == chunked.chunks_written
        assert (
            await db.fetchval("select status from public.document where id = $1", document)
            == "ready"
        )
        assert (
            await db.fetchval(
                "select count(*) from public.chunk where document_id = $1 and embedding is null",
                document,
            )
            == 0
        )

    async def test_chunks_keep_their_section_and_page(
        self, db: asyncpg.Connection, storage: StorageClient
    ) -> None:
        _, _, document = await _seed(db, storage)
        await run_extract_and_chunk(db, storage, document_id=document, max_pages=300)

        rows = await db.fetch(
            "select chunk_index, content, context_prefix, page_number "
            "from public.chunk where document_id = $1 order by chunk_index",
            document,
        )
        assert [r["chunk_index"] for r in rows] == list(range(len(rows)))
        assert all(r["page_number"] >= 1 for r in rows)
        # Contextual retrieval: the section name is embedded with the chunk so
        # "the four conditions" retrieves for "deadlock".
        assert any("Banker" in (r["context_prefix"] or "") for r in rows)
        assert all("os-notes.txt" in (r["context_prefix"] or "") for r in rows)

    async def test_full_text_index_is_populated(
        self, db: asyncpg.Connection, storage: StorageClient
    ) -> None:
        """The lexical half of hybrid retrieval, generated by the column."""
        _, _, document = await _seed(db, storage)
        await run_extract_and_chunk(db, storage, document_id=document, max_pages=300)

        hits = await db.fetchval(
            "select count(*) from public.chunk "
            "where document_id = $1 and fts @@ plainto_tsquery('english', 'banker algorithm')",
            document,
        )
        assert hits >= 1


class TestResumability:
    async def test_rerunning_chunking_does_not_duplicate(
        self, db: asyncpg.Connection, storage: StorageClient
    ) -> None:
        """A retry after a crash must be a no-op, not a duplicate-key crash
        that strands the document."""
        _, _, document = await _seed(db, storage)
        first = await run_extract_and_chunk(db, storage, document_id=document, max_pages=300)
        await run_extract_and_chunk(db, storage, document_id=document, max_pages=300)

        total = await db.fetchval(
            "select count(*) from public.chunk where document_id = $1", document
        )
        assert total == first.chunks_written

    async def test_embedding_resumes_instead_of_restarting(
        self, db: asyncpg.Connection, storage: StorageClient
    ) -> None:
        """The property that keeps a worker restart from re-paying for every
        vector in a 300-page document."""
        _, _, document = await _seed(db, storage)
        await run_extract_and_chunk(db, storage, document_id=document, max_pages=300)
        await run_embed(db, DeterministicEmbedder(), document_id=document)

        # Simulate a crash that lost exactly one vector.
        await db.execute(
            "update public.chunk set embedding = null "
            "where id = (select id from public.chunk where document_id = $1 "
            "            order by chunk_index desc limit 1)",
            document,
        )

        second = await run_embed(db, DeterministicEmbedder(), document_id=document)
        assert second.chunks_embedded == 1, "should re-embed only the missing vector"

    async def test_an_unreadable_file_fails_with_actionable_advice(
        self, db: asyncpg.Connection, storage: StorageClient
    ) -> None:
        from app.domain.extraction import ExtractionFailed

        _, _, document = await _seed(db, storage, body=b"   \n\n   ")

        with pytest.raises(ExtractionFailed):
            await run_extract_and_chunk(db, storage, document_id=document, max_pages=300)

        row = await db.fetchrow(
            "select status, error_code, error_message from public.document where id = $1",
            document,
        )
        assert row["status"] == "failed"
        assert row["error_code"] == "empty"
        assert row["error_message"], "a failed document must say what to do about it"

    async def test_ownership_columns_are_populated_for_rls(
        self, db: asyncpg.Connection, storage: StorageClient
    ) -> None:
        """Chunks carry denormalised user_id/subject_id; the RLS policies read
        them, so a null here is a chunk nobody can retrieve."""
        user, subject, document = await _seed(db, storage)
        await run_extract_and_chunk(db, storage, document_id=document, max_pages=300)

        mismatched = await db.fetchval(
            "select count(*) from public.chunk "
            "where document_id = $1 and (user_id <> $2 or subject_id <> $3)",
            document,
            user,
            subject,
        )
        assert mismatched == 0
