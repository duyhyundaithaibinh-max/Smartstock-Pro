"""Local document ingestion and deterministic chunking for the SmartStock knowledge base.

The module stores extracted text and metadata in SQLite. It does not call external
services, train models, or infer facts from uploaded documents.
"""
from __future__ import annotations

import csv
import hashlib
import io
import re
from pathlib import Path
from typing import Iterable

from pypdf import PdfReader

from .db import connection

SUPPORTED_EXTENSIONS = {".txt", ".md", ".csv", ".pdf"}
MAX_UPLOAD_BYTES = 10 * 1024 * 1024
MAX_EXTRACTED_CHARS = 2_000_000
CHUNK_SIZE = 1_200
CHUNK_OVERLAP = 150


class KnowledgeBaseError(ValueError):
    """A safe, user-correctable document ingestion error."""


def _extract_text(filename: str, raw: bytes) -> tuple[str, str]:
    extension = Path(filename).suffix.lower()
    if extension not in SUPPORTED_EXTENSIONS:
        raise KnowledgeBaseError("Unsupported file type. Use TXT, Markdown, CSV or PDF.")
    if not raw:
        raise KnowledgeBaseError("The uploaded document is empty.")

    if extension == ".pdf":
        if not raw.startswith(b"%PDF-"):
            raise KnowledgeBaseError("The uploaded file is not a valid PDF.")
        try:
            reader = PdfReader(io.BytesIO(raw), strict=True)
            pages = []
            for index, page in enumerate(reader.pages):
                page_text = (page.extract_text() or "").strip()
                if page_text:
                    pages.append(f"[Page {index + 1}]\n{page_text}")
                if sum(len(item) for item in pages) > MAX_EXTRACTED_CHARS:
                    raise KnowledgeBaseError("Extracted document text exceeds the 2 MB character limit.")
            text = "\n\n".join(pages)
        except KnowledgeBaseError:
            raise
        except Exception as exc:
            raise KnowledgeBaseError("Unable to read this PDF. Check that it is not encrypted or damaged.") from exc
        if not text.strip():
            raise KnowledgeBaseError("No selectable text found in PDF. Scanned PDFs require OCR and are not supported yet.")
        return text, "application/pdf"

    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise KnowledgeBaseError("Text documents must use UTF-8 encoding.") from exc
    if not text.strip():
        raise KnowledgeBaseError("The uploaded document contains no readable text.")
    if len(text) > MAX_EXTRACTED_CHARS:
        raise KnowledgeBaseError("Extracted document text exceeds the 2 MB character limit.")
    if extension == ".csv":
        try:
            rows = list(csv.reader(io.StringIO(text)))
        except csv.Error as exc:
            raise KnowledgeBaseError("Unable to parse CSV document.") from exc
        if not rows or not any(any(cell.strip() for cell in row) for row in rows):
            raise KnowledgeBaseError("CSV document contains no data.")
    mime = {
        ".txt": "text/plain",
        ".md": "text/markdown",
        ".csv": "text/csv",
    }[extension]
    return text, mime


def chunk_text(text: str, chunk_size: int = CHUNK_SIZE, overlap: int = CHUNK_OVERLAP) -> list[dict]:
    """Split text deterministically, preferring paragraph/line boundaries."""
    if chunk_size < 100 or overlap < 0 or overlap >= chunk_size:
        raise ValueError("Invalid chunk size or overlap")
    normalized = text.replace("\r\n", "\n").replace("\r", "\n").strip()
    if not normalized:
        return []

    chunks = []
    start = 0
    length = len(normalized)
    while start < length:
        hard_end = min(start + chunk_size, length)
        end = hard_end
        if hard_end < length:
            boundary = max(
                normalized.rfind("\n\n", start + chunk_size // 2, hard_end),
                normalized.rfind("\n", start + chunk_size // 2, hard_end),
                normalized.rfind(" ", start + chunk_size // 2, hard_end),
            )
            if boundary > start:
                end = boundary
        content = normalized[start:end].strip()
        if content:
            actual_start = normalized.find(content, start, end + 1)
            chunks.append({
                "chunk_index": len(chunks),
                "content": content,
                "char_start": actual_start if actual_start >= 0 else start,
                "char_end": (actual_start if actual_start >= 0 else start) + len(content),
            })
        if end >= length:
            break
        start = max(start + 1, end - overlap)
    return chunks


def ingest_document(filename: str, raw: bytes, source: str = "user_upload", title: str | None = None) -> dict:
    safe_name = Path(filename.replace("\\", "/")).name.strip()
    if not safe_name or len(safe_name) > 255:
        raise KnowledgeBaseError("Filename must contain 1 to 255 characters.")
    if len(raw) > MAX_UPLOAD_BYTES:
        raise KnowledgeBaseError("Document exceeds the 10 MB upload limit.")
    source = source.strip()
    if not source or len(source) > 100:
        raise KnowledgeBaseError("Source must contain 1 to 100 characters.")
    extracted, mime_type = _extract_text(safe_name, raw)
    chunks = chunk_text(extracted)
    if not chunks:
        raise KnowledgeBaseError("No text chunks could be created.")
    digest = hashlib.sha256(raw).hexdigest()
    document_title = (title or Path(safe_name).stem).strip()
    if not document_title or len(document_title) > 200:
        raise KnowledgeBaseError("Title must contain 1 to 200 characters.")

    with connection() as conn:
        existing = conn.execute(
            "SELECT id, filename, title, created_at FROM knowledge_documents WHERE content_sha256=?",
            (digest,),
        ).fetchone()
        if existing:
            return {"status": "duplicate", **dict(existing), "content_sha256": digest}

        cursor = conn.execute(
            """INSERT INTO knowledge_documents
               (filename,title,mime_type,source,size_bytes,content_sha256,character_count,chunk_count)
               VALUES(?,?,?,?,?,?,?,?)""",
            (safe_name, document_title, mime_type, source, len(raw), digest, len(extracted), len(chunks)),
        )
        document_id = cursor.lastrowid
        conn.executemany(
            """INSERT INTO knowledge_chunks(document_id,chunk_index,content,char_start,char_end)
               VALUES(?,?,?,?,?)""",
            [
                (document_id, item["chunk_index"], item["content"], item["char_start"], item["char_end"])
                for item in chunks
            ],
        )
        row = conn.execute("SELECT * FROM knowledge_documents WHERE id=?", (document_id,)).fetchone()
    return {"status": "indexed", **dict(row)}


def list_documents(limit: int = 100, offset: int = 0) -> dict:
    with connection() as conn:
        total = conn.execute("SELECT COUNT(*) FROM knowledge_documents").fetchone()[0]
        rows = conn.execute(
            """SELECT id,filename,title,mime_type,source,size_bytes,content_sha256,
                      character_count,chunk_count,created_at
               FROM knowledge_documents ORDER BY created_at DESC,id DESC LIMIT ? OFFSET ?""",
            (limit, offset),
        ).fetchall()
    return {"total": total, "limit": limit, "offset": offset, "items": [dict(row) for row in rows]}


def get_document(document_id: int, include_chunks: bool = True) -> dict | None:
    with connection() as conn:
        row = conn.execute(
            """SELECT id,filename,title,mime_type,source,size_bytes,content_sha256,
                      character_count,chunk_count,created_at
               FROM knowledge_documents WHERE id=?""",
            (document_id,),
        ).fetchone()
        if row is None:
            return None
        result = dict(row)
        if include_chunks:
            result["chunks"] = [
                dict(item) for item in conn.execute(
                    """SELECT chunk_index,content,char_start,char_end
                       FROM knowledge_chunks WHERE document_id=? ORDER BY chunk_index""",
                    (document_id,),
                ).fetchall()
            ]
    return result


def delete_document(document_id: int) -> bool:
    with connection() as conn:
        cursor = conn.execute("DELETE FROM knowledge_documents WHERE id=?", (document_id,))
        return cursor.rowcount > 0
