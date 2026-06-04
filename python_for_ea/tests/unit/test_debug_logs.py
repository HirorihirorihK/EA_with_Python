"""Debug log output tests."""

from __future__ import annotations

from pathlib import Path

from ea_py.io.debug_logs import append_debug_entry_stop


def test_append_debug_entry_stop_records_safe_stop_reason(tmp_path: Path) -> None:
    """Safe-stop diagnostics distinguish a guarded stop from a normal GPT skip."""
    path = tmp_path / "debug_entry.txt"

    append_debug_entry_stop(
        path=path,
        stage="openai_api",
        reason="RateLimitError: retry later",
        trend_state=2,
        selected_strategies=[1, 2],
        candidate_id="202606012100",
        current_price=4535.17,
        imbalance_summary="signal=NONE",
    )

    actual = path.read_text(encoding="utf-8")
    assert "RESULT            : SAFE_STOP" in actual
    assert "STAGE             : openai_api" in actual
    assert "REASON            : RateLimitError: retry later" in actual
    assert "MARKET_STATE(H4)  : 2 (LOW_VOL_UP)" in actual
    assert "SELECTED_STRATEGY : 1,2" in actual
    assert "CANDIDATE_ID      : 202606012100" in actual
