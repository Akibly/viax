"""Supabase Storage access.

Audit SEC-05: the bucket is private (see the migration), so nothing is
reachable by URL alone. Clients get short-lived signed URLs issued per
request; the backend reads objects with the service-role key.

Object keys are `<user_id>/<document_id>/<filename>`, because the storage RLS
policies compare the first path segment to the caller. A key that does not
start with the owner's id is unreachable by that user even though the row
says otherwise — so the key shape is a security property, not a convention,
and `object_key` is the only place it is constructed.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

import httpx

BUCKET = "documents"

_UNSAFE = re.compile(r"[^A-Za-z0-9._-]+")


def safe_filename(filename: str) -> str:
    """Strip anything that could traverse or confuse a path.

    A filename arrives from the client and lands in an object key. Without
    this, `../../other-user/notes.pdf` is a request worth trying.
    """
    cleaned = _UNSAFE.sub("_", filename.strip().replace("\\", "/").split("/")[-1])
    cleaned = cleaned.lstrip(".") or "upload"
    return cleaned[:120]


def object_key(*, user_id: str, document_id: str, filename: str) -> str:
    return f"{user_id}/{document_id}/{safe_filename(filename)}"


class StorageError(RuntimeError):
    pass


@dataclass(slots=True)
class StorageClient:
    base_url: str
    service_role_key: str
    timeout: float = 30.0

    @property
    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.service_role_key}",
            "apikey": self.service_role_key,
        }

    async def upload(self, key: str, data: bytes, content_type: str) -> None:
        url = f"{self.base_url}/storage/v1/object/{BUCKET}/{key}"
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.post(
                url,
                content=data,
                headers={**self._headers, "Content-Type": content_type, "x-upsert": "true"},
            )
        if response.status_code >= 400:
            raise StorageError(f"upload failed ({response.status_code}): {response.text[:200]}")

    async def download(self, key: str) -> bytes:
        url = f"{self.base_url}/storage/v1/object/{BUCKET}/{key}"
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.get(url, headers=self._headers)
        if response.status_code >= 400:
            raise StorageError(f"download failed ({response.status_code}): {response.text[:200]}")
        return response.content

    async def signed_url(self, key: str, *, expires_in: int = 300) -> str:
        """A short-lived read URL for the client.

        Deliberately short: the URL is a bearer credential for that object,
        and a long-lived one shared in a chat outlives any access decision.
        """
        url = f"{self.base_url}/storage/v1/object/sign/{BUCKET}/{key}"
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.post(
                url, json={"expiresIn": expires_in}, headers=self._headers
            )
        if response.status_code >= 400:
            raise StorageError(f"sign failed ({response.status_code}): {response.text[:200]}")
        return f"{self.base_url}/storage/v1{response.json()['signedURL']}"

    async def delete(self, key: str) -> None:
        url = f"{self.base_url}/storage/v1/object/{BUCKET}/{key}"
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.delete(url, headers=self._headers)
        if response.status_code >= 400 and response.status_code != 404:
            raise StorageError(f"delete failed ({response.status_code}): {response.text[:200]}")
