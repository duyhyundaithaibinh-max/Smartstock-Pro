# PHIÊN 21 — Backend migration hardening traceability

Baseline: PR #26 exact HEAD 17a7050fd3a7669578027e35e47b49e9c0bbc016.
This follow-up is stacked directly on that commit. The API contract is unchanged.

## Requirement-to-evidence matrix

| Requirement | Source function / route | Direct test and key assertion | Evidence class |
|---|---|---|---|
| Transactional migration and rollback after event-table rename/new-table create | backend/app/db.py::_migrate_training_review | test_pr25_event_rebuild_faults_after_rename_and_after_copy_roll_back_exactly_then_retry — SQLite authorizer denies event INSERT after old-table rename/new-table create; after rollback exact sqlite_master schema, all rows, FK metadata and sqlite_sequence match pre-migration snapshot | Direct |
| Rollback after copying legacy events but before dropping old table | backend/app/db.py::_migrate_training_review | same test, checkpoint old_event_drop — deny DROP TABLE training_example_review_events_old after copy; exact snapshot restored | Direct |
| Retry after fault and idempotent second migration | backend/app/db.py::_migrate_training_review | same test — retry succeeds, second migration snapshot equals first migrated snapshot, integrity_check=ok, foreign_key_check empty | Direct |
| Upgrade from PR #25 event schema containing real edited/rejected events | backend/app/db.py::_migrate_training_review | test_pr25_upgrade_fixture_preserves_all_statuses_both_histories_and_init_is_idempotent — retains event IDs 71/72, action/reason/revisions/changed_fields/reviewer/timestamps; labels copied events Owner | Direct |
| Preserve draft/approved/rejected examples and full quality history | backend/app/db.py::_migrate_training_review | same test — example IDs/statuses/fields/timestamps and quality IDs 81–83, example revisions, scores, rubric, rationale, reviewer and timestamps survive | Direct |
| Do not fabricate historic approvals | backend/app/db.py::_migrate_training_review | both PR #25 migration tests — approved example 52 remains approved but migrated event table has zero new approved rows | Direct |
| Preserve indexes, triggers and FK constraints on rollback; restore healthy FK schema after retry | backend/app/db.py::_migrate_training_review | fault-injection test snapshot includes sqlite_master indexes/triggers and PRAGMA foreign_key_list; integrity_check and foreign_key_check pass after retry | Direct |
| Owner vs legacy authentication, route-specific permission | backend/app/routers/training_review.py::_reviewer_id; backend/app/main.py auth middleware | test_reject_requires_owner_and_legacy_token_is_forbidden; test_review_endpoints_reject_legacy_token_for_read_and_write; test_patch_auth_is_route_specific_for_missing_legacy_and_owner | Direct / regression |
| Approve/reject race, one transition and one event | backend/app/training_room.py::approve_example/reject_example | test_reject_and_approve_race_has_one_transition_and_one_event | Direct |
| Edit optimistic concurrency race | backend/app/training_room.py::edit_draft_example | test_concurrent_edits_with_same_revision_allow_exactly_one_writer | Direct |
| Append-only audit and quality histories | backend/app/db.py triggers | test_reject_edit_approve_audit_and_quality_rows_cascade_on_hard_delete; test_quality_review_history_is_append_only_and_revision_scoped | Direct |
| Hard-delete cascade | backend/app/training_room.py::delete_example | test_delete_remains_hard_delete_and_cascades_review_history; test_reject_edit_approve_audit_and_quality_rows_cascade_on_hard_delete | Direct |
| Quality review allowed on draft/approved/rejected without changing readiness/export/evaluator | backend/app/training_room.py::create_quality_review/evaluate_dataset/export_approved_jsonl; backend/app/offline_model_evaluation.py::evaluate_predictions | test_quality_review_accepts_all_existing_statuses_and_does_not_change_evaluator; test_quality_review_validation_and_owner_only_auth | Direct |
| Review event pagination/order/empty/404/401/403/422 | backend/app/routers/training_review.py::get_training_review_events; backend/app/training_room.py::list_review_events | test_review_event_history_is_chronological_paginated_and_owner_only | Direct |
| Deterministic analysis remains separate from AI narrative | backend/app/interpretation_guard.py; backend/app/model_adapter.py | test_context_contains_allowlisted_engine_facts_only; test_model_cannot_invent_numeric_values_in_summary; test_every_claim_requires_known_evidence; test_gateway_is_disabled_by_default_and_does_not_call_adapter | Indirect architecture regression |
| Offline evaluator does not call/train a model | backend/app/offline_model_evaluation.py::evaluate_predictions | test_offline_evaluation_scores_answer_and_citations; test_offline_evaluation_rejects_unapproved_examples; test_offline_evaluation_excludes_approved_examples_with_deleted_sources | Indirect architecture regression |
| No fabricated OHLCV / no unsupported data assumptions | backend/app/market_data.py, analysis engines and CSV import | test_report_handles_short_history_without_fabricating_bars; test_no_data_does_not_invent_latest_quote; test_valid_import_trims_and_persists_provenance | Indirect market-data regression |

## Test execution record

- Targeted migration tests: run the two tests beginning test_pr25_event_ in backend/tests/test_training_review.py.
- Full backend suite: python -m pytest -q.
- Repeatability: rerun the targeted migration tests and full suite on the same exact commit; no skipped tests accepted.
- CI run/job IDs and exact SHA are recorded in the PR conversation after workflow completion. A test assertion is not considered executed evidence until the matching CI log confirms it.

## Scope guard

No API route/schema change, no VPS adapter/API/dependency, no synthetic market data, no paid AI provider or SDK, and no new runtime dependency is part of this follow-up. No physical-device, production migration, backup/restore, LAN/TLS/firewall or production deployment PASS is claimed.
