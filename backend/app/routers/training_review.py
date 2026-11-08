from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field, StrictInt, StrictStr, model_validator

from .. import training_room

router = APIRouter(prefix="/api/v1/training", tags=["training-review"])


class RejectPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")
    reason: StrictStr = Field(min_length=1, max_length=1000)


class EditPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")
    expected_revision: StrictInt = Field(ge=1)
    question: StrictStr | None = Field(default=None, min_length=10, max_length=1000)
    expected_answer: StrictStr | None = Field(default=None, min_length=20, max_length=5000)
    topic: StrictStr | None = Field(default=None, min_length=1, max_length=80)
    citation_ids: list[StrictStr] | None = None

    @model_validator(mode="after")
    def require_edit_field(self):
        if not self.model_fields_set.intersection({"question", "expected_answer", "topic", "citation_ids"}):
            raise ValueError("Provide at least one field to update.")
        return self


class QualityReviewPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")
    score: StrictInt = Field(ge=0, le=100)
    rubric_version: StrictStr = Field(min_length=1, max_length=40)
    rationale: StrictStr = Field(min_length=10, max_length=2000)


def _reviewer_id(request: Request) -> int:
    user = getattr(request.state, "user", None) or {}
    user_id = user.get("id")
    if type(user_id) is not int or user_id <= 0:
        raise HTTPException(403, "Human review requires an authenticated owner session.")
    return user_id


@router.post("/examples/{example_id}/reject")
def reject_training_example(example_id: int, payload: RejectPayload, request: Request):
    try:
        result = training_room.reject_example(example_id, payload.reason, _reviewer_id(request))
    except training_room.TrainingConflictError as exc:
        raise HTTPException(409, str(exc)) from exc
    except training_room.TrainingDataError as exc:
        raise HTTPException(422, str(exc)) from exc
    if result is None:
        raise HTTPException(404, "Training example not found")
    return result


@router.patch("/examples/{example_id}")
def edit_training_example(example_id: int, payload: EditPayload, request: Request):
    try:
        result = training_room.edit_draft_example(
            example_id,
            payload.model_dump(exclude_unset=True),
            _reviewer_id(request),
        )
    except training_room.TrainingConflictError as exc:
        raise HTTPException(409, str(exc)) from exc
    except training_room.TrainingDataError as exc:
        raise HTTPException(422, str(exc)) from exc
    if result is None:
        raise HTTPException(404, "Training example not found")
    return result


@router.post("/examples/{example_id}/quality-reviews", status_code=201)
def create_training_quality_review(example_id: int, payload: QualityReviewPayload, request: Request):
    try:
        result = training_room.create_quality_review(
            example_id, payload.score, payload.rubric_version, payload.rationale,
            _reviewer_id(request),
        )
    except training_room.TrainingDataError as exc:
        raise HTTPException(422, str(exc)) from exc
    if result is None:
        raise HTTPException(404, "Training example not found")
    return result


@router.get("/examples/{example_id}/quality-reviews")
def get_training_quality_reviews(example_id: int, request: Request):
    _reviewer_id(request)
    result = training_room.list_quality_reviews(example_id)
    if result is None:
        raise HTTPException(404, "Training example not found")
    return {"example_id": example_id, "items": result, "count": len(result)}



@router.get("/examples/{example_id}/review-events")
def get_training_review_events(
    example_id: int,
    request: Request,
    limit: int = 50,
    offset: int = 0,
):
    """Return chronological append-only approve/reject/edit events for one example."""
    _reviewer_id(request)
    try:
        result = training_room.list_review_events(example_id, limit=limit, offset=offset)
    except training_room.TrainingDataError as exc:
        raise HTTPException(422, str(exc)) from exc
    if result is None:
        raise HTTPException(404, "Training example not found")
    return result
