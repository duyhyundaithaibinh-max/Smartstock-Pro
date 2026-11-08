"""Owner-protected endpoint for evaluating locally generated model predictions."""
from typing import Any

from fastapi import APIRouter, Body, HTTPException

from .. import offline_model_evaluation

router = APIRouter(prefix="/api/v1/training", tags=["training"])


@router.post("/evaluation/predictions")
def evaluate_local_predictions(payload: dict[str, Any] = Body(...)):
    """Evaluate predictions from a local model against approved reference examples."""
    try:
        return offline_model_evaluation.evaluate_predictions(payload.get("predictions"))
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
