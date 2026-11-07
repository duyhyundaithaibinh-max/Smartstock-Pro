from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_root_returns_service_status() -> None:
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["name"] == "SmartStock Pro API"


def test_health_endpoint() -> None:
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
