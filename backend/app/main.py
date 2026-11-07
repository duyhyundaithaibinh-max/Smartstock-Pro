from contextlib import asynccontextmanager
from fastapi import FastAPI
from .db import init_db
from .routers.market import router as market_router

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield

app=FastAPI(title="SmartStock Pro API",version="0.3.0",
    description="Vietnam equities research API; market data must have a declared source.",lifespan=lifespan)
app.include_router(market_router)

@app.get("/health",tags=["system"])
def health():
    return {"status":"ok","service":"smartstock-pro-api","version":"0.3.0"}
