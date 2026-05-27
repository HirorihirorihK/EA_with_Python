"""ボラティリティ計算のUnit Test。"""

from __future__ import annotations

from ea_py.market.volatility import calc_exponential_atr_values, calc_true_ranges, summarize_ohlc
from ea_py.types import OhlcBar


def test_calc_true_ranges_uses_previous_close_for_gap_range() -> None:
    """ギャップがある足では前回終値との差をTrue Rangeに反映する。"""
    ohlc: list[OhlcBar] = [
        {"DateTime": "1", "Open": 10.0, "High": 12.0, "Low": 9.0, "Close": 11.0},
        {"DateTime": "2", "Open": 15.0, "High": 16.0, "Low": 14.0, "Close": 15.0},
    ]

    actual = calc_true_ranges(ohlc)

    assert actual == [3.0, 5.0]


def test_calc_exponential_atr_values_short_series_returns_seed_for_all_values() -> None:
    """期間未満のTR列では平均値を全要素のEATRとして返す。"""
    actual = calc_exponential_atr_values([2.0, 4.0], period=14)

    assert actual == [3.0, 3.0]


def test_summarize_ohlc_slope_uses_weighted_close() -> None:
    """傾きはClose単体ではなくWeighted Closeの始点/終点差から計算する。"""
    ohlc: list[OhlcBar] = [
        {"DateTime": "1", "Open": 10.0, "High": 20.0, "Low": 10.0, "Close": 10.0},
        {"DateTime": "2", "Open": 10.0, "High": 30.0, "Low": 10.0, "Close": 10.0},
    ]

    actual = summarize_ohlc(ohlc)

    assert actual["slope"] == 2.5
