"""デバッグ理由ログをMT5 Files配下へ追記する。"""

from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import Sequence

from ea_py.constants import MARKET_STATE_LABELS


def now_str() -> str:
    """デバッグログ用の現在時刻文字列を返す。"""
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def append_debug_trend(
    *,
    path: Path,
    model: str,
    reasoning_effort: str,
    max_output_tokens: int,
    api_diagnostics: str,
    current_price: float,
    numeric_summary: str,
    direction_numeric: str,
    market_state: int,
    classification_reason: str,
    reason_text: str,
) -> None:
    """H4トレンド判定の数値要約、方向出力、分類理由を追記する。"""
    with path.open("a", encoding="utf-8") as file:
        file.write("=" * 60 + "\n")
        file.write(f"DEBUG TIME    : {now_str()}\n")
        file.write(f"MODEL         : {model}\n")
        file.write(f"REASONING     : {reasoning_effort}\n")
        file.write(f"MAX TOKENS    : {max_output_tokens}\n")
        file.write(f"CURRENT PRICE : {current_price:.2f}\n")
        file.write(f"MARKET STATE  : {market_state} ({MARKET_STATE_LABELS.get(market_state, 'UNKNOWN')})\n")
        file.write("=" * 60 + "\n\n")
        file.write("---- API DIAGNOSTICS START ----\n")
        file.write((api_diagnostics or "").strip() + "\n")
        file.write("---- API DIAGNOSTICS END ----\n\n")
        file.write("---- NUMERIC SUMMARY START ----\n")
        file.write((numeric_summary or "").strip() + "\n")
        file.write("---- NUMERIC SUMMARY END ----\n\n")
        file.write("---- DIRECTION NUMERIC (0/1/2) START ----\n")
        file.write((direction_numeric or "").strip() + "\n")
        file.write("---- DIRECTION NUMERIC (0/1/2) END ----\n\n")
        file.write("---- MARKET STATE CLASSIFICATION START ----\n")
        file.write((classification_reason or "").strip() + "\n")
        file.write("---- MARKET STATE CLASSIFICATION END ----\n\n")
        file.write("---- REASON START ----\n")
        file.write((reason_text or "").strip() + "\n")
        file.write("---- REASON END ----\n\n")


def append_debug_entry(
    *,
    path: Path,
    model: str,
    reasoning_effort: str,
    text_verbosity: str,
    max_output_tokens: int,
    api_diagnostics: str,
    timeframe: str,
    current_price: float,
    trend_state: int,
    selected_strategies: Sequence[int],
    imbalance_summary: str,
    numeric_summary: str,
    numeric_lines: str,
    post_filter_summary: str,
    sanitized_numeric_list: Sequence[int | float] | None,
    reason_text: str,
) -> None:
    """H1エントリー候補生成の数値行と理由を追記する。"""
    with path.open("a", encoding="utf-8") as file:
        file.write("=" * 60 + "\n")
        file.write(f"DEBUG TIME        : {now_str()}\n")
        file.write(f"MODEL             : {model}\n")
        file.write(f"REASONING         : {reasoning_effort}\n")
        file.write(f"VERBOSITY         : {text_verbosity}\n")
        file.write(f"MAX TOKENS        : {max_output_tokens}\n")
        file.write(f"TIMEFRAME         : {timeframe}\n")
        file.write(f"MARKET_STATE(H4)  : {trend_state} ({MARKET_STATE_LABELS.get(trend_state, 'UNKNOWN')})\n")
        file.write(f"SELECTED_STRATEGY : {','.join(str(x) for x in selected_strategies)}\n")
        file.write(f"IMBALANCE(H1)     : {imbalance_summary}\n")
        file.write(f"CURRENT PRICE     : {current_price:.2f}\n")
        file.write("=" * 60 + "\n\n")
        file.write("---- API DIAGNOSTICS START ----\n")
        file.write((api_diagnostics or "").strip() + "\n")
        file.write("---- API DIAGNOSTICS END ----\n\n")
        file.write("---- NUMERIC SUMMARY START ----\n")
        file.write((numeric_summary or "").strip() + "\n")
        file.write("---- NUMERIC SUMMARY END ----\n\n")
        file.write("---- GPT NUMERIC LINES START ----\n")
        file.write((numeric_lines or "").strip() + "\n")
        file.write("---- GPT NUMERIC LINES END ----\n\n")
        file.write("---- POST FILTER START ----\n")
        file.write((post_filter_summary or "").strip() + "\n")
        if sanitized_numeric_list is not None:
            file.write("sanitized_numeric_list=" + ",".join(str(x) for x in sanitized_numeric_list) + "\n")
        file.write("---- POST FILTER END ----\n\n")
        file.write("---- REASON START ----\n")
        file.write((reason_text or "").strip() + "\n")
        file.write("---- REASON END ----\n\n")


def append_debug_entry_stop(
    *,
    path: Path,
    stage: str,
    reason: str,
    trend_state: int,
    selected_strategies: Sequence[int] = (),
    candidate_id: str = "",
    current_price: float | None = None,
    imbalance_summary: str = "",
) -> None:
    """H1候補生成が安全側停止値へ倒れた理由を追記する。"""
    with path.open("a", encoding="utf-8") as file:
        file.write("=" * 60 + "\n")
        file.write(f"DEBUG TIME        : {now_str()}\n")
        file.write("RESULT            : SAFE_STOP\n")
        file.write(f"STAGE             : {stage}\n")
        file.write(f"REASON            : {reason}\n")
        file.write(f"MARKET_STATE(H4)  : {trend_state} ({MARKET_STATE_LABELS.get(trend_state, 'UNKNOWN')})\n")
        file.write(f"SELECTED_STRATEGY : {','.join(str(x) for x in selected_strategies) or '-'}\n")
        file.write(f"CANDIDATE_ID      : {candidate_id or '-'}\n")
        if current_price is not None:
            file.write(f"CURRENT PRICE     : {current_price:.2f}\n")
        if imbalance_summary:
            file.write(f"IMBALANCE(H1)     : {imbalance_summary}\n")
        file.write("=" * 60 + "\n\n")
