"""target_prices変換と戦略選択のUnit Test。"""

from __future__ import annotations

from ea_py.market.target_prices import parse_lines_to_13_allow_subset, sanitize_numeric_list, strategies_by_trend
from ea_py.market.target_zones import (
    build_candidate_id,
    format_target_zones,
    parse_lines_to_entry_zones_allow_subset,
    sanitize_entry_zones,
    zones_to_numeric_list,
)


def test_strategies_by_trend_range_state_returns_countertrend_strategies() -> None:
    """レンジstateでは逆張り買いと逆張り売りだけを選択する。"""
    actual = strategies_by_trend(0)

    assert actual == [2, 4]


def test_parse_lines_to_13_allow_subset_valid_subset_returns_13_values() -> None:
    """GPTの一部戦略行を13値のtarget_prices形式へ展開する。"""
    actual = parse_lines_to_13_allow_subset("2,1900.00,1910.00,1890.00\n4,1930.00,1920.00,1940.00")

    assert actual == [1, 0.0, 0.0, 0.0, 1900.0, 1910.0, 1890.0, 0.0, 0.0, 0.0, 1930.0, 1920.0, 1940.0]


def test_parse_lines_to_13_allow_subset_no_prices_returns_all_stop_values() -> None:
    """有効価格がない場合は全停止値を返す。"""
    actual = parse_lines_to_13_allow_subset("2,0.00,0.00,0.00")

    assert actual == [0] * 13


def test_sanitize_numeric_list_invalid_unselected_strategy_zeroes_it() -> None:
    """未選択戦略と価格条件違反の戦略を0.00へ補正する。"""
    parsed = [1, 1910.0, 1920.0, 1900.0, 1890.0, 1900.0, 1880.0, 1880.0, 1870.0, 1890.0, 1930.0, 1920.0, 1940.0]

    actual = sanitize_numeric_list(parsed, selected_strategies=[2, 4], current_price=1900.0)

    assert actual == [1, 0.0, 0.0, 0.0, 1890.0, 1900.0, 1880.0, 0.0, 0.0, 0.0, 1930.0, 1920.0, 1940.0]


def test_sanitize_numeric_list_rejects_far_entry_price() -> None:
    """現在価格から遠すぎる候補は遅延エントリー防止のため0.00へ補正する。"""
    parsed = [1, 0.0, 0.0, 0.0, 1870.0, 1900.0, 1860.0, 0.0, 0.0, 0.0, 1910.0, 1880.0, 1920.0]

    actual = sanitize_numeric_list(parsed, selected_strategies=[2, 4], current_price=1900.0, max_entry_distance=20.0)

    assert actual == [1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1910.0, 1880.0, 1920.0]


def test_sanitize_numeric_list_uses_strategy_specific_entry_distance() -> None:
    """戦略別の距離制限によりStop系だけ広い候補を残せる。"""
    parsed = [1, 1925.0, 1940.0, 1915.0, 1875.0, 1900.0, 1865.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

    actual = sanitize_numeric_list(
        parsed,
        selected_strategies=[1, 2],
        current_price=1900.0,
        max_entry_distance={1: 30.0, 2: 20.0},
    )

    assert actual == [1, 1925.0, 1940.0, 1915.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]


def test_parse_lines_to_entry_zones_allow_subset_valid_zone_returns_zone_values() -> None:
    """GPTのゾーン行を戦略別ゾーンへ展開する。"""
    actual = parse_lines_to_entry_zones_allow_subset("2,1895.00,1910.00,1885.00,1892.00,1898.00")

    assert actual[2].entry == 1895.0
    assert actual[2].zone_low == 1892.0
    assert actual[2].zone_high == 1898.0


def test_sanitize_entry_zones_invalid_unselected_strategy_zeroes_it() -> None:
    """未選択戦略のゾーンは停止値へ補正する。"""
    parsed = parse_lines_to_entry_zones_allow_subset(
        "1,1910.00,1925.00,1900.00,1908.00,1912.00\n"
        "2,1895.00,1910.00,1885.00,1892.00,1898.00"
    )

    actual = sanitize_entry_zones(parsed, selected_strategies=[2], current_price=1900.0)

    assert actual[1].entry == 0.0
    assert actual[2].entry == 1895.0


def test_sanitize_entry_zones_allows_near_zone_edge_when_entry_is_farther() -> None:
    """ゾーンの最寄り端が近い場合は広めの候補ゾーンを残す。"""
    parsed = parse_lines_to_entry_zones_allow_subset("2,1890.00,1910.00,1880.00,1890.00,1896.00")

    actual = sanitize_entry_zones(parsed, selected_strategies=[2], current_price=1900.0, max_entry_distance=5.0)

    assert actual[2].entry == 1890.0


def test_zones_to_numeric_list_valid_zone_returns_legacy_13_values() -> None:
    """有効ゾーンのentry/tp/slから既存13行形式を生成する。"""
    parsed = parse_lines_to_entry_zones_allow_subset("4,1910.00,1880.00,1920.00,1908.00,1912.00")
    sanitized = sanitize_entry_zones(parsed, selected_strategies=[4], current_price=1900.0)

    actual = zones_to_numeric_list(sanitized)

    assert actual == [1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1910.0, 1880.0, 1920.0]


def test_format_target_zones_includes_schema_candidate_and_all_strategies() -> None:
    """MT5向けゾーンファイルはschema/res/candidate/4戦略行で出力する。"""
    parsed = parse_lines_to_entry_zones_allow_subset("2,1895.00,1910.00,1885.00,1892.00,1898.00")
    sanitized = sanitize_entry_zones(parsed, selected_strategies=[2], current_price=1900.0)

    actual = format_target_zones(sanitized, "202605241300")

    assert actual.splitlines() == [
        "2",
        "1",
        "202605241300",
        "1,0.00,0.00,0.00,0.00",
        "2,1892.00,1898.00,1910.00,1885.00",
        "3,0.00,0.00,0.00,0.00",
        "4,0.00,0.00,0.00,0.00",
    ]


def test_build_candidate_id_datetime_text_returns_compact_digits() -> None:
    """H1確定足時刻からスペースなしの候補IDを作る。"""
    actual = build_candidate_id("2026.05.24 13:00")

    assert actual == "202605241300"
