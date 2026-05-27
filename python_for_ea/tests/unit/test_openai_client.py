"""OpenAI Responses API wrapper tests."""

from __future__ import annotations

from typing import Any

from ea_py.openai_client import call_responses_api


class FakeDumpable:
    """Minimal SDK-like object exposing model_dump."""

    def __init__(self, data: dict[str, object]) -> None:
        self._data = data

    def model_dump(self, *, mode: str, exclude_none: bool) -> dict[str, object]:
        """Return JSON-serializable diagnostic data."""
        return self._data


class FakeResponse:
    """Minimal Responses API response shape used by the wrapper."""

    def __init__(self, *, output_text: str, incomplete_details: object | None = None) -> None:
        self.output_text = output_text
        self.model = "gpt-5.5-2026-04-23"
        self.status = "completed"
        self.incomplete_details = incomplete_details
        self.error = None
        self.usage = FakeDumpable({"input_tokens": 10, "output_tokens": 1})


class FakeResponsesResource:
    """Capture create parameters and return a fixed response."""

    def __init__(self, response: FakeResponse) -> None:
        self.response = response
        self.create_params: dict[str, Any] = {}

    def create(self, **kwargs: Any) -> FakeResponse:
        """Record the request payload."""
        self.create_params = kwargs
        return self.response


class FakeClient:
    """Minimal OpenAI client shape."""

    def __init__(self, response: FakeResponse) -> None:
        self.responses = FakeResponsesResource(response)


def test_call_responses_api_sends_reasoning_and_omits_temperature() -> None:
    """GPT-5.5 requests should use reasoning controls instead of temperature."""
    fake_client = FakeClient(FakeResponse(output_text=" 0\n"))

    actual = call_responses_api(
        client=fake_client,  # type: ignore[arg-type]
        model="gpt-5.5-2026-04-23",
        reasoning_effort="none",
        system_content="Return one number.",
        user_text="Classify.",
        image_data_urls=[],
        max_output_tokens=128,
    )

    assert actual.text == "0"
    assert fake_client.responses.create_params["reasoning"] == {"effort": "none"}
    assert fake_client.responses.create_params["max_output_tokens"] == 128
    assert "temperature" not in fake_client.responses.create_params


def test_call_responses_api_returns_incomplete_diagnostics_for_empty_text() -> None:
    """Empty output_text keeps the API status details for live diagnosis."""
    fake_client = FakeClient(
        FakeResponse(
            output_text="",
            incomplete_details=FakeDumpable({"reason": "max_output_tokens"}),
        )
    )

    actual = call_responses_api(
        client=fake_client,  # type: ignore[arg-type]
        model="gpt-5.5-2026-04-23",
        reasoning_effort="low",
        system_content="Return one number.",
        user_text="Classify.",
        image_data_urls=[],
        max_output_tokens=8,
    )

    assert actual.text == ""
    assert "max_output_tokens" in actual.diagnostics.incomplete_details
