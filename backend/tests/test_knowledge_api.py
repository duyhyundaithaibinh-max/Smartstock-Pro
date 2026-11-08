import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from app import db, knowledge_base
from app.routers import market


class KnowledgeApiContractTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.temp_dir.name) / "knowledge-api.db"
        self.patch_db = patch("app.db.DB_PATH", str(self.db_path))
        self.patch_db.start()
        db.init_db()

    def tearDown(self):
        self.patch_db.stop()
        self.temp_dir.cleanup()

    def test_search_api_returns_citation_and_exact_source_locator(self):
        raw = ("Fibonacci time projection dùng số nến giao dịch. " * 30).encode("utf-8")
        document = knowledge_base.ingest_document(
            "fibonacci.md", raw, source="user_research", title="Fibonacci time"
        )

        response = market.search_knowledge_documents("Fibonacci time projection", top_k=3)

        self.assertEqual(response["query"], "Fibonacci time projection")
        self.assertGreaterEqual(response["total"], 1)
        hit = response["results"][0]
        passage = response["retrieval_context"]["passages"][0]
        self.assertEqual(hit["document_id"], document["id"])
        self.assertEqual(hit["category"], "other")
        self.assertEqual(passage["citation_id"], hit["citation_id"])
        self.assertEqual(passage["document_id"], hit["document_id"])
        self.assertEqual(passage["chunk_id"], hit["chunk_id"])
        self.assertEqual(passage["chunk_index"], hit["chunk_index"])
        self.assertEqual(passage["char_start"], hit["char_start"])
        self.assertEqual(passage["char_end"], hit["char_end"])
        self.assertEqual(passage["content_sha256"], hit["content_sha256"])
        self.assertEqual(response["retrieval_context"]["status"], "ready")

    def test_category_filter_limits_search_and_document_list(self):
        fibonacci = knowledge_base.ingest_document(
            "fib.md", b"Fibonacci retracement and time projection", category="fibonacci"
        )
        knowledge_base.ingest_document(
            "wyckoff.md", b"Wyckoff accumulation distribution volume", category="wyckoff"
        )

        results = market.search_knowledge_documents("accumulation Fibonacci", top_k=10, category="fibonacci")
        self.assertGreaterEqual(results["total"], 1)
        self.assertTrue(all(item["category"] == "fibonacci" for item in results["results"]))
        listed = market.list_knowledge_documents(limit=100, offset=0, category="fibonacci")
        self.assertEqual(listed["total"], 1)
        self.assertEqual(listed["items"][0]["id"], fibonacci["id"])

    def test_invalid_category_is_rejected(self):
        with self.assertRaises(knowledge_base.KnowledgeBaseError):
            knowledge_base.ingest_document("bad.txt", b"content", category="unknown")

    def test_search_api_returns_explicit_no_evidence_state(self):
        response = market.search_knowledge_documents("khong co tai lieu nay", top_k=5)

        self.assertEqual(response["total"], 0)
        self.assertEqual(response["results"], [])
        self.assertEqual(response["retrieval_context"]["status"], "no_evidence")
        self.assertEqual(response["retrieval_context"]["passages"], [])
        self.assertEqual(response["retrieval_context"]["citations"], [])

    def test_document_delete_removes_it_from_subsequent_search(self):
        document = knowledge_base.ingest_document(
            "elliott.txt", b"Elliott Wave impulse structure and invalidation."
        )
        self.assertGreater(
            market.search_knowledge_documents("Elliott Wave", top_k=5)["total"], 0
        )

        result = market.delete_knowledge_document(document["id"])

        self.assertEqual(result, {"document_id": document["id"], "status": "deleted"})
        response = market.search_knowledge_documents("Elliott Wave", top_k=5)
        self.assertEqual(response["total"], 0)
        self.assertEqual(response["retrieval_context"]["status"], "no_evidence")

    def test_document_list_does_not_expose_chunk_text(self):
        knowledge_base.ingest_document("private.txt", b"Local research content")
        response = market.list_knowledge_documents(limit=100, offset=0)

        self.assertEqual(response["total"], 1)
        self.assertNotIn("chunks", response["items"][0])
        self.assertNotIn("content", response["items"][0])


if __name__ == "__main__":
    unittest.main()
