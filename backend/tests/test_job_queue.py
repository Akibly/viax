"""Job queue semantics, against a real Postgres.

Audit OPS-03: the architecture drew an async ingestion pipeline and named no
queue. This is the queue, and these are the properties that make it safe to
run more than one worker — none of which can be verified without two real
connections holding two real transactions.
"""

from __future__ import annotations

import asyncpg
import pytest

from tests.conftest import DATABASE_URL, make_document, make_student

pytestmark = pytest.mark.integration


async def _queue(conn: asyncpg.Connection, document_id: str, user_id: str, kind: str) -> str:
    return str(
        await conn.fetchval(
            """
            insert into public.ingestion_job (document_id, user_id, kind)
            values ($1, $2, $3::public.job_kind) returning id
            """,
            document_id,
            user_id,
            kind,
        )
    )


class TestClaiming:
    async def test_claim_marks_running_and_records_the_worker(
        self, db: asyncpg.Connection
    ) -> None:
        user = await make_student(db)
        _, document = await make_document(db, user)
        await _queue(db, document, user, "extract")

        job = await db.fetchrow("select * from app.claim_job($1, 300)", "worker-a")

        assert job is not None and job["id"] is not None
        assert job["status"] == "running"
        assert job["leased_by"] == "worker-a"
        assert job["attempts"] == 1
        assert job["leased_until"] is not None

    async def test_empty_queue_returns_nothing(self, db: asyncpg.Connection) -> None:
        """A worker polling an empty queue must not spin on a phantom row."""
        job = await db.fetchrow("select * from app.claim_job($1, 300)", "worker-a")
        assert job is None or job["id"] is None

    async def test_a_job_scheduled_for_later_is_not_claimed(
        self, db: asyncpg.Connection
    ) -> None:
        """Backoff is meaningless if the claim query ignores run_after."""
        user = await make_student(db)
        _, document = await make_document(db, user)
        job_id = await _queue(db, document, user, "extract")
        await db.execute(
            "update public.ingestion_job set run_after = now() + interval '1 hour' where id = $1",
            job_id,
        )

        job = await db.fetchrow("select * from app.claim_job($1, 300)", "worker-a")
        assert job is None or job["id"] is None

    async def test_kind_filter_is_respected(self, db: asyncpg.Connection) -> None:
        user = await make_student(db)
        _, document = await make_document(db, user)
        await _queue(db, document, user, "embed")

        wrong = await db.fetchrow(
            "select * from app.claim_job($1, 300, $2::public.job_kind[])",
            "worker-a",
            ["extract"],
        )
        assert wrong is None or wrong["id"] is None

        right = await db.fetchrow(
            "select * from app.claim_job($1, 300, $2::public.job_kind[])",
            "worker-a",
            ["embed"],
        )
        assert right is not None and right["kind"] == "embed"


class TestConcurrency:
    async def test_two_workers_never_claim_the_same_job(
        self, db_available: bool
    ) -> None:
        """The property the whole design rests on.

        Without SKIP LOCKED the second worker blocks on the first's row lock
        and throughput collapses to one worker; worse, a naive
        select-then-update hands the same job to both and the document is
        embedded twice — paying twice and racing on the write.

        This needs two real connections: a single transaction cannot observe
        its own lock contention.
        """
        # Three raw connections, so the shared `db` fixture cannot supply them
        # — but the availability check still has to run, or this fails with a
        # connection error instead of skipping like every other integration
        # test in the suite.
        if not db_available:
            pytest.skip("local Postgres not running — start it with `supabase start`")

        setup = await asyncpg.connect(DATABASE_URL)
        worker_a = await asyncpg.connect(DATABASE_URL)
        worker_b = await asyncpg.connect(DATABASE_URL)
        try:
            user = await make_student(setup)
            _, document_one = await make_document(setup, user)
            _, document_two = await make_document(setup, user)
            first = await _queue(setup, document_one, user, "extract")
            second = await _queue(setup, document_two, user, "extract")

            tx_a = worker_a.transaction()
            tx_b = worker_b.transaction()
            await tx_a.start()
            await tx_b.start()

            claimed_a = await worker_a.fetchrow("select * from app.claim_job($1, 300)", "a")
            # B claims while A still holds its transaction open.
            claimed_b = await worker_b.fetchrow("select * from app.claim_job($1, 300)", "b")

            assert claimed_a is not None and claimed_a["id"] is not None
            assert claimed_b is not None and claimed_b["id"] is not None, (
                "worker B got nothing — SKIP LOCKED is not in effect and B blocked on A's row"
            )
            assert claimed_a["id"] != claimed_b["id"], "the same job was handed to two workers"
            assert {str(claimed_a["id"]), str(claimed_b["id"])} == {first, second}

            await tx_a.rollback()
            await tx_b.rollback()
        finally:
            await setup.execute(
                "delete from auth.users where email like '%@example.test'"
            )
            await setup.close()
            await worker_a.close()
            await worker_b.close()

    async def test_duplicate_active_jobs_are_rejected(self, db: asyncpg.Connection) -> None:
        """Re-queueing an in-flight document must be a no-op, not a second
        charge for the same embedding work."""
        user = await make_student(db)
        _, document = await make_document(db, user)
        await _queue(db, document, user, "extract")

        with pytest.raises(asyncpg.UniqueViolationError):
            await _queue(db, document, user, "extract")

    async def test_a_finished_job_frees_the_slot_for_a_rerun(
        self, db: asyncpg.Connection
    ) -> None:
        """The uniqueness is on *active* jobs only, so a document can be
        re-ingested after an edit."""
        user = await make_student(db)
        _, document = await make_document(db, user)
        job_id = await _queue(db, document, user, "extract")
        await db.execute(
            "update public.ingestion_job set status = 'succeeded', finished_at = now() "
            "where id = $1",
            job_id,
        )

        assert await _queue(db, document, user, "extract")


class TestLeaseReaping:
    async def test_expired_lease_is_requeued_with_backoff(
        self, db: asyncpg.Connection
    ) -> None:
        """A killed worker must not leave a document stuck in `processing`
        forever — which the student experiences as an upload that never
        finishes."""
        user = await make_student(db)
        _, document = await make_document(db, user)
        await _queue(db, document, user, "extract")
        await db.fetchrow("select * from app.claim_job($1, 300)", "doomed-worker")
        await db.execute(
            "update public.ingestion_job set leased_until = now() - interval '1 minute' "
            "where leased_by = 'doomed-worker'"
        )

        reclaimed = await db.fetchval("select app.reap_expired_leases()")
        assert reclaimed == 1

        row = await db.fetchrow(
            "select status, leased_by, run_after, error_code from public.ingestion_job "
            "where document_id = $1",
            document,
        )
        assert row["status"] == "queued"
        assert row["leased_by"] is None
        assert row["error_code"] == "worker_lease_expired"
        assert row["run_after"] > await db.fetchval("select now()")

    async def test_a_job_that_exhausts_its_attempts_goes_dead(
        self, db: asyncpg.Connection
    ) -> None:
        """Retrying forever turns one poisonous document into an infinite
        bill."""
        user = await make_student(db)
        _, document = await make_document(db, user)
        job_id = await _queue(db, document, user, "extract")
        await db.execute(
            "update public.ingestion_job set attempts = max_attempts where id = $1", job_id
        )
        await db.execute(
            "update public.ingestion_job set status = 'running', "
            "leased_until = now() - interval '1 minute', leased_by = 'w' where id = $1",
            job_id,
        )

        await db.fetchval("select app.reap_expired_leases()")

        assert (
            await db.fetchval("select status from public.ingestion_job where id = $1", job_id)
            == "dead"
        )

    async def test_a_live_lease_is_left_alone(self, db: asyncpg.Connection) -> None:
        user = await make_student(db)
        _, document = await make_document(db, user)
        await _queue(db, document, user, "extract")
        await db.fetchrow("select * from app.claim_job($1, 300)", "healthy-worker")

        assert await db.fetchval("select app.reap_expired_leases()") == 0


class TestInvariants:
    async def test_a_failed_job_must_say_why(self, db: asyncpg.Connection) -> None:
        user = await make_student(db)
        _, document = await make_document(db, user)
        job_id = await _queue(db, document, user, "extract")

        with pytest.raises(asyncpg.CheckViolationError):
            await db.execute(
                "update public.ingestion_job set status = 'failed', leased_until = null "
                "where id = $1",
                job_id,
            )

    async def test_students_cannot_see_each_others_ingestion_progress(
        self, db: asyncpg.Connection
    ) -> None:
        alice = await make_student(db, "Alice")
        bob = await make_student(db, "Bob")
        _, document = await make_document(db, alice)
        await _queue(db, document, alice, "extract")

        await db.execute("set local role authenticated")
        await db.execute(
            "select set_config('request.jwt.claims', $1, true)",
            f'{{"sub": "{bob}", "role": "authenticated"}}',
        )
        assert await db.fetchval("select count(*) from public.ingestion_job") == 0

        await db.execute(
            "select set_config('request.jwt.claims', $1, true)",
            f'{{"sub": "{alice}", "role": "authenticated"}}',
        )
        assert await db.fetchval("select count(*) from public.ingestion_job") == 1
