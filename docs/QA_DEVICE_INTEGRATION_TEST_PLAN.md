# SmartStock Pro — Chat 4 device and integration test plan

Status: manual acceptance plan; not evidence that a physical-device test has run.
Tested CI baseline: commit `a5598cd97fe3deefa5e4c5b0b47af836fb680451`, run [42450837945](https://github.com/duyhyundaithaibinh-max/Smartstock-Pro/actions/runs/42450837945).
APK artifact: `smartstock-pro-debug-apk`, ID `13605841116`.

## Safety gate before testing on a LAN

**Do not expose an uninitialized instance to a shared LAN.** First-owner registration is unauthenticated, while the current Docker Compose port mapping publishes port 8000 on all host interfaces. A LAN client could race to claim the first-owner account.

A one-time bootstrap secret is now implemented in SP-019:
- Start the backend once, then read the secret only from a trusted host administration terminal: Docker Compose: `docker compose exec api python -m scripts.show_bootstrap_secret`; direct backend: `cd backend && python -m scripts.show_bootstrap_secret`.
- Enter the secret in the Android first-owner setup field. Never paste it into chat, tickets, screenshots or logs.
- The secret is single-use and is stored as a SHA-256 digest in SQLite; the plaintext file is owner-only (0600 on POSIX) and is removed after successful owner creation.
- Bootstrap over HTTPS or an isolated/trusted administration network only. HTTP on an untrusted Wi-Fi/LAN can expose the secret in transit. Do not port-forward or expose the API to the public Internet.
- The helper command has been verified from source/package layout and Dockerfile working directory; it has not yet been smoke-tested on the actual deployment host.

## A. Install and launch

| ID | Action | Expected result |
|---|---|---|
| A1 | Install the debug APK on a supported Android device. | Installation completes without signing/release assumptions. |
| A2 | Launch with an empty backend database. | App shows first-owner setup, not an authenticated dashboard. |
| A3 | Enter invalid/short username or password. | Validation is clear; no owner is created. |
| A4 | Read bootstrap secret on the trusted host and complete first-owner setup over HTTPS/trusted isolated network. | Exactly one owner is created; app receives a session and the plaintext secret is no longer available. |
| A5 | Attempt a second first-owner registration. | Server rejects it (HTTP 409); existing owner remains unchanged. |

## B. Authentication and API authorization

| ID | Action | Expected result |
|---|---|---|
| B1 | Call a private endpoint without Authorization. | HTTP 401 and `WWW-Authenticate: Bearer`. |
| B2 | Login with an incorrect password. | HTTP 401; no session is created. |
| B3 | Login with correct credentials. | Opaque bearer token returned; never expose password in logs. |
| B4 | Call private endpoint with valid token. | Request succeeds for the owner. |
| B5 | Call public market GET endpoints without token. | Allowed only for the documented market-read allowlist. |
| B6 | Call rule-management, watchlist, Knowledge Base and Training Room routes without token. | HTTP 401. |
| B7 | Logout, then reuse the same token. | Logout succeeds; subsequent private call returns HTTP 401. |
| B8 | Wait past expiry or set an expired test session. | Expired token is rejected. |
| B9 | Restart backend while preserving SQLite. | Owner remains; valid unexpired session behavior matches documented policy. |
| B10 | Close and relaunch Android app. | User is asked to log in again because current app stores token in memory only. |

## C. Knowledge Base and Training Room

| ID | Action | Expected result |
|---|---|---|
| C1 | Upload a small UTF-8 Markdown/TXT curriculum file. | Document is stored locally and chunked; duplicate upload is handled safely. |
| C2 | Search for a known phrase. | Search returns source metadata and real citation IDs. |
| C3 | Create a training example with a real citation. | Example is created as `draft`. |
| C4 | Attempt approval with a missing/deleted citation. | Approval is rejected. |
| C5 | Approve a reviewed example with valid citations. | Status becomes `approved`. |
| C6 | Export approved examples. | Only approved examples with existing citations are exported as JSONL. |
| C7 | Submit evaluator input containing unknown/unapproved IDs. | Request is rejected with validation error. |
| C8 | Submit partial-overlap answer “Sóng 3 tăng mạnh” vs “Sóng 3 giảm mạnh”. | Token precision, recall and F1 are each 0.75. |
| C9 | Submit boolean `example_id: true`. | Input is rejected as an invalid positive integer ID. |

## D. Data durability and recovery

| ID | Action | Expected result |
|---|---|---|
| D1 | Create owner, upload document and add approved example. | All records are visible after normal app/API refresh. |
| D2 | Stop and restart backend without deleting the data volume. | Owner, documents and examples persist. |
| D3 | Back up SQLite using a consistent SQLite backup procedure. | Backup file is readable and integrity check passes. |
| D4 | Restore backup into an isolated test instance. | Restored records and citation references remain consistent. |
| D5 | Test an upgrade using a copy of the database. | Schema migration does not lose user data; record any migration gap. |

## E. Android-to-backend connectivity

Do these only after the bootstrap security gate is resolved:
- Verify the configured API base URL for emulator and physical device separately.
- Confirm the device can reach the backend on the intended trusted network.
- Confirm the app handles server unavailable, timeout and HTTP 401 without crashing or showing stale private data.
- Confirm logout clears the in-memory token and private screens require login again.
- Confirm no password or bearer token appears in logs, analytics or crash reports.
- Confirm market GET functionality remains available only as documented; all private mutations require owner authentication.

## Exit criteria

- All automated CI checks remain green on the exact code head.
- Sections A–D pass on an isolated test environment.
- Section E passes on a physical Android device after bootstrap mitigation.
- No secrets appear in logs.
- SQLite backup/restore is verified.
- Security limitations (single owner, no TLS/rate limit, debug APK) are clearly disclosed.

A passing CI build alone does not satisfy the physical-device, LAN, persistence or release exit criteria.
