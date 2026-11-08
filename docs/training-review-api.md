# Training Review API contract (SP-022)

All routes below require an authenticated owner Bearer session. A missing/invalid token returns 401. A legacy SMARTSTOCK_API_TOKEN principal is not a human reviewer and receives 403 on review operations. The server derives reviewer_user_id from the owner session; clients must not send it.

## Existing example lifecycle

| Method | Path | Contract |
|---|---|---|
| GET | /api/v1/training/examples?limit=100&offset=0&status=draft | Existing list contract; status may be draft, approved, or rejected. Response includes revision. |
| POST | /api/v1/training/examples | Existing create contract; returns 201, status draft, revision 1. |
| POST | /api/v1/training/examples/{id}/approve | Draft-only; returns the existing example response (200) and atomically records an approved event. Repeated/non-draft transition: 409. |
| POST | /api/v1/training/examples/{id}/reject | Draft-only; body {"reason":"Source does not support this answer."}. Reason is trimmed, 1–1000 chars. Returns 200; invalid reason 422; missing example 404; non-draft 409. |
| PATCH | /api/v1/training/examples/{id} | Draft-only optimistic edit. Requires expected_revision plus at least one of question, expected_answer, topic, citation_ids. Only those four fields are editable. Returns incremented revision. Invalid fields/citations 422; stale revision/non-draft 409; missing example 404. |
| DELETE | /api/v1/training/examples/{id} | Existing hard-delete contract is retained. Review and quality rows cascade with the example. |

### PATCH example

Request:
{"expected_revision":2,"topic":"elliott-wave","question":"What is the strict rule for Elliott Wave three?"}

Response is the existing example representation with revision 3. expected_revision is a concurrency guard, not a field that is stored.

## Review event history

GET /api/v1/training/examples/{id}/review-events?limit=50&offset=0

- Chronological order, oldest first; stable tie-breaker is event ID.
- limit is 1–100 (default 50); offset is zero or greater (default 0).
- Empty history returns 200 with items: [] and total: 0.
- Missing example returns 404; missing/invalid owner token 401; legacy shared token 403; invalid pagination 422.
- Event actions: approved, rejected, edited.
- reviewer_user_id is the server-authenticated owner ID; reviewer_label is the non-identifying single-owner label Owner.
- changed_fields is an array; approval/rejection use an empty array.
- The API never returns session tokens, password material, bootstrap secrets or account credentials.
- Events are append-only while the parent example exists. Hard deletion cascades event rows by the explicitly retained MVP-1 policy.

Response:
{
  "example_id": 12,
  "items": [{
    "id": 31,
    "example_id": 12,
    "action": "rejected",
    "reason": "Source does not support this answer.",
    "revision_from": 2,
    "revision_to": 2,
    "changed_fields": [],
    "reviewer_user_id": 1,
    "reviewer_label": "Owner",
    "created_at": "2026-11-09T00:00:00"
  }],
  "count": 1,
  "total": 1,
  "limit": 50,
  "offset": 0
}

## Manual quality review (separate from lifecycle events)

- POST /api/v1/training/examples/{id}/quality-reviews body:
  {"score":0,"rubric_version":"qa-quality-v1","rationale":"Manual review rationale with enough detail."}
- score is a strict integer 0–100 inclusive; booleans/floats/null are invalid.
- Only supported rubric: qa-quality-v1; rationale is required (10–2000 trimmed characters).
- 201 creates a new append-only review associated with the current example revision.
- Manual quality review is intentionally allowed for every existing status: draft, approved, and rejected. It does not change status, readiness, export eligibility or prediction evaluator metrics.
- GET /api/v1/training/examples/{id}/quality-reviews remains a separate history endpoint.

## Compatibility / behavior guarantees

- CREATE, APPROVE, DELETE response status/shape, list fields, readiness response and approved-only JSONL export remain compatible; list adds/retains revision.
- Approval now adds an audit row in the same SQLite transaction as the status transition; a failed audit insert rolls back the status update.
- Existing approved rows from before audit support are preserved without fabricated retrospective events.
- Rejected examples are excluded from training readiness and export.
- Prediction evaluator schema and behavior are unchanged; manual quality score is not a prediction metric.
- SQLite migration is transactional and retryable. It preserves existing example IDs, question/answer/topic/citations/status/timestamps, sets revision 1 for legacy rows, rebuilds review event action constraint to include approved, and retains FK/index/append-only guarantees.
