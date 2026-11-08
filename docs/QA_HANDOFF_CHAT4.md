# QA handoff — Chat 4

Last verified: 2026-11-08 07:45 UTC
Scope: automated CI and source-level security review; no merge or release performed.

## Latest verified backend security CI

- PR #8 head: `3fe6267265b7012fd03b851f38bd47a93f5c064b`
- Workflow run: [42458090879](https://github.com/duyhyundaithaibinh-max/Smartstock-Pro/actions/runs/42458090879)
- Backend: **142 passed, 1 warning**.
- Regression cases verified in `backend/tests/test_auth.py`:
  - missing secret (422) and wrong secret (403);
  - consumed/replay secret rejected;
  - second first-owner registration rejected;
  - concurrent two-connection first-owner race permits only one owner;
  - failed owner INSERT rolls back secret consumption;
  - POSIX bootstrap file permission 0600;
  - setup response and captured logs do not expose plaintext secret.
- This is automated test evidence, not a penetration test or deployment-host smoke test.

## Latest verified Android/bootstrap CI

- PR #19 head: `93153968b8895e35379c675b9a7ef80f3cac8cad`
- Base: PR #8 head `3fe6267265b7012fd03b851f38bd47a93f5c064b`
- Workflow run: [42458567609](https://github.com/duyhyundaithaibinh-max/Smartstock-Pro/actions/runs/42458567609)
- Backend pytest: success; **142 passed, 1 warning**.
- Flutter Analyze: success.
- Flutter tests: **1 passed**.
- Android debug APK build: success.
- Artifact upload: success.
- Artifact: [smartstock-pro-debug-apk](https://github.com/duyhyundaithaibinh-max/Smartstock-Pro/actions/runs/42458567609/artifacts/13608782312), ID `13608782312`, size 75,930,465 bytes.
- Artifact ZIP SHA-256: `1f369364f888b30426b1d80b3bdb27b30fc1919ae864993f784845ae9afa6c71`.
- This is a debug APK, not a signed production release.

## Bootstrap secret implementation and operational checks

- `backend/scripts/show_bootstrap_secret.py` and `backend/scripts/__init__.py` exist; Dockerfile copies `scripts` into `/app`; Compose sets `SMARTSTOCK_BOOTSTRAP_SECRET_FILE=/data/bootstrap.secret` on persistent volume `/data`.
- Documented command: `docker compose exec api python -m scripts.show_bootstrap_secret`; direct backend command: `cd backend && python -m scripts.show_bootstrap_secret`.
- Source/package path and container working directory were verified. The command has **not** yet been executed on the actual deployment host.
- Secret is generated once, file mode 0600 on POSIX, digest-only in SQLite, single-use, removed after successful owner creation; replay remains blocked by the SQLite consumed marker.
- Android PR #19 adds a hidden field, validates 32–256 characters, sends `bootstrap_secret`, handles 403/422, clears controller after successful setup and disposes controller. Review found no secret persistence or logging in that diff.
- Transport: bootstrap only over HTTPS or trusted isolated administration network. HTTP on untrusted Wi-Fi/LAN can expose the secret in transit. No TLS/reverse proxy or rate limiting is supplied by the current Compose configuration.

## Not verified / remaining acceptance work

1. Physical Android device smoke test for first-owner setup, login/logout and Training Room calls.
2. Trusted LAN connectivity and deployment-host execution of `show_bootstrap_secret`.
3. SQLite backup/restore and upgrade behavior on a copied production-like database.
4. Release signing, TLS/reverse proxy, rate limiting and public-Internet hardening.
5. No model training/fine-tuning is verified; current evaluator scores supplied local predictions only.

A green CI run does not satisfy physical-device, deployment-host, backup/restore or release acceptance.
