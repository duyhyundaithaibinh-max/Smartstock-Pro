"""Append-only, locally stored versions of technical-analysis rule configurations."""
from __future__ import annotations

import hashlib
import json
import re
from typing import Any

from .db import connection

_VERSION = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
_MAX_CONFIG_BYTES = 20_000


def _canonical_config(config: Any) -> tuple[str, str]:
    if not isinstance(config, dict):
        raise ValueError("config must be a JSON object")
    try:
        encoded = json.dumps(config, ensure_ascii=False, sort_keys=True,
                             separators=(",", ":"), allow_nan=False)
    except (TypeError, ValueError) as exc:
        raise ValueError("config must contain finite JSON values only") from exc
    if len(encoded.encode("utf-8")) > _MAX_CONFIG_BYTES:
        raise ValueError("config exceeds 20000 UTF-8 bytes")
    return encoded, hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def _serialize(row) -> dict[str, Any]:
    item = dict(row)
    item["config"] = json.loads(item.pop("config_json"))
    return item


def ensure_default_version() -> None:
    config_json, digest = _canonical_config({})
    with connection() as conn:
        conn.execute(
            """INSERT OR IGNORE INTO analysis_rule_versions
               (version,name,description,config_json,config_sha256,status,activated_at)
               VALUES(?,?,?,?,?,'active',CURRENT_TIMESTAMP)""",
            ("1.0.0", "SmartStock baseline", "Built-in baseline rule metadata; existing engine defaults remain authoritative.", config_json, digest),
        )


def list_versions(limit: int = 100, offset: int = 0) -> dict[str, Any]:
    if not 1 <= limit <= 500 or offset < 0:
        raise ValueError("limit must be 1..500 and offset must be non-negative")
    ensure_default_version()
    with connection() as conn:
        rows = conn.execute(
            """SELECT id,version,name,description,config_json,config_sha256,
                      status,created_at,activated_at
               FROM analysis_rule_versions
               ORDER BY id DESC LIMIT ? OFFSET ?""",
            (limit, offset),
        ).fetchall()
        total = conn.execute("SELECT COUNT(*) FROM analysis_rule_versions").fetchone()[0]
    return {"total": total, "items": [_serialize(row) for row in rows]}


def get_version(version: str) -> dict[str, Any] | None:
    ensure_default_version()
    with connection() as conn:
        row = conn.execute(
            """SELECT id,version,name,description,config_json,config_sha256,
                      status,created_at,activated_at
               FROM analysis_rule_versions WHERE version=?""",
            (version,),
        ).fetchone()
    return _serialize(row) if row else None


def get_active_version() -> dict[str, Any]:
    ensure_default_version()
    with connection() as conn:
        row = conn.execute(
            """SELECT id,version,name,description,config_json,config_sha256,
                      status,created_at,activated_at
               FROM analysis_rule_versions WHERE status='active'"""
        ).fetchone()
    return _serialize(row)


def create_version(version: str, name: str, description: str, config: dict) -> dict[str, Any]:
    if not isinstance(version, str) or not _VERSION.fullmatch(version):
        raise ValueError("version must use semantic version format MAJOR.MINOR.PATCH")
    if not isinstance(name, str) or not name.strip() or len(name.strip()) > 120:
        raise ValueError("name must contain 1 to 120 characters")
    if not isinstance(description, str) or len(description) > 2000:
        raise ValueError("description must not exceed 2000 characters")
    config_json, digest = _canonical_config(config)
    ensure_default_version()
    with connection() as conn:
        try:
            cursor = conn.execute(
                """INSERT INTO analysis_rule_versions
                   (version,name,description,config_json,config_sha256,status)
                   VALUES(?,?,?,?,?,'draft')""",
                (version, name.strip(), description.strip(), config_json, digest),
            )
        except Exception as exc:
            if "UNIQUE" in str(exc):
                raise ValueError("version already exists; create a new version instead of overwriting") from exc
            raise
        row = conn.execute(
            """SELECT id,version,name,description,config_json,config_sha256,
                      status,created_at,activated_at
               FROM analysis_rule_versions WHERE id=?""",
            (cursor.lastrowid,),
        ).fetchone()
    return _serialize(row)


def activate_version(version: str) -> dict[str, Any]:
    ensure_default_version()
    with connection() as conn:
        target = conn.execute(
            "SELECT id,status FROM analysis_rule_versions WHERE version=?", (version,)
        ).fetchone()
        if target is None:
            raise KeyError("rule version not found")
        if target["status"] != "active":
            conn.execute(
                "UPDATE analysis_rule_versions SET status='archived' WHERE status='active'"
            )
            conn.execute(
                """UPDATE analysis_rule_versions
                   SET status='active',activated_at=CURRENT_TIMESTAMP WHERE id=?""",
                (target["id"],),
            )
        row = conn.execute(
            """SELECT id,version,name,description,config_json,config_sha256,
                      status,created_at,activated_at
               FROM analysis_rule_versions WHERE id=?""",
            (target["id"],),
        ).fetchone()
    return _serialize(row)
