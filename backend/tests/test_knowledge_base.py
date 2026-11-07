import hashlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from app import db, knowledge_base
from app.knowledge_base import KnowledgeBaseError


class KnowledgeBaseTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.temp_dir.name) / "knowledge.db"
        self.patch_db = patch("app.db.DB_PATH", str(self.db_path))
        self.patch_db.start()
        db.init_db()

    def tearDown(self):
        self.patch_db.stop()
        self.temp_dir.cleanup()

    def test_chunking_is_deterministic_and_overlaps(self):
        source = ("Paragraph one. " * 120) + "\n\n" + ("Paragraph two. " * 120)
        first = knowledge_base.chunk_text(source)
        second = knowledge_base.chunk_text(source)
        self.assertEqual(first, second)
        self.assertGreater(len(first), 1)
        self.assertTrue(all(len(item["content"]) <= knowledge_base.CHUNK_SIZE for item in first))
        self.assertTrue(all(item["char_end"] > item["char_start"] for item in first))
        self.assertLessEqual(first[1]["char_start"], first[0]["char_end"])

    def test_ingest_text_document_persists_metadata_and_chunks(self):
        raw = ("EMA, RSI, Fibonacci và Elliott. " * 100).encode("utf-8")
        result = knowledge_base.ingest_document("phan-tich.md", raw, source="research-note")
        self.assertEqual(result["status"], "indexed")
        self.assertEqual(result["content_sha256"], hashlib.sha256(raw).hexdigest())
        self.assertEqual(result["mime_type"], "text/markdown")
        self.assertGreater(result["chunk_count"], 1)

        detail = knowledge_base.get_document(result["id"])
        self.assertEqual(len(detail["chunks"]), result["chunk_count"])
        self.assertEqual([chunk["chunk_index"] for chunk in detail["chunks"]],
                         list(range(result["chunk_count"])))
        self.assertEqual(detail["source"], "research-note")

    def test_exact_duplicate_is_detected_by_content_hash(self):
        raw = b"Knowledge base duplicate test"
        first = knowledge_base.ingest_document("one.txt", raw)
        duplicate = knowledge_base.ingest_document("renamed.txt", raw)
        self.assertEqual(first["status"], "indexed")
        self.assertEqual(duplicate["status"], "duplicate")
        self.assertEqual(first["id"], duplicate["id"])
        self.assertEqual(knowledge_base.list_documents()["total"], 1)

    def test_list_paginates_and_does_not_return_full_text(self):
        for index in range(3):
            knowledge_base.ingest_document(f"doc-{index}.txt", f"content {index}".encode())
        page = knowledge_base.list_documents(limit=2, offset=1)
        self.assertEqual(page["total"], 3)
        self.assertEqual(len(page["items"]), 2)
        self.assertNotIn("chunks", page["items"][0])
        self.assertNotIn("content", page["items"][0])

    def test_delete_cascades_chunks_and_unknown_id(self):
        result = knowledge_base.ingest_document("delete.txt", b"Delete this document")
        self.assertTrue(knowledge_base.delete_document(result["id"]))
        self.assertIsNone(knowledge_base.get_document(result["id"]))
        self.assertFalse(knowledge_base.delete_document(result["id"]))
        with db.connection() as conn:
            count = conn.execute("SELECT COUNT(*) FROM knowledge_chunks").fetchone()[0]
        self.assertEqual(count, 0)

    def test_unsupported_extension_and_invalid_utf8_are_rejected(self):
        with self.assertRaises(KnowledgeBaseError):
            knowledge_base.ingest_document("notes.exe", b"not allowed")
        with self.assertRaises(KnowledgeBaseError):
            knowledge_base.ingest_document("notes.txt", b"\xff\xfe")

    def test_empty_and_oversized_documents_are_rejected(self):
        with self.assertRaises(KnowledgeBaseError):
            knowledge_base.ingest_document("empty.txt", b"")
        with self.assertRaises(KnowledgeBaseError):
            knowledge_base.ingest_document(
                "large.txt", b"x" * (knowledge_base.MAX_UPLOAD_BYTES + 1)
            )

    def test_pdf_without_selectable_text_is_not_misrepresented_as_indexed(self):
        with self.assertRaises(KnowledgeBaseError):
            knowledge_base.ingest_document("scan.pdf", b"%PDF-1.4\n%%EOF")


if __name__ == "__main__":
    unittest.main()
