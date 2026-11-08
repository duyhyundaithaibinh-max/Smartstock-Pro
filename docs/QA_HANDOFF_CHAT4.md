# QA handoff — Chat 4

Last verified: 2026-11-08 05:20 UTC
Scope: verification and packaging only; no merge or release performed.

## Latest verified CI

- Workflow: SmartStock Pro CI
- Run: [42449990815](https://github.com/duyhyundaithaibinh-max/Smartstock-Pro/actions/runs/42449990815)
- Tested commit: `ef2bae56d014998ddd911ddf747a812ef560724a`
- Branch: `codex-free/sp-019-local-auth`
- Overall conclusion: **success**
- Backend job: success (`cd backend && pytest`), including the Token F1 regression test.
- Android job: success
  - Flutter dependencies resolved
  - `flutter analyze`: success
  - `flutter test`: success
  - Debug APK build: success
  - Artifact upload: success

## Latest Android artifact

- Name: `smartstock-pro-debug-apk`
- Artifact ID: `13605381993`
- Size: 75,930,697 bytes
- GitHub artifact digest: `sha256:7d4b9095b44bbb216d7b62543702166ca77eb8fd97cd5f7ef2982c83a615387e`
- Created: 2026-11-08 05:20:18 UTC
- Expires: 2027-02-06 05:14:32 UTC
- Download from the Actions run's Artifacts section. This is a debug APK, not a signed production release. The digest above is the GitHub artifact digest, not a separately calculated APK-file checksum.

## QA fix included in this verified commit

- Corrected the Unicode word-token regex in `backend/app/offline_model_evaluation.py` to `r"[^\\W_]+"` with Unicode semantics, so Vietnamese words are tokenized separately.
- Added regression coverage in `backend/tests/test_offline_model_evaluation.py`: comparing “Sóng 3 tăng mạnh” with “Sóng 3 giảm mạnh” yields token precision, recall and F1 of 0.75.
- The backend pytest job passed on the exact commit above.

## Not verified / hand off

1. Install and smoke-test on a physical Android device; CI only builds the debug APK.
2. Verify backend URL/network connectivity on the intended deployment device and trusted LAN.
3. Verify first-owner registration/login/logout end-to-end against a persistent local SQLite database.
4. Exercise watchlist, knowledge upload/search, Training Room and evaluation APIs end-to-end from the Android UI.
5. Test SQLite backup/restore and upgrade behavior before distributing user data.
6. No release signing, Play Store package, TLS, rate limiting, public-Internet hardening, or multi-user authorization is included.
7. No model training/fine-tuning is verified. Current training work prepares supervised examples and local evaluation only.

## PR-chain warning for coordinator

PR #3 is merged. PR #4 and PR #5 are closed without merge. PR #6 remains open and is based on `codex-free/sp-017-indicator-signature`; PR #8 remains open/draft and is based on `codex-free/sp-018-training-dataset`. These stacked dependencies need coordinator review before any merge/retarget operation. Chat 4 did not change PR bases or merge any PR.

## Chat 4 completion boundary

CI verification and debug APK artifact creation are complete for exact commit `ef2bae56d014998ddd911ddf747a812ef560724a`. Remaining items are integration/device/release checks and are intentionally left for the owning chat/coordinator. Re-run CI after any backend, mobile, or workflow source change.
