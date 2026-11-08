"""Provider-neutral model gateway. No provider SDK or network call is included.

The default configuration is disabled and has a zero-dollar budget. A concrete
provider adapter must be added explicitly and enabled by deployment config.
"""
from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from typing import Any, Mapping, Protocol


@dataclass(frozen=True)
class ModelRequest:
    task: str
    input_text: str
    context: Mapping[str, Any] = field(default_factory=dict)
    estimated_cost_usd: float = 0.0
    max_output_tokens: int = 800

    def __post_init__(self) -> None:
        if not self.task.strip():
            raise ValueError("task must not be empty")
        if not self.input_text.strip():
            raise ValueError("input_text must not be empty")
        if self.estimated_cost_usd < 0:
            raise ValueError("estimated_cost_usd must be non-negative")
        if self.max_output_tokens < 1:
            raise ValueError("max_output_tokens must be positive")


@dataclass(frozen=True)
class ModelResponse:
    text: str
    provider: str
    model: str
    input_tokens: int = 0
    output_tokens: int = 0
    actual_cost_usd: float = 0.0


class ModelAdapter(Protocol):
    """Minimal contract implemented by a provider-specific adapter."""

    @property
    def provider_name(self) -> str: ...

    def generate(self, request: ModelRequest) -> ModelResponse: ...


@dataclass(frozen=True)
class ModelGatewayConfig:
    enabled: bool = False
    provider: str = "none"
    timeout_seconds: float = 20.0
    max_cost_usd: float = 0.0

    def __post_init__(self) -> None:
        if self.timeout_seconds <= 0:
            raise ValueError("timeout_seconds must be positive")
        if self.max_cost_usd < 0:
            raise ValueError("max_cost_usd must be non-negative")


@dataclass(frozen=True)
class ModelGatewayResult:
    status: str
    response: ModelResponse | None = None
    message: str | None = None


class ModelGateway:
    """Controls adapter selection, opt-in, timeout and cost preflight."""

    def __init__(
        self,
        config: ModelGatewayConfig | None = None,
        adapters: Mapping[str, ModelAdapter] | None = None,
    ) -> None:
        self.config = config or ModelGatewayConfig()
        self.adapters = dict(adapters or {})

    async def generate(self, request: ModelRequest) -> ModelGatewayResult:
        if not self.config.enabled:
            return ModelGatewayResult(
                status="disabled",
                message="Model calls are disabled; deterministic analysis remains available.",
            )

        adapter = self.adapters.get(self.config.provider)
        if adapter is None:
            return ModelGatewayResult(
                status="not_configured",
                message="No adapter is registered for the selected provider.",
            )
        if adapter.provider_name != self.config.provider:
            return ModelGatewayResult(
                status="provider_mismatch",
                message="Registered adapter provider does not match configured provider.",
            )
        if request.estimated_cost_usd > self.config.max_cost_usd:
            return ModelGatewayResult(
                status="budget_blocked",
                message="Estimated request cost exceeds the configured per-request budget.",
            )

        try:
            response = await asyncio.wait_for(
                asyncio.to_thread(adapter.generate, request),
                timeout=self.config.timeout_seconds,
            )
        except asyncio.TimeoutError:
            return ModelGatewayResult(status="timeout", message="Model request timed out.")
        except Exception as exc:  # provider errors must not break deterministic analysis
            return ModelGatewayResult(
                status="provider_error",
                message=f"Provider adapter failed: {type(exc).__name__}",
            )

        if response.actual_cost_usd < 0:
            return ModelGatewayResult(
                status="invalid_usage",
                message="Adapter returned a negative cost value.",
            )
        if response.actual_cost_usd > self.config.max_cost_usd:
            return ModelGatewayResult(
                status="cost_limit_exceeded",
                message="Reported cost exceeded the configured budget; review adapter pricing.",
            )
        return ModelGatewayResult(status="completed", response=response)
