"""market_state分類とH4方向パースのUnit Test。"""

from __future__ import annotations

import math

import pytest

from ea_py.market.trend_state import (
    classify_direction_from_ohlc,
    classify_market_state,
    parse_trend_012_or_none,
)
from ea_py.market.volatility import summarize_ohlc
from ea_py.types import OhlcBar, OhlcSummary


def summary_with(*, eatr_ratio: float, latest_range_to_eatr: float = 1.0, n: int = 20) -> OhlcSummary:
    """market_state分類テスト用のOHLC要約を作る。"""
    return {
        "n": n,
        "high": 10.0,
        "low": 1.0,
        "range": 9.0,
        "eatr": eatr_ratio,
        "eatr_baseline": 1.0,
        "eatr_ratio": eatr_ratio,
        "latest_range": latest_range_to_eatr,
        "latest_range_to_eatr": latest_range_to_eatr,
        "latest_upper_wick": 0.2,
        "latest_lower_wick": 0.2,
        "avg_body": 0.5,
        "up": 10,
        "down": 10,
        "slope": 0.1,
    }


def linear_ohlc(*, start: float, step: float, count: int = 72) -> list[OhlcBar]:
    """方向判定テスト用の線形OHLCを作る。"""
    bars: list[OhlcBar] = []
    for index in range(count):
        close = start + step * index
        open_ = close - step * 0.5
        high = max(open_, close) + 0.3
        low = min(open_, close) - 0.3
        bars.append(
            {
                "DateTime": str(index),
                "Open": open_,
                "High": high,
                "Low": low,
                "Close": close,
            }
        )
    return bars


def oscillating_ohlc(*, center: float = 100.0, count: int = 72) -> list[OhlcBar]:
    """方向判定テスト用の往復的なレンジOHLCを作る。"""
    closes = [center + math.sin(index * math.pi / 2.0) for index in range(count)]
    bars: list[OhlcBar] = []
    previous_close = closes[0]

    for index, close in enumerate(closes):
        open_ = previous_close
        high = max(open_, close) + 0.8
        low = min(open_, close) - 0.8
        bars.append(
            {
                "DateTime": str(index),
                "Open": open_,
                "High": high,
                "Low": low,
                "Close": close,
            }
        )
        previous_close = close

    return bars


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("0", 0),
        ("answer: 1", 1),
        ("2\nreason", 2),
        ("3", None),
        ("", None),
    ],
)
def test_parse_trend_012_or_none_various_inputs_returns_expected(text: str, expected: int | None) -> None:
    """GPT方向出力から0/1/2だけを許可して抽出する。"""
    actual = parse_trend_012_or_none(text)

    assert actual == expected


def test_classify_direction_from_ohlc_clear_uptrend_returns_up() -> None:
    """明確なH4上昇は方向1を返す。"""
    ohlc = linear_ohlc(start=100.0, step=1.0)

    actual, _reason = classify_direction_from_ohlc(ohlc, summarize_ohlc(ohlc))

    assert actual == 1


def test_classify_direction_from_ohlc_clear_downtrend_returns_down() -> None:
    """明確なH4下降は方向2を返す。"""
    ohlc = linear_ohlc(start=170.0, step=-1.0)

    actual, _reason = classify_direction_from_ohlc(ohlc, summarize_ohlc(ohlc))

    assert actual == 2


def test_classify_direction_from_ohlc_choppy_range_returns_range() -> None:
    """往復的なH4レンジは方向0へ倒す。"""
    ohlc = oscillating_ohlc()

    actual, _reason = classify_direction_from_ohlc(ohlc, summarize_ohlc(ohlc))

    assert actual == 0


@pytest.mark.parametrize(
    ("direction", "eatr_ratio", "expected"),
    [
        (0, 1.0, 0),
        (0, 1.2, 1),
        (1, 1.0, 2),
        (1, 1.2, 3),
        (2, 1.0, 4),
        (2, 1.2, 5),
    ],
)
def test_classify_market_state_direction_and_volatility_returns_expected(
    direction: int,
    eatr_ratio: float,
    expected: int,
) -> None:
    """方向判定とボラティリティ比から期待するmarket_stateへ分類する。"""
    actual, _reason = classify_market_state(direction, summary_with(eatr_ratio=eatr_ratio))

    assert actual == expected


def test_classify_market_state_extreme_volatility_returns_high_vol_state() -> None:
    """旧異常ボラティリティ閾値以上でも停止せず高ボラstateへ吸収する。"""
    actual, _reason = classify_market_state(1, summary_with(eatr_ratio=2.0))

    assert actual == 3


def test_classify_market_state_extreme_latest_range_returns_high_vol_state() -> None:
    """直近足レンジが旧異常閾値以上でも方向に応じた高ボラstateを返す。"""
    actual, _reason = classify_market_state(2, summary_with(eatr_ratio=1.0, latest_range_to_eatr=2.5))

    assert actual == 5
