"""H1インバランス判定のUnit Test。"""

from __future__ import annotations

import pytest

from ea_py.market.imbalance import (
    adjust_strategies_for_imbalance,
    calculate_average_body_size,
    detect_imbalance_signal,
)
from ea_py.types import OhlcBar


def make_bar(open_price: float, close_price: float) -> OhlcBar:
    """テスト用OHLCバーを作る。"""
    high = max(open_price, close_price)
    low = min(open_price, close_price)
    return {
        "DateTime": "2026-01-01 00:00",
        "Open": open_price,
        "High": high,
        "Low": low,
        "Close": close_price,
    }


def test_calculate_average_body_size_excludes_current_bar() -> None:
    """平均実体サイズには判定対象足を含めない。"""
    ohlc = [make_bar(100.0, 101.0), make_bar(100.0, 102.0), make_bar(100.0, 110.0)]

    actual = calculate_average_body_size(ohlc, current_index=2, period=2)

    assert actual == 1.5


@pytest.mark.parametrize(
    ("open_price", "close_price", "expected"),
    [
        (100.0, 103.0, "BUY"),
        (103.0, 100.0, "SELL"),
        (100.0, 101.5, "NONE"),
    ],
)
def test_detect_imbalance_signal_various_current_bars_returns_expected(
    open_price: float,
    close_price: float,
    expected: str,
) -> None:
    """直近確定足の実体が平均実体の感度倍率を超えた時だけ方向シグナルを返す。"""
    ohlc = [make_bar(100.0, 101.0) for _ in range(20)]
    ohlc.append(make_bar(open_price, close_price))

    actual = detect_imbalance_signal(
        ohlc,
        avg_body_period=20,
        sensitivity=2.0,
        min_avg_body_size=0.01,
    )

    assert actual.signal == expected


def test_detect_imbalance_signal_tiny_average_body_returns_none() -> None:
    """平均実体が極小の場合は誤検知を避ける。"""
    ohlc = [make_bar(100.0, 100.0) for _ in range(20)]
    ohlc.append(make_bar(100.0, 103.0))

    actual = detect_imbalance_signal(
        ohlc,
        avg_body_period=20,
        sensitivity=2.0,
        min_avg_body_size=0.01,
    )

    assert actual.signal == "NONE"


def test_adjust_strategies_for_imbalance_conflicting_up_trend_keeps_stop_strategy() -> None:
    """H4上昇中の売りインバランスは順張りStopだけ残す。"""
    ohlc = [make_bar(100.0, 101.0) for _ in range(20)]
    ohlc.append(make_bar(103.0, 100.0))
    analysis = detect_imbalance_signal(
        ohlc,
        avg_body_period=20,
        sensitivity=2.0,
        min_avg_body_size=0.01,
    )

    actual = adjust_strategies_for_imbalance(
        [1, 2],
        trend_state=3,
        analysis=analysis,
        use_filter=True,
    )

    assert actual == [1]


def test_adjust_strategies_for_imbalance_conflicting_down_trend_keeps_stop_strategy() -> None:
    """H4下降中の買いインバランスは順張りStopだけ残す。"""
    ohlc = [make_bar(100.0, 101.0) for _ in range(20)]
    ohlc.append(make_bar(100.0, 103.0))
    analysis = detect_imbalance_signal(
        ohlc,
        avg_body_period=20,
        sensitivity=2.0,
        min_avg_body_size=0.01,
    )

    actual = adjust_strategies_for_imbalance(
        [3, 4],
        trend_state=5,
        analysis=analysis,
        use_filter=True,
    )

    assert actual == [3]
