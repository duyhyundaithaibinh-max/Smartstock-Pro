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

- The current Compose mapping \`8000:8000\` publishes the API on host interfaces. Do not assume it is loopback-only.
- For a host-local deployment, override the published mapping to \`127.0.0.1:8000:8000\`; expose it only through a locally controlled client or a reverse proxy.
- For remote/LAN access, terminate HTTPS at a maintained reverse proxy, restrict inbound firewall rules to explicitly trusted client networks, and do not expose TCP 8000 directly to the Internet.
- Do not enter the bootstrap secret or owner credentials over plain HTTP on shared Wi-Fi, guest Wi-Fi or an otherwise untrusted network. A trusted LAN is a compensating control, not encryption.
- Verify from a second machine that port 8000 is unreachable unless intentionally allowed, and verify the HTTPS certificate/hostname and redirect/proxy behavior. Record the host, date and firewall/proxy configuration in the deployment record.
- No TLS proxy or firewall smoke test is claimed by this repository's CI.

## 4. SQLite backup and restore

### Consistent online database backup

The SQLite backup API produces a consistent database copy while the service is running:

\`\`\`sh
docker compose exec -T api python -c "import sqlite3; src=sqlite3.connect('/data/smartstock.db'); dst=sqlite3.connect('/data/smartstock.db.backup'); src.backup(dst); dst.close(); src.close()"
mkdir -p backups
docker compose cp api:/data/smartstock.db.backup ./backups/smartstock.db
\`\`\`

If first-owner setup has not yet completed, also preserve the bootstrap file securely as part of the protected volume backup. Once an owner exists, the plaintext bootstrap file should be absent; SQLite retains the consumed marker.

### Full data-volume backup

1. Stop the API to make a quiescent volume snapshot: \`docker compose stop api\`.
2. Resolve the Compose volume name: \`docker volume ls --filter label=com.docker.compose.volume=smartstock_data\`.
3. Use a trusted local backup mechanism or a temporary container to archive the exact volume shown above. Encrypt the backup at rest and restrict access; it may contain the database and, before setup is complete, the bootstrap secret.
4. Restart the API: \`docker compose start api\`.
5. Store the backup off-host under the organization's retention policy. Do not commit it to Git.

### Restore drill (isolated environment only)

1. Stop the target API and restore the backup to a separate test volume/instance; never overwrite the live volume during the first drill.
2. Start the isolated instance and check \`/health\`, owner login, expected symbols/watchlist, knowledge documents/chunks, training examples and active analysis-rule version.
3. Run SQLite \`PRAGMA integrity_check\` and verify it returns \`ok\`.
4. If restoring a pre-owner snapshot, verify the bootstrap file and database digest correspond; if restoring a post-owner snapshot, verify that first-owner registration remains consumed.
5. Record restore duration, database/volume identifiers, integrity result and application-level checks.

CI does not execute host-volume backup/restore, and no successful restore drill is claimed until an operator records one.

## 5. Deployment limits

- This is a local single-owner service, not a public or multi-tenant deployment.
- Login/setup rate limiting is not implemented.
- Plain HTTP does not protect credentials in transit.
- Android currently uses a debug build for CI validation; release signing and production distribution are separate work.
- Do not add VPS dependencies, paid AI API dependencies, or synthetic market data as deployment workarounds.
