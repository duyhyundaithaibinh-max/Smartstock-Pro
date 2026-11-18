# SmartStock Pro — Local backend deployment safety runbook

**Scope:** single-owner local deployment only. This runbook is an operator checklist, not evidence that a production host, physical Android device, LAN, TLS proxy, firewall, or backup/restore procedure has been smoke-tested.

## 1. What CI verifies vs. what the operator must verify

| Area | Automated evidence | Operator action still required |
|---|---|---|
| Bootstrap secret | Unit/integration tests cover generation, 0600 POSIX mode, missing/invalid file repair, permission repair, single-use consume, replay, transaction rollback and concurrent first-owner registration. | Verify the actual Docker volume mount, file owner/mode, persistence across container recreation and recovery from a real host backup. |
| API authorization | TestClient integration tests exercise middleware for watchlist, Knowledge Base, Training Room and analysis-rule writes, including missing/invalid/owner/legacy credentials and expired/revoked sessions. | Verify TLS termination, firewall policy, published ports and network isolation on the deployment host. |
| SQLite | CI tests schema creation/migration, append-only rule-history triggers and duplicate-upload concurrency. | Perform and restore a backup on a separate host or isolated volume; validate application-level records after restore. |
| Android/LAN | CI builds and tests the debug app. | Physical-device connectivity, trusted-LAN behavior and real reverse-proxy/TLS configuration remain manual acceptance work. |

## 2. Bootstrap secret and Docker volume

1. Start the service on a trusted host only: \`docker compose up -d --build\`.
2. Confirm the persistent volume is mounted at \`/data\`: \`docker compose exec api sh -c 'mount | grep " /data " || true; ls -la /data'\`.
3. Before the first owner is created, read the secret only in the host's trusted administration terminal:
   \`docker compose exec api python -m scripts.show_bootstrap_secret\`.
   Never paste the value into chat, tickets, shell history, screenshots or logs.
4. On Linux/POSIX, inspect the secret file without printing its contents:
   \`docker compose exec api stat -c '%a %U:%G %n' /data/bootstrap.secret\`.
   Expected mode is \`600\`; restrict host access to the Docker daemon and volume.
5. Create the first owner, then confirm the plaintext file is gone:
   \`docker compose exec api sh -c 'test ! -e /data/bootstrap.secret && echo "bootstrap file absent after owner setup"'\`.
   The consumed marker and digest remain in SQLite to prevent replay if file cleanup had failed.
6. Restart/recreate the container while retaining the named volume. Confirm the owner can log in and that a consumed secret cannot be reused. Do not delete the volume as part of an ordinary image upgrade.

The helper command and volume path have automated/source-level checks only; the commands above must still be run by the operator on the actual host.

## 3. HTTPS, trusted LAN, firewall and port exposure

### Default: local-only host binding

Docker Compose publishes the API as `127.0.0.1:8000:8000` by default through `SMARTSTOCK_BIND_ADDRESS`'s loopback fallback. The container still listens on port `8000`; only the host-side bind address changes.

1. Start the service without setting `SMARTSTOCK_BIND_ADDRESS`: `docker compose up -d --build`.
2. Inspect the resolved configuration: `docker compose config`. Under `services.api.ports`, verify the published port is `8000`, the target is `8000`, and the host IP is exactly `127.0.0.1`.
3. On the host, verify the listener with an OS-appropriate command such as `ss -ltn` (Linux) or `netstat -an`; the published listener must be loopback, not a wildcard address.
4. Keep the variable unset for host-local use. Local clients connect through `http://127.0.0.1:8000`.

### Explicit LAN opt-in (not a security feature)

Only if LAN access is intentionally required, bind to the host's specific LAN interface address, for example:

```sh
SMARTSTOCK_BIND_ADDRESS=192.168.1.10 docker compose up -d --build
```

Replace the example with an IP actually assigned to the host. The same value can be placed in a protected local `.env` file for Compose interpolation. Do not use `0.0.0.0` or another wildcard; do not set this variable for local-only use. After changing the bind address, run `docker compose config` again and verify the resolved `host_ip` is the intended address.

A LAN bind opt-in does **not** make the HTTP API safe for remote access:

- Terminate HTTPS at a maintained reverse proxy before accepting LAN/remote credentials.
- Restrict inbound firewall rules to explicitly trusted client networks and expose only the proxy's TLS port; do not expose TCP 8000 directly to the Internet.
- Do not enter the bootstrap secret or owner credentials over plain HTTP on shared Wi-Fi, guest Wi-Fi or an otherwise untrusted network. A trusted LAN is a compensating control, not encryption.
- Verify from a second machine that the API port is unreachable except where intentionally allowed; verify the HTTPS certificate/hostname and proxy behavior. Record host, date and firewall/proxy configuration in the deployment record.

The local-only default reduces accidental host-interface exposure; it does not implement login/bootstrap rate limiting and does not prove TLS, firewall or LAN deployment safety. No TLS proxy or firewall smoke test is claimed by this repository's CI.
## 4. SQLite backup and restore

This section describes a local operator procedure. Automated tests exercise SQLite backup/restore on temporary file copies only; they do not create or restore Docker named volumes.

### 4.1 Consistent online database backup (post-owner preferred)

Use SQLite's online backup API while the service is running. Do not copy a live smartstock.db file with ordinary cp, and do not copy only a live .db while ignoring its WAL/SHM state.

1. Create a temporary backup inside the container's writable /tmp, not inside the persistent /data volume:

```sh
docker compose exec -T api python -c "import sqlite3; src=sqlite3.connect('/data/smartstock.db'); dst=sqlite3.connect('/tmp/smartstock.db.backup.partial'); src.backup(dst); dst.close(); src.close()"
```

2. Copy it to a temporary host-side file. Keep the partial name until all checks succeed:

```sh
mkdir -p backups
umask 077
docker compose cp api:/tmp/smartstock.db.backup.partial ./backups/smartstock.db.partial
```

3. Verify the host copy before accepting it. Both SQLite checks must pass, and the file must contain the expected SmartStock application tables (not merely be an empty SQLite file):

```sh
python -c "import sqlite3,sys; p=sys.argv[1]; c=sqlite3.connect('file:'+p+'?mode=ro',uri=True); assert c.execute('PRAGMA integrity_check').fetchone()[0]=='ok'; assert not c.execute('PRAGMA foreign_key_check').fetchall(); names={r[0] for r in c.execute(\"SELECT name FROM sqlite_master WHERE type='table'\")}; required={'symbols','candles','watchlist','auth_bootstrap','auth_users','auth_sessions','knowledge_documents','knowledge_chunks','analysis_rule_versions','analysis_rule_activation_history','training_examples','training_example_review_events','training_example_quality_reviews'}; assert required <= names; c.close()" ./backups/smartstock.db.partial
sha256sum ./backups/smartstock.db.partial
chmod 600 ./backups/smartstock.db.partial
mv ./backups/smartstock.db.partial ./backups/smartstock.db
```

The mv must remain on the same host filesystem so finalization is atomic. Record the SHA-256, timestamp, source instance/volume identifier and application revision in the backup record; do not include credentials, bearer tokens or secret contents. Encrypt backups at rest and restrict access. If verification fails, do not rename or restore the partial file; quarantine/delete it safely and investigate.

4. Remove the temporary container copy after successful host verification:

```sh
docker compose exec -T api rm -f /tmp/smartstock.db.backup.partial
```

### 4.2 Full data-volume backup and bootstrap pairing

The named volume contains /data/smartstock.db and, before first-owner setup completes, /data/bootstrap.secret.

- **Before first owner exists:** use a quiescent full-volume snapshot so the database and plaintext bootstrap file are captured as one matched point-in-time pair. Stop the API, archive the exact Compose data volume, encrypt/restrict the archive, and record its checksum. Never combine a DB snapshot from one time with a separately generated or rotated bootstrap.secret.
- **After first owner exists:** confirm the owner row exists, auth_bootstrap.consumed_at is non-NULL, and /data/bootstrap.secret is absent. A post-owner SQLite online backup is preferred for routine DB backups; a full-volume archive remains an option when preserving the complete volume is required.
- Do not commit database files, volume archives, bootstrap secrets or backup artifacts to Git.

For a quiescent full-volume snapshot:

1. Run docker compose stop api.
2. Resolve and record the exact Compose project volume using docker compose config and docker volume ls.
3. Archive that exact stopped volume using the operator's trusted local backup method. Do not guess the volume name; verify the archive contains the expected /data contents.
4. Verify archive readability and checksum, store it encrypted with restricted permissions, then restart with docker compose start api.
5. If owner setup is incomplete, retain the database and bootstrap file together and verify their digest pairing before any restore. Never print the secret.

### 4.3 Restore to a new isolated volume (never overwrite the source)

1. Identify the source backup by its recorded checksum. Create a **new, explicitly named drill volume** and a separate Compose project. Do not mount the original data volume read-write in the drill container.
2. Populate the new volume only from the verified backup. Keep the drill API bound to loopback and use a non-conflicting host port (for example 127.0.0.1:18000); use a temporary Compose override if needed. Do not expose the drill instance to a LAN.
3. Before allowing owner access, run SQLite PRAGMA integrity_check (must return exactly ok) and PRAGMA foreign_key_check (must return zero rows).
4. Verify application-level records, not just /health: owner login; symbols, candles and watchlist; Knowledge Base documents, chunks and citations; Training Room examples, review events and quality-review history; active analysis-rule version/config hash and activation history. Compare against the backup manifest or recorded expected counts/identifiers.
5. **Invalidate every restored active session before the restored instance serves the owner.** An older snapshot can reintroduce a session that was revoked after backup. On the restored database, execute:

```sql
UPDATE auth_sessions SET revoked_at=CURRENT_TIMESTAMP WHERE revoked_at IS NULL;
```

   Confirm zero rows remain with revoked_at IS NULL. Require the owner to log in again. The old bearer tokens are not invalidated merely by copying the database; the SQL step is mandatory. Do not run this against the original/source database as part of a drill.
6. Check bootstrap state:
   - **Pre-owner snapshot:** verify no owner exists, auth_bootstrap.consumed_at IS NULL, and the paired bootstrap.secret hashes to auth_bootstrap.secret_sha256. Preserve the DB and secret as one matched pair with restrictive file permissions. Never display or log the secret.
   - **Post-owner snapshot:** verify the owner exists, the bootstrap marker is consumed, and the plaintext bootstrap.secret is absent. First-owner registration must remain unavailable.
7. Record drill start/end time, source and drill volume identifiers, backup SHA-256, app image/revision, integrity/FK results, application checks, session-revocation result and errors. Do not record passwords, tokens or secret values.
8. Stop/remove only the drill Compose project and delete only the explicitly named drill volume after evidence is saved. Verify the source project/volume still exists and was not modified. Never use docker compose down -v against the original project.

### 4.4 Acceptance boundary

The automated test suite proves SQLite backup/restore and application-state preservation on temporary filesystem copies, including fail-closed handling of missing, empty, truncated and non-SQLite files, and the restore-time session/bootstrap policies. It does **not** prove Docker named-volume behavior, host filesystem permissions, external archive/media integrity, container networking, or a successful host-volume restore. A manual Docker host-volume drill is a separate operator acceptance item; record its evidence before claiming it passed.

## 5. Deployment limits

- This is a local single-owner service, not a public or multi-tenant deployment.
- Login/setup rate limiting is not implemented.
- Plain HTTP does not protect credentials in transit.
- Android currently uses a debug build for CI validation; release signing and production distribution are separate work.
- Do not add VPS dependencies, paid AI API dependencies, or synthetic market data as deployment workarounds.
