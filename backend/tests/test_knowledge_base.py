import hashlib
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier, Lock
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

    def test_chunk_offsets_reference_original_text_including_whitespace_and_crlf(self):
        source = "\r\n  Fibonacci retracement\r\n\r\nElliott Wave  "
        chunks = knowledge_base.chunk_text(source, chunk_size=100, overlap=10)
        self.assertEqual(len(chunks), 1)
        chunk = chunks[0]
        self.assertEqual(source[chunk["char_start"]:chunk["char_end"]], chunk["content"])
        self.assertEqual(chunk["char_start"], source.index("Fibonacci"))
        self.assertEqual(chunk["char_end"], source.index("Wave") + len("Wave"))

    def test_ingest_text_document_persists_metadata_and_chunks(self):
        raw = ("EMA, RSI, Fibonacci và Elliott. " * 100).encode("utf-8")
        result = knowledge_base.ingest_document("phan-tich.md", raw, source="research-note")
        self.assertEqual(result["status"], "indexed")
        self.assertEqual(result["category"], "other")
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

    def test_concurrent_duplicate_ingestion_is_serialized_across_connections(self):
        from contextlib import contextmanager

        raw = b"Two simultaneous uploads must resolve to one knowledge document"
        start_together = Barrier(2)
        connection_lock = Lock()
        opened_connections = []
        original_connection = db.connection

        @contextmanager
        def tracking_connection():
            with original_connection() as conn:
                with connection_lock:
                    opened_connections.append(conn)
                yield conn

        def ingest(filename):
            start_together.wait(timeout=5)
            return knowledge_base.ingest_document(filename, raw)

        with patch.object(knowledge_base, "connection", tracking_connection):
            with ThreadPoolExecutor(max_workers=2) as executor:
                futures = [
                    executor.submit(ingest, "parallel-one.txt"),
                    executor.submit(ingest, "parallel-two.txt"),
                ]
                results = [future.result(timeout=10) for future in futures]

        self.assertEqual(len(opened_connections), 2)
        self.assertIsNot(opened_connections[0], opened_connections[1])
        self.assertCountEqual([item["status"] for item in results], ["indexed", "duplicate"])
        self.assertEqual(results[0]["id"], results[1]["id"])
        self.assertEqual(db.connection.__name__, original_connection.__name__)

        with db.connection() as conn:
            document_count = conn.execute(
                "SELECT COUNT(*) FROM knowledge_documents"
            ).fetchone()[0]
            chunk_count = conn.execute(
                "SELECT COUNT(*) FROM knowledge_chunks"
            ).fetchone()[0]
            stored_chunk_count = conn.execute(
                "SELECT chunk_count FROM knowledge_documents WHERE id=?",
                (results[0]["id"],),
            ).fetchone()[0]

        self.assertEqual(document_count, 1)
        self.assertEqual(chunk_count, stored_chunk_count)
        self.assertGreater(chunk_count, 0)

    def test_duplicate_detection_starts_inside_write_transaction(self):
        from contextlib import contextmanager

        raw = b"Concurrent duplicate upload lock test"
        first = knowledge_base.ingest_document("first.txt", raw)
        transaction_states = []
        original_connection = db.connection

        @contextmanager
        def observing_connection():
            with original_connection() as conn:
                class ConnectionProxy:
                    def __getattr__(self, name):
                        return getattr(conn, name)

                    def execute(self, sql, parameters=()):
                        if "SELECT id, filename, title, created_at" in sql:
                            transaction_states.append(conn.in_transaction)
                        return conn.execute(sql, parameters)

                yield ConnectionProxy()

        with patch.object(knowledge_base, "connection", observing_connection):
            duplicate = knowledge_base.ingest_document("second.txt", raw)

        self.assertEqual(duplicate["status"], "duplicate")
        self.assertEqual(duplicate["id"], first["id"])
        self.assertEqual(transaction_states, [True])

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
