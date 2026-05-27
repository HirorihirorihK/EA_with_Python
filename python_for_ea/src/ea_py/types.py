"""プロジェクト内で共有する型定義。"""

from __future__ import annotations

from typing import TypedDict


class OhlcBar(TypedDict):
    """MT5 OHLC CSVから読み込んだ1本分のローソク足。"""

    DateTime: str
    Open: float
    High: float
    Low: float
    Close: float


class OhlcSummary(TypedDict):
    """ローソク足配列から算出した数値要約。"""

    n: int
    high: float
    low: float
    range: float
    eatr: float
    eatr_baseline: float
    eatr_ratio: float
    latest_range: float
    latest_range_to_eatr: float
    latest_upper_wick: float
    latest_lower_wick: float
    avg_body: float
    up: int
    down: int
    slope: float


NumericList = list[int | float]
