# QA handoff — Chat 4

Last verified: 2026-11-08 05:32 UTC
Scope: verification and packaging only; no merge or release performed.

## Latest verified CI

- Workflow: SmartStock Pro CI
- Run: [42450837945](https://github.com/duyhyundaithaibinh-max/Smartstock-Pro/actions/runs/42450837945)
- Tested commit: `a5598cd97fe3deefa5e4c5b0b47af836fb680451`
- Branch: `codex-free/sp-019-local-auth`
- Overall conclusion: **success**
- Backend job: success; all 135 pytest tests passed.
- Android job: success
  - Flutter dependencies resolved
  - `flutter analyze`: success
  - `flutter test`: success
  - Debug APK build: success
  - Artifact upload: success

## Latest Android artifact

- Name: `smartstock-pro-debug-apk`
- Artifact ID: `13605841116`
- Size: 75,930,696 bytes
- GitHub artifact digest: `sha256:d0dbd8384d15aa107fe8c1adddbe8832a1c998b6e78d7bbecbf9639b9ef4db61`
- Created: 2026-11-08 05:32:12 UTC
- Expires: 2027-02-06 05:27:19 UTC
- Download from the Actions run's Artifacts section. This is a debug APK, not a signed production release. The digest above is the GitHub artifact digest, not a separately calculated APK-file checksum.

## QA fixes included in the verified branch head

- Corrected the Unicode word-token regex in `backend/app/offline_model_evaluation.py` to `r"[^\W_]+"` with Unicode semantics, so Vietnamese words are tokenized separately.
- Added regression coverage: comparing “Sóng 3 tăng mạnh” with “Sóng 3 giảm mạnh” yields token precision, recall and F1 of 0.75.
- Tightened `example_id` validation to reject booleans (Python's `bool` is a subclass of `int`).
- The backend pytest job passed on the exact commit above.

## Security review — bootstrap risk requiring coordinator decision

- `POST /api/v1/auth/register-first-owner` is unauthenticated until the first owner is created.
- `docker-compose.yml` publishes `8000:8000`, and the Dockerfile starts Uvicorn on `0.0.0.0:8000`.
- There is no one-time bootstrap secret or local-origin restriction.
- A LAN client could race to register the first owner if the service is reachable before legitimate setup.
- This is a setup-time account-takeover risk for LAN deployment. It is not a CI failure, but should be mitigated before LAN use.
- Suggested choices: one-time local bootstrap secret, or loopback-only default binding plus an explicit protected LAN procedure. The choice affects Android device connectivity, so Chat 4 has not changed it unilaterally.
- Related review comment is recorded on PR #8.

## Not verified / hand off

1. Install and smoke-test on a physical Android device; CI only builds the debug APK.
2. Verify backend URL/network connectivity on the intended deployment device and trusted LAN.
3. Verify first-owner registration/login/logout end-to-end against a persistent local SQLite database after the bootstrap exposure is mitigated.
4. Exercise watchlist, knowledge upload/search, Training Room and evaluation APIs end-to-end from the Android UI.
5. Test SQLite backup/restore and upgrade behavior before distributing user data.
6. No release signing, Play Store package, TLS, rate limiting, public-Internet hardening, or multi-user authorization is included.
7. No model training/fine-tuning is verified. Current training work prepares supervised examples and local evaluation only.

## PR-chain warning for coordinator

PR #3 is merged. PR #4 and PR #5 are closed without merge. PR #6 remains open and is based on `codex-free/sp-017-indicator-signature`; PR #8 remains open/draft and is based on `codex-free/sp-018-training-dataset`. These stacked dependencies need coordinator review before any merge/retarget operation. Chat 4 did not change PR bases or merge any PR.

## Chat 4 completion boundary

CI verification and debug APK artifact creation are complete for exact commit `a5598cd97fe3deefa5e4c5b0b47af836fb680451`. Remaining items are integration/device/release checks and the bootstrap security decision. Re-run CI after any backend, mobile, or workflow source change.
