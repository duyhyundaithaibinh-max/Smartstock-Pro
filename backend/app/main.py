from fastapi import FastAPI

app = FastAPI(title="SmartStock Pro API", version="0.1.0")


@app.get("/health", tags=["system"])
def health() -> dict[str, str]:
    return {"status": "ok", "service": "smartstock-pro-api", "version": "0.1.0"}


@app.get("/api/v1/markets", tags=["market"])
def markets() -> list[dict[str, str]]:
    return [
        {"code": "HOSE", "name": "Sở Giao dịch Chứng khoán TP.HCM"},
        {"code": "HNX", "name": "Sở Giao dịch Chứng khoán Hà Nội"},
        {"code": "UPCOM", "name": "Thị trường UPCoM"},
    ]
