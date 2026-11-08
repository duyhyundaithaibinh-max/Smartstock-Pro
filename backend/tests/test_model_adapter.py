import asyncio

from app.model_adapter import (
    ModelGateway,
    ModelGatewayConfig,
    ModelRequest,
    ModelResponse,
)


class FakeAdapter:
    provider_name = "fake"

    def __init__(self, response=None, delay=0):
        self.response = response or ModelResponse(
            text="Interpretation", provider="fake", model="fake-v1",
            input_tokens=10, output_tokens=5, actual_cost_usd=0.0,
        )
        self.delay = delay
        self.calls = 0

    def generate(self, request):
        import time
        self.calls += 1
        if self.delay:
            time.sleep(self.delay)
        return self.response


def request(cost=0.0):
    return ModelRequest(task="explain_report", input_text="Explain this report", estimated_cost_usd=cost)


def test_gateway_is_disabled_by_default_and_does_not_call_adapter():
    adapter = FakeAdapter()
    result = asyncio.run(ModelGateway(adapters={"fake": adapter}).generate(request()))
    assert result.status == "disabled"
    assert adapter.calls == 0


def test_missing_provider_adapter_is_reported_without_network_call():
    gateway = ModelGateway(
        ModelGatewayConfig(enabled=True, provider="missing", max_cost_usd=1.0)
    )
    assert asyncio.run(gateway.generate(request())).status == "not_configured"


def test_request_is_blocked_when_estimated_cost_exceeds_budget():
    adapter = FakeAdapter()
    gateway = ModelGateway(
        ModelGatewayConfig(enabled=True, provider="fake", max_cost_usd=0.0),
        {"fake": adapter},
    )
    result = asyncio.run(gateway.generate(request(cost=0.01)))
    assert result.status == "budget_blocked"
    assert adapter.calls == 0


def test_provider_adapter_can_be_invoked_when_explicitly_enabled():
    adapter = FakeAdapter()
    gateway = ModelGateway(
        ModelGatewayConfig(enabled=True, provider="fake", max_cost_usd=0.1),
        {"fake": adapter},
    )
    result = asyncio.run(gateway.generate(request()))
    assert result.status == "completed"
    assert result.response.text == "Interpretation"
    assert adapter.calls == 1


def test_timeout_is_contained_and_returned_as_status():
    adapter = FakeAdapter(delay=0.1)
    gateway = ModelGateway(
        ModelGatewayConfig(enabled=True, provider="fake", timeout_seconds=0.01, max_cost_usd=0.1),
        {"fake": adapter},
    )
    result = asyncio.run(gateway.generate(request()))
    assert result.status == "timeout"


def test_provider_exception_does_not_escape_gateway():
    class BrokenAdapter:
        provider_name = "fake"
        def generate(self, request):
            raise RuntimeError("secret provider details")

    gateway = ModelGateway(
        ModelGatewayConfig(enabled=True, provider="fake", max_cost_usd=0.1),
        {"fake": BrokenAdapter()},
    )
    result = asyncio.run(gateway.generate(request()))
    assert result.status == "provider_error"
    assert "secret provider details" not in (result.message or "")
