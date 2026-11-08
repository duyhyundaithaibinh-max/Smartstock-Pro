from typing import Any

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

from .. import auth

router = APIRouter(prefix="/api/v1/auth", tags=["authentication"])


class Credentials(BaseModel):
    username: str = Field(min_length=3, max_length=40)
    password: str = Field(min_length=12, max_length=256)


class FirstOwnerCredentials(Credentials):
    bootstrap_secret: str = Field(min_length=32, max_length=256)


@router.get("/status")
def auth_status():
    """Tell the client whether first-owner setup is still available."""
    return {"owner_initialized": auth.owner_exists(), "registration": "first_owner_only"}


@router.post("/register-first-owner", status_code=201)
def register_first_owner(payload: FirstOwnerCredentials):
    try:
        return auth.create_first_owner(
            payload.username, payload.password, payload.bootstrap_secret
        )
    except auth.BootstrapSecretError as exc:
        raise HTTPException(403, str(exc)) from exc
    except auth.AuthError as exc:
        raise HTTPException(409 if auth.owner_exists() else 422, str(exc)) from exc


@router.post("/login")
def create_session(payload: Credentials):
    try:
        return auth.login(payload.username, payload.password)
    except auth.AuthError as exc:
        raise HTTPException(401, str(exc)) from exc


@router.post("/logout")
def revoke_session(authorization: str | None = Header(default=None)):
    token = authorization[7:].strip() if authorization and authorization.lower().startswith("bearer ") else None
    if not token or not auth.revoke(token):
        raise HTTPException(401, "Phiên đăng nhập không hợp lệ hoặc đã hết hạn.")
    return {"status": "logged_out"}


@router.get("/me")
def current_session(authorization: str | None = Header(default=None)):
    token = authorization[7:].strip() if authorization and authorization.lower().startswith("bearer ") else None
    user = auth.authenticate(token)
    if user is None:
        raise HTTPException(401, "Phiên đăng nhập không hợp lệ hoặc đã hết hạn.")
    return user
