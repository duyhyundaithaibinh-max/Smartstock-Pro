# Training Review API contract (SP-022)

Review, edit, quality and history routes require an authenticated owner Bearer session. A missing/invalid token returns 401. A legacy SMARTSTOCK_API_TOKEN principal receives 403 on reject/edit/quality/history routes. The existing approve route deliberately retains its legacy shared-token compatibility; audit attribution is reviewer_user_id=null and reviewer_label=Legacy shared token for that path. Owner approval records the owner ID and Owner label. Clients must never send reviewer_user_id.

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
- reviewer_user_id is the server-authenticated owner ID when an owner session is used; reviewer_label is Owner. For the retained legacy approval path, the ID is null and the label is Legacy shared token. Direct internal service calls use System. No client-supplied reviewer identity is accepted.
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


## Complete wire examples for Android

All JSON examples below are UTF-8. id, timestamps, status and reviewer identity are server-owned. Never send reviewer_user_id, reviewer_label, revision, created_at or updated_at on create.

### Create draft

POST /api/v1/training/examples

Request:
{
  "question": "What rule applies to Elliott Wave three?",
  "expected_answer": "Wave three must not be the shortest impulse wave.",
  "topic": "elliott",
  "citation_ids": ["kb:12:0"]
}

- question: required string, trimmed length 10–1000.
- expected_answer: required string, trimmed length 20–5000.
- topic: optional string, default general, trimmed length 1–80.
- citation_ids: required array of 1–10 unique citation IDs; every citation must resolve to an existing knowledge chunk.
- Clients should send only the four fields above.

201 response (example):
{
  "id": 42,
  "question": "What rule applies to Elliott Wave three?",
  "expected_answer": "Wave three must not be the shortest impulse wave.",
  "topic": "elliott",
  "citation_ids": ["kb:12:0"],
  "status": "draft",
  "revision": 1,
  "created_at": "2026-11-09 00:00:00",
  "updated_at": "2026-11-09 00:00:00"
}

### List, approve, reject, edit and delete

- GET /api/v1/training/examples?limit=100&offset=0&status=draft: limit 1–500 (default 100), offset >=0 (default 0), optional status draft|approved|rejected. Response: {"total":1,"limit":100,"offset":0,"items":[example]}.
- POST /api/v1/training/examples/{id}/approve: no request body. 200 returns the same example representation with status approved; revision does not change. Draft only; repeat/non-draft is 409.
- POST /api/v1/training/examples/{id}/reject: request {"reason":"Source does not support this answer."}; reason must be a string trimmed to 1–1000 chars. 200 returns the example with status rejected; revision does not change.
- PATCH /api/v1/training/examples/{id}: request must include expected_revision (strict integer >=1) and at least one editable field. Editable fields and limits: question 10–1000, expected_answer 20–5000, topic 1–80, citation_ids 1–10 valid unique IDs. Extra fields are forbidden. Omit unchanged fields; do not send null. 200 returns the updated example with revision incremented exactly once.
- DELETE /api/v1/training/examples/{id}: no body. 200 response {"example_id":42,"status":"deleted"}. This is a permanent hard delete; lifecycle events and quality rows cascade. Reject is not a delete.

Example reject response (the ordinary example shape):
{
  "id": 42,
  "question": "What rule applies to Elliott Wave three?",
  "expected_answer": "Wave three must not be the shortest impulse wave.",
  "topic": "elliott",
  "citation_ids": ["kb:12:0"],
  "status": "rejected",
  "revision": 1,
  "created_at": "2026-11-09 00:00:00",
  "updated_at": "2026-11-09 00:00:00"
}

### Quality review history — distinct from lifecycle events

POST /api/v1/training/examples/{id}/quality-reviews

Request:
{"score":92,"rubric_version":"qa-quality-v1","rationale":"Answer is accurate and the cited source directly supports it."}

- score is a strict integer 0–100 inclusive; JSON booleans, floats and null are invalid.
- rubric_version must be qa-quality-v1 (string length 1–40).
- rationale is required, trimmed length 10–2000.
- A quality review may be added while the example is draft, approved or rejected.
- 201 response is one row:
{
  "id": 91,
  "example_id": 42,
  "example_revision": 1,
  "score": 92,
  "rubric_version": "qa-quality-v1",
  "rationale": "Answer is accurate and the cited source directly supports it.",
  "reviewer_user_id": 1,
  "reviewed_at": "2026-11-09 00:00:00"
}

GET /api/v1/training/examples/{id}/quality-reviews

Response (not paginated):
{
  "example_id": 42,
  "items": [{
    "id": 91,
    "example_id": 42,
    "example_revision": 1,
    "score": 92,
    "rubric_version": "qa-quality-v1",
    "rationale": "Answer is accurate and the cited source directly supports it.",
    "reviewer_user_id": 1,
    "reviewed_at": "2026-11-09 00:00:00"
  }],
  "count": 1
}

This endpoint is intentionally different from review-events: quality history is ordered by reviewed_at,id, has count, and has no total, limit or offset. It records manual quality observations at a particular example revision; it is not a lifecycle transition and does not affect readiness, JSONL export or prediction evaluator metrics.

### Readiness and JSONL export

- GET /api/v1/training/evaluation returns the readiness object: total_examples, approved_examples, valid_approved_examples, draft_examples, rejected_examples, approved_examples_with_missing_sources, source_documents, duplicate_question_groups, topics, readiness, minimum_approved_examples_for_initial_evaluation, and explanatory notes.
- GET /api/v1/training/export returns {"format":"jsonl","count":N,"content":"..."}. content is newline-delimited UTF-8 JSON. Only approved examples with existing cited chunks are exported. Export does not fine-tune or call a model.

### HTTP error and auth mapping

| Status | Meaning for this API | Android behavior |
|---|---|---|
| 200 | Read/update/transition succeeded | Parse operation-specific response shape. |
| 201 | Draft or quality review created | Parse created resource. |
| 401 | Missing, invalid, expired or revoked credentials | Clear invalid session when applicable and request owner login; do not show bootstrap-secret error unless the bootstrap endpoint itself failed. |
| 403 | Authenticated legacy principal used an owner-session-only route, or owner identity is unavailable | Explain that owner login is required; do not repeatedly retry with the same legacy token. |
| 404 | Example/document/citation resource does not exist | Show a not-found state; refresh list/history. |
| 409 | Duplicate/non-draft transition or stale revision | Refresh the example and its revision before retrying. |
| 422 | Field/range/citation/pagination/rubric validation failed | Show field-specific validation; this is not a bootstrap-secret error. |
| 5xx | Unexpected server/storage failure | Show a generic retry-later error; never expose traceback or credentials. |

Owner Bearer session is required for reject, PATCH edit, quality-review POST/GET and review-events GET. Missing/invalid auth on these routes is 401; a valid legacy shared-token principal is 403. The existing approve route and existing create/list/delete/readiness/export paths retain configured legacy-token compatibility. Legacy approval audit attribution is null ID plus Legacy shared token; owner approval is owner ID plus Owner.

### Timestamp parsing

Timestamps are generated/stored by the backend. SQLite CURRENT_TIMESTAMP responses commonly use YYYY-MM-DD HH:MM:SS; preserved historical rows may use ISO-8601 with T (and may include an offset). Android should parse both forms as server timestamps, preserve the original value for diagnostics, and never replace them with client-generated time. The example values in this document are illustrative, not a guarantee of one serialization format.
