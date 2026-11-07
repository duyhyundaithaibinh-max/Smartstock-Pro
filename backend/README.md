# SmartStock Pro API

## Requirements
- Python 3.11+
- PostgreSQL 16+ (database integration is introduced in a later milestone)

## Run locally
```bash
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\\Scripts\\activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Open `http://127.0.0.1:8000/docs` for the interactive API docs.
Health check: `GET /api/v1/health`.

## Tests
From the `backend` directory:
```bash
pytest
```

Do not commit real secrets. Copy `.env.example` to `.env` and replace placeholders locally.
