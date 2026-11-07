from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(
    title="SmartStock Pro API",
    description="Backend API for AI-assisted Vietnamese stock market research.",
    version="0.1.0",
)

# Restrict origins through configuration before deploying publicly.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:8080"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)


@app.get("/", tags=["system"])
async def root() -> dict[str, str]:
    return {"name": "SmartStock Pro API", "status": "running"}


@app.get("/api/v1/health", tags=["system"])
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "smartstock-api", "version": "0.1.0"}
