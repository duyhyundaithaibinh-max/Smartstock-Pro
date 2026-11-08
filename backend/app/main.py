import hmac
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from . import auth
from .db import init_db
from .routers.market import router as market_router
from .routers.auth import router as auth_router
from .routers.training_eval import router as training_eval_router
from .routers.training_review import router as training_review_router


def api_token_is_valid(authorization: str | None, expected_token: str) -> bool:
    if not expected_token:
        return False
    scheme, separator, supplied = (authorization or "").partition(" ")
    return bool(
        separator
        and scheme.lower() == "bearer"
        and supplied
        and hmac.compare_digest(supplied.encode("utf-8"), expected_token.encode("utf-8"))
    )


def validate_security_configuration(environment: str, api_token: str) -> None:
    normalized_token = api_token.strip()
    if normalized_token and len(normalized_token) < 32:
        raise RuntimeError("SMARTSTOCK_API_TOKEN must contain at least 32 characters")


@asynccontextmanager
async def lifespan(app: FastAPI):
    environment = os.getenv("SMARTSTOCK_ENV", "development")
    api_token = os.getenv("SMARTSTOCK_API_TOKEN", "").strip()
    validate_security_configuration(environment, api_token)
    init_db()
    auth.ensure_bootstrap_secret()
    yield


app = FastAPI(
    title="SmartStock Pro API",
    version="0.4.0",
    description="Vietnam equities research API; market data must have a declared source.",
    lifespan=lifespan,
)
app.include_router(market_router)
app.include_router(auth_router)
app.include_router(training_eval_router)
app.include_router(training_review_router)


def _is_public_market_read(path: str) -> bool:
    exact = {
        "/api/v1/markets",
        "/api/v1/symbols",
        "/api/v1/candles",
        "/api/v1/candles/chart",
        "/api/v1/indicators",
    }
    if path in exact:
        return True
    if path.startswith("/api/v1/symbols/") and path.endswith("/detail"):
        return True
    if path in {
        "/api/v1/analysis/price-action",
        "/api/v1/analysis/fibonacci",
        "/api/v1/analysis/elliott",
        "/api/v1/analysis/volume-flow",
        "/api/v1/analysis/report",
    }:
        return True
    return False


@app.middleware("http")
async def require_local_owner(request: Request, call_next):
    path = request.url.path
    if path in {"/health", "/docs", "/redoc", "/openapi.json"}:
        return await call_next(request)
    if path in {
        "/api/v1/auth/status",
        "/api/v1/auth/register-first-owner",
        "/api/v1/auth/login",
    }:
        return await call_next(request)
    if request.method == "GET" and _is_public_market_read(path):
        return await call_next(request)

    header = request.headers.get("authorization", "")
    token = header[7:].strip() if header.lower().startswith("bearer ") else None
    user = auth.authenticate(token)
    # Backward-compatible fallback for installations that still use the
    # shared API token configured before local owner accounts were introduced.
    expected_token = os.getenv("SMARTSTOCK_API_TOKEN", "").strip()
    if user is None and api_token_is_valid(header, expected_token):
        request.state.user = {"id": 0, "username": "legacy-api-token", "role": "owner"}
        return await call_next(request)
    if user is None:
        return JSONResponse(
            status_code=401,
            content={"detail": "Cần đăng nhập SmartStock Pro để sử dụng chức năng này."},
            headers={"WWW-Authenticate": "Bearer"},
        )
    request.state.user = user
    return await call_next(request)


@app.get("/health", tags=["system"])
def health():
    return {"status": "ok", "service": "smartstock-pro-api", "version": "0.4.0"}
