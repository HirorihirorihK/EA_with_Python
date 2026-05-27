"""Runtime config loading tests."""

from __future__ import annotations

import pytest

from ea_py.config import load_runtime_config


def test_load_runtime_config_reads_model_and_reasoning_from_env(monkeypatch: pytest.MonkeyPatch) -> None:
    """OpenAI model and reasoning effort can be overridden without code edits."""
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setenv("OPENAI_MODEL", "gpt-test")
    monkeypatch.setenv("OPENAI_REASONING_EFFORT", "low")

    actual = load_runtime_config()

    assert actual.api_key == "test-key"
    assert actual.model == "gpt-test"
    assert actual.reasoning_effort == "low"


def test_load_runtime_config_rejects_invalid_reasoning_effort(monkeypatch: pytest.MonkeyPatch) -> None:
    """Invalid reasoning effort should fail before an API call is attempted."""
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setenv("OPENAI_REASONING_EFFORT", "fastest")

    with pytest.raises(RuntimeError, match="OPENAI_REASONING_EFFORT"):
        load_runtime_config()
