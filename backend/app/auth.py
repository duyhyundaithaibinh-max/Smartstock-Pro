"""Single-owner local authentication using PBKDF2 password hashes and opaque sessions.

This is intended for a single trusted SmartStock installation, not a public
multi-tenant service. Session tokens are random, stored only as SHA-256 hashes,
and expire after a bounded lifetime.
"""
from __future__ import annotations

import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

from .db import connection

_ITERATIONS = 310_000
_SESSION_DAYS = 14
_TOKEN_BYTES = 32


class AuthError(ValueError):
    pass


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


def create_first_owner(username: Any, password: Any) -> dict:
    if not isinstance(username, str):
        raise AuthError("Tên đăng nhập không hợp lệ.")
    username = username.strip().lower()
    if not 3 <= len(username) <= 40 or not username.replace("_", "").replace("-", "").isalnum():
        raise AuthError("Tên đăng nhập phải dài 3–40 ký tự, chỉ gồm chữ, số, _ hoặc -.")
    password = _validate_password(password)
    salt = secrets.token_bytes(16)
    digest = _password_hash(password, salt)
    with connection() as conn:
        if conn.execute("SELECT 1 FROM auth_users LIMIT 1").fetchone():
            raise AuthError("Tài khoản chủ sở hữu đã được khởi tạo; không cho phép đăng ký thêm.")
        conn.execute(
            "INSERT INTO auth_users(username,password_salt,password_hash,password_iterations) VALUES(?,?,?,?)",
            (username, salt.hex(), digest.hex(), _ITERATIONS),
        )
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
    if not isinstance(username, str) or not isinstance(password, str):
        raise AuthError("Tên đăng nhập hoặc mật khẩu không đúng.")
    with connection() as conn:
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
