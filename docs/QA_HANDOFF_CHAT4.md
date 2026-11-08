# QA handoff — Chat 4

Last verified: 2026-11-08
Scope: verification and packaging only; no merge or release performed.

## Verified CI

- Workflow: SmartStock Pro CI
- Run: [42448877490](https://github.com/duyhyundaithaibinh-max/Smartstock-Pro/actions/runs/42448877490)
- Tested commit: `ff0c35ae73532d9fb12bebb537b5a1534cc45655`
- Branch: `codex-free/sp-019-local-auth`
- Backend job: success (`cd backend && pytest`)
- Android job: success
  - Flutter dependencies resolved
  - `flutter analyze`: success
  - `flutter test`: success
  - `flutter build apk --debug`: success
  - artifact upload: success

## Android artifact

- Name: `smartstock-pro-debug-apk`
- Artifact ID: `13604432974`
- Size: 75,930,696 bytes
- SHA-256: `aa4360e145d6cd35517bb9394f10e0b303be97fe157a5b530fc1dba3739111f6`
- Expires: 2027-02-06
- Download from the Actions run's Artifacts section. This is a debug APK, not a signed production release.

## Not verified / hand off

1. Install and smoke-test on a physical Android device; CI only builds the emulator-compatible debug APK.
2. Verify backend URL/network connectivity on the intended deployment device and trusted LAN.
3. Verify first-owner registration/login/logout end-to-end against a persistent local SQLite database.
4. Exercise watchlist, knowledge upload/search, Training Room and evaluation APIs end-to-end from the Android UI.
5. Test SQLite backup/restore and upgrade behavior before distributing user data.
6. No release signing, Play Store package, TLS, rate limiting, public-Internet hardening, or multi-user authorization is included.
7. No model training/fine-tuning is verified. Current training work prepares supervised examples and local evaluation only.

## PR-chain warning for coordinator

At handoff, PR #3 is merged. PR #4 and PR #5 are closed without merge. PR #6 remains open and is based on branch `codex-free/sp-017-indicator-signature`; PR #8 remains open and is based on `codex-free/sp-018-training-dataset`. These stacked dependencies need coordinator review before any merge/retarget operation. Chat 4 did not change PR bases or merge any PR.

## Chat 4 completion boundary

CI verification and debug APK artifact creation are complete for the exact commit above. The remaining items are integration/device/release checks and are intentionally left for the owning chat/coordinator. Re-run CI after any backend, mobile, or workflow source change.
