import hmac
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from .db import init_db
from .routers.market import router as market_router


def api_token_is_valid(authorization: str | None, expected_token: str) -> bool:
    """Validate a shared bearer token without leaking comparison timing."""
    if not expected_token:
        return False
    scheme, separator, supplied = (authorization or "").partition(" ")
    return bool(
        separator
        and scheme.lower() == "bearer"
        and supplied
        and hmac.compare_digest(supplied.encode('utf-8'), expected_token.encode('utf-8'))
    )


def validate_security_configuration(environment: str, api_token: str) -> None:
    """Production deployments must not start with an unprotected API."""
    normalized_token = api_token.strip()
    if environment.strip().lower() == "production" and not normalized_token:
        raise RuntimeError(
            "SMARTSTOCK_API_TOKEN is required when SMARTSTOCK_ENV=production"
        )
    if normalized_token and len(normalized_token) < 32:
        raise RuntimeError("SMARTSTOCK_API_TOKEN must contain at least 32 characters")


@asynccontextmanager
async def lifespan(app: FastAPI):
    environment = os.getenv("SMARTSTOCK_ENV", "development")
    api_token = os.getenv("SMARTSTOCK_API_TOKEN", "").strip()
    validate_security_configuration(environment, api_token)
    init_db()
    yield


app = FastAPI(
    title="SmartStock Pro API",
    version="0.3.0",
    description="Vietnam equities research API; market data must have a declared source.",
    lifespan=lifespan,
)


@app.middleware("http")
async def protect_api_routes(request: Request, call_next):
    expected_token = os.getenv("SMARTSTOCK_API_TOKEN", "").strip()
    if request.url.path.startswith("/api/") and expected_token:
        if not api_token_is_valid(request.headers.get("authorization"), expected_token):
            return JSONResponse(
                status_code=401,
                content={"detail": "Valid Bearer API token required"},
                headers={"WWW-Authenticate": "Bearer"},
            )
    return await call_next(request)


app.include_router(market_router)


@app.get("/health", tags=["system"])
def health():
    return {"status": "ok", "service": "smartstock-pro-api", "version": "0.3.0"}
