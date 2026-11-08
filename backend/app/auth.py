"""Single-owner local authentication using PBKDF2 password hashes and opaque sessions.

This is intended for a single trusted SmartStock installation, not a public
multi-tenant service. Session tokens are random, stored only as SHA-256 hashes,
and expire after a bounded lifetime.
"""
from __future__ import annotations

import hashlib
import hmac
import os
import secrets
import tempfile
from pathlib import Path
from datetime import datetime, timedelta, timezone
from typing import Any

from . import db
from .db import connection

_ITERATIONS = 310_000
_SESSION_DAYS = 14
_TOKEN_BYTES = 32


class AuthError(ValueError):
    pass


class BootstrapSecretError(AuthError):
    """The one-time local setup secret is missing, invalid or already consumed."""


def _bootstrap_secret_path() -> Path:
    configured = os.getenv("SMARTSTOCK_BOOTSTRAP_SECRET_FILE")
    return Path(configured) if configured else Path(db.DB_PATH).parent / "bootstrap.secret"


def read_bootstrap_secret() -> str:
    """Read the one-time secret for an operator on the trusted host only."""
    path = _bootstrap_secret_path()
    try:
        secret = path.read_text(encoding="utf-8").strip()
    except OSError as exc:
        raise AuthError(
            "Bootstrap secret is not available. Start the backend once, then read it from the local setup command."
        ) from exc
    if not secret or len(secret) > 256:
        raise AuthError("Bootstrap secret file is invalid; rotate it through the local setup process.")
    if os.name == "posix" and path.stat().st_mode & 0o077:
        raise AuthError("Bootstrap secret file permissions are too broad; restrict it to the owner (0600).")
    return secret


def _write_bootstrap_secret(path: Path, secret: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_name = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent,
            prefix=".bootstrap-secret-", delete=False,
        ) as handle:
            temp_name = handle.name
            os.chmod(temp_name, 0o600)
            handle.write(secret + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_name, path)
        if os.name == "posix":
            os.chmod(path, 0o600)
    finally:
        if temp_name and os.path.exists(temp_name):
            os.unlink(temp_name)


def ensure_bootstrap_secret() -> bool:
    """Create or repair the local one-time secret before serving first-owner setup.

    The plaintext secret is kept in a 0600 file on the persistent local data
    volume. Only its SHA-256 digest is stored in SQLite. It is never logged or
    exposed through an HTTP endpoint.
    """
    path = _bootstrap_secret_path()
    remove_file = False
    created = False
    with connection() as conn:
        conn.execute("BEGIN IMMEDIATE")
        if conn.execute("SELECT 1 FROM auth_users LIMIT 1").fetchone():
            remove_file = True
        else:
            row = conn.execute(
                "SELECT secret_sha256, consumed_at FROM auth_bootstrap WHERE id=1"
            ).fetchone()
            current = None
            try:
                current = path.read_text(encoding="utf-8").strip()
            except OSError:
                pass
            if (
                row is not None
                and row["consumed_at"] is None
                and current
                and hmac.compare_digest(
                    hashlib.sha256(current.encode("utf-8")).hexdigest(),
                    row["secret_sha256"],
                )
            ):
                return False

            secret = secrets.token_urlsafe(32)
            _write_bootstrap_secret(path, secret)
            digest = hashlib.sha256(secret.encode("utf-8")).hexdigest()
            conn.execute(
                """INSERT INTO auth_bootstrap(id,secret_sha256,consumed_at)
                   VALUES(1,?,NULL)
                   ON CONFLICT(id) DO UPDATE SET
                     secret_sha256=excluded.secret_sha256,
                     consumed_at=NULL,
                     created_at=CURRENT_TIMESTAMP""",
                (digest,),
            )
            created = True
    if remove_file:
        try:
            path.unlink(missing_ok=True)
        except OSError:
            pass
    return created


def _password_hash(password: str, salt: bytes) -> bytes:
    return hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, _ITERATIONS)


def _validate_password(password: Any) -> str:
    if not isinstance(password, str) or len(password) < 12 or len(password) > 256:
        raise AuthError("Mật khẩu phải có từ 12 đến 256 ký tự.")
    if password.strip() != password:
        raise AuthError("Mật khẩu không được có khoảng trắng ở đầu hoặc cuối.")
    return password


def owner_exists() -> bool:
    with connection() as conn:
        return conn.execute("SELECT 1 FROM auth_users LIMIT 1").fetchone() is not None


def create_first_owner(username: Any, password: Any, bootstrap_secret: Any) -> dict:
    if not isinstance(username, str):
        raise AuthError("Tên đăng nhập không hợp lệ.")
    username = username.strip().lower()
    if not 3 <= len(username) <= 40 or not username.replace("_", "").replace("-", "").isalnum():
        raise AuthError("Tên đăng nhập phải dài 3–40 ký tự, chỉ gồm chữ, số, _ hoặc -.")
    password = _validate_password(password)
    salt = secrets.token_bytes(16)
    if not isinstance(bootstrap_secret, str) or not 32 <= len(bootstrap_secret) <= 256:
        raise BootstrapSecretError("Bootstrap secret không hợp lệ hoặc đã được sử dụng.")
    bootstrap_digest = hashlib.sha256(bootstrap_secret.encode("utf-8")).hexdigest()
    digest = _password_hash(password, salt)
    with connection() as conn:
        conn.execute("BEGIN IMMEDIATE")
        if conn.execute("SELECT 1 FROM auth_users LIMIT 1").fetchone():
            raise AuthError("Tài khoản chủ sở hữu đã được khởi tạo; không cho phép đăng ký thêm.")
        bootstrap = conn.execute(
            "SELECT secret_sha256,consumed_at FROM auth_bootstrap WHERE id=1"
        ).fetchone()
        if (
            bootstrap is None
            or bootstrap["consumed_at"] is not None
            or not hmac.compare_digest(bootstrap_digest, bootstrap["secret_sha256"])
        ):
            raise BootstrapSecretError("Bootstrap secret không hợp lệ hoặc đã được sử dụng.")
        consumed = conn.execute(
            """UPDATE auth_bootstrap SET consumed_at=CURRENT_TIMESTAMP
               WHERE id=1 AND consumed_at IS NULL AND secret_sha256=?""",
            (bootstrap_digest,),
        )
        if consumed.rowcount != 1:
            raise BootstrapSecretError("Bootstrap secret không hợp lệ hoặc đã được sử dụng.")
        conn.execute(
            "INSERT INTO auth_users(username,password_salt,password_hash,password_iterations) VALUES(?,?,?,?)",
            (username, salt.hex(), digest.hex(), _ITERATIONS),
        )
    try:
        _bootstrap_secret_path().unlink(missing_ok=True)
    except OSError:
        # The consumed marker in SQLite prevents replay even if cleanup fails.
        pass
    return {"username": username, "role": "owner"}


def _new_session(conn: Any, user_id: int) -> dict:
    token = secrets.token_urlsafe(_TOKEN_BYTES)
    token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
    expires = datetime.now(timezone.utc) + timedelta(days=_SESSION_DAYS)
    conn.execute(
        "INSERT INTO auth_sessions(user_id,token_sha256,expires_at) VALUES(?,?,?)",
        (user_id, token_hash, expires.isoformat()),
    )
    return {"access_token": token, "token_type": "bearer",
            "expires_at": expires.isoformat(), "expires_in": _SESSION_DAYS * 86400}


def login(username: Any, password: Any) -> dict:
    if (not isinstance(username, str) or not isinstance(password, str)
            or len(username) > 40 or len(password) > 256):
        raise AuthError("Tên đăng nhập hoặc mật khẩu không đúng.")
    with connection() as conn:
        conn.execute(
            "DELETE FROM auth_sessions WHERE expires_at < ? OR (revoked_at IS NOT NULL AND revoked_at < datetime('now','-30 days'))",
            (datetime.now(timezone.utc).isoformat(),),
        )
        row = conn.execute(
            "SELECT id,username,password_salt,password_hash,password_iterations FROM auth_users WHERE username=?",
            (username.strip().lower(),),
        ).fetchone()
        if row is None:
            # Spend comparable CPU time to reduce username enumeration timing.
            _password_hash(password[:256], bytes(16))
            raise AuthError("Tên đăng nhập hoặc mật khẩu không đúng.")
        calculated = hashlib.pbkdf2_hmac(
            "sha256", password.encode("utf-8"), bytes.fromhex(row["password_salt"]),
            int(row["password_iterations"]),
        )
        if not hmac.compare_digest(calculated.hex(), row["password_hash"]):
            raise AuthError("Tên đăng nhập hoặc mật khẩu không đúng.")
        session = _new_session(conn, int(row["id"]))
        return {**session, "user": {"username": row["username"], "role": "owner"}}


def authenticate(token: str | None) -> dict | None:
    if not token or len(token) > 512:
        return None
    digest = hashlib.sha256(token.encode("utf-8")).hexdigest()
    now = datetime.now(timezone.utc).isoformat()
    with connection() as conn:
        row = conn.execute(
            """SELECT u.id,u.username FROM auth_sessions s
               JOIN auth_users u ON u.id=s.user_id
               WHERE s.token_sha256=? AND s.revoked_at IS NULL AND s.expires_at>?""",
            (digest, now),
        ).fetchone()
    return {"id": int(row["id"]), "username": row["username"], "role": "owner"} if row else None


def revoke(token: str | None) -> bool:
    if not token or len(token) > 512:
        return False
    digest = hashlib.sha256(token.encode("utf-8")).hexdigest()
    with connection() as conn:
        cursor = conn.execute(
            "UPDATE auth_sessions SET revoked_at=CURRENT_TIMESTAMP WHERE token_sha256=? AND revoked_at IS NULL",
            (digest,),
        )
    return cursor.rowcount > 0
