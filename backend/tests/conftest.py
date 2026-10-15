"""Shared fixtures.

Integration tests talk to the local Supabase Postgres. They are skipped
rather than failed when it is not running, so `pytest` stays useful without
Docker, while CI always has it up.
"""

from __future__ import annotations

import os
from collections.abc import AsyncIterator
from uuid import uuid4

import asyncpg
import pytest

DATABASE_URL = os.environ.get(
    "VIVAX_TEST_DATABASE_URL",
    "postgresql://postgres:postgres@127.0.0.1:55322/postgres",
)


@pytest.fixture(scope="session")
async def db_available() -> bool:
    try:
        conn = await asyncpg.connect(DATABASE_URL, timeout=3)
    except Exception:
        return False
    await conn.close()
    return True


@pytest.fixture
async def db(db_available: bool) -> AsyncIterator[asyncpg.Connection]:
    """A connection wrapped in a transaction that is always rolled back.

    Every test therefore sees the same clean schema, and nothing a test writes
    survives it.
    """
    if not db_available:
        pytest.skip("local Postgres not running — start it with `supabase start`")

    conn = await asyncpg.connect(DATABASE_URL)
    transaction = conn.transaction()
    await transaction.start()
    try:
        yield conn
    finally:
        await transaction.rollback()
        await conn.close()


async def make_student(conn: asyncpg.Connection, name: str = "Student") -> str:
    """Create an auth user; the trigger creates the profile."""
    user_id = str(uuid4())
    await conn.execute(
        """
        insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                                email_confirmed_at, created_at, updated_at,
                                raw_app_meta_data, raw_user_meta_data)
        values ($1, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
                $2, '', now(), now(), now(), '{}', $3::jsonb)
        """,
        user_id,
        f"{uuid4().hex[:12]}@example.test",
        f'{{"full_name": "{name}"}}',
    )
    return user_id


async def make_document(
    conn: asyncpg.Connection, user_id: str, *, subject_name: str | None = None
) -> tuple[str, str]:
    """Create a subject and a document under it. Returns (subject_id, document_id)."""
    subject_id = await conn.fetchval(
        "insert into public.subject (user_id, name) values ($1, $2) returning id",
        user_id,
        subject_name or f"Subject {uuid4().hex[:8]}",
    )
    document_id = await conn.fetchval(
        """
        insert into public.document (subject_id, user_id, filename, storage_path,
                                     mime_type, byte_size, content_hash, status)
        values ($1, $2, 'notes.pdf', $3, 'application/pdf', 4096, $4, 'pending')
        returning id
        """,
        subject_id,
        user_id,
        f"{user_id}/{uuid4()}/notes.pdf",
        f"sha256:{uuid4().hex}",
    )
    return str(subject_id), str(document_id)
