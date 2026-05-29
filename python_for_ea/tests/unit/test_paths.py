"""MT5 path discovery tests."""

from __future__ import annotations

from pathlib import Path

import pytest

from ea_py.paths import (
    ENV_MT5_EA_FILE_PREFIX,
    ENV_MT5_DATA_PATH,
    ENV_MT5_FILES_DIR,
    ENV_MT5_PRICE_DIGITS,
    Mt5PathSettings,
    build_entry_paths,
    build_trend_paths,
    discover_mql5_dir,
    files_dir_from_data_path,
    mt5_price_digits,
    prefixed_file_name,
    sanitize_file_prefix,
    sanitize_price_digits,
    terminal_files_dir,
)


def test_discover_mql5_dir_from_nested_python_project(tmp_path: Path) -> None:
    """MQL5/python_for_ea 配置から親の MQL5 ディレクトリを見つける。"""
    nested = tmp_path / "Terminal" / "ABC" / "MQL5" / "python_for_ea" / "src" / "ea_py" / "paths.py"
    nested.parent.mkdir(parents=True)
    nested.write_text("", encoding="utf-8")

    actual = discover_mql5_dir(nested)

    assert actual == tmp_path / "Terminal" / "ABC" / "MQL5"


def test_terminal_files_dir_accepts_explicit_files_dir(tmp_path: Path) -> None:
    """Tests and special deployments can pass the Files directory directly."""
    expected = tmp_path / "Files"

    actual = terminal_files_dir(Mt5PathSettings(files_dir=expected))

    assert actual == expected


def test_terminal_files_dir_prefers_environment_files_dir(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """MT5_FILES_DIR overrides automatic discovery."""
    expected = tmp_path / "CustomFiles"
    monkeypatch.setenv(ENV_MT5_FILES_DIR, str(expected))

    actual = terminal_files_dir()

    assert actual == expected


def test_terminal_files_dir_accepts_legacy_user_and_terminal_settings() -> None:
    """Existing tests and tools can still pass user and terminal settings."""
    settings = Mt5PathSettings(user_name="alice", terminal_id="TERMINAL123")

    actual = terminal_files_dir(settings)

    assert actual == Path(
        "C:/Users/alice/AppData/Roaming/MetaQuotes/Terminal/TERMINAL123/MQL5/Files"
    )


def test_files_dir_from_data_path_accepts_terminal_data_path(tmp_path: Path) -> None:
    """Terminal data paths are converted to MQL5/Files."""
    data_path = tmp_path / "Terminal" / "ABC"

    actual = files_dir_from_data_path(data_path)

    assert actual == data_path / "MQL5" / "Files"


def test_files_dir_from_data_path_accepts_mql5_path(tmp_path: Path) -> None:
    """MQL5 paths are converted to their adjacent Files directory."""
    mql5_path = tmp_path / "Terminal" / "ABC" / "MQL5"

    actual = files_dir_from_data_path(mql5_path)

    assert actual == mql5_path / "Files"


def test_terminal_files_dir_accepts_environment_data_path(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """MT5_DATA_PATH can point at the terminal data folder."""
    data_path = tmp_path / "Terminal" / "ABC"
    monkeypatch.setenv(ENV_MT5_DATA_PATH, str(data_path))

    actual = terminal_files_dir()

    assert actual == data_path / "MQL5" / "Files"


def test_prefixed_file_name_uses_legacy_name_when_prefix_is_empty(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """接頭辞未指定時は既存のMT5連携ファイル名を維持する。"""
    monkeypatch.delenv(ENV_MT5_EA_FILE_PREFIX, raising=False)

    assert prefixed_file_name("target_prices.txt") == "target_prices.txt"


def test_sanitize_file_prefix_replaces_unsafe_characters() -> None:
    """Symbols containing dots or suffixes are safe for filesystem names."""
    assert sanitize_file_prefix("HIT_XAUUSD.pro_10001") == "HIT_XAUUSD_pro_10001"


def test_build_paths_apply_file_prefix_from_settings(tmp_path: Path) -> None:
    """同一Files配下でEAごとの連携ファイル名を分離できる。"""
    settings = Mt5PathSettings(files_dir=tmp_path, file_prefix="HIT_GOLD_10001")

    trend_paths = build_trend_paths(settings)
    entry_paths = build_entry_paths(settings)

    assert trend_paths.input_csv == tmp_path / "HIT_GOLD_10001_ohlc_H4.csv"
    assert trend_paths.trend_state == tmp_path / "HIT_GOLD_10001_trend_state.txt"
    assert entry_paths.input_csv == tmp_path / "HIT_GOLD_10001_ohlc_H1.csv"
    assert entry_paths.output_prices == tmp_path / "HIT_GOLD_10001_target_prices.txt"
    assert entry_paths.output_zones == tmp_path / "HIT_GOLD_10001_target_zones.txt"


def test_build_paths_apply_file_prefix_from_environment(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """batから渡されたMT5_EA_FILE_PREFIXでPython側ファイル名を合わせる。"""
    monkeypatch.setenv(ENV_MT5_FILES_DIR, str(tmp_path))
    monkeypatch.setenv(ENV_MT5_EA_FILE_PREFIX, "HIT_GOLD_10001")

    actual = build_entry_paths()

    assert actual.done_entry == tmp_path / "HIT_GOLD_10001_process_done_entry.txt"


def test_sanitize_price_digits_accepts_mt5_symbol_digits() -> None:
    """MT5のSYMBOL_DIGITSは安全な範囲だけ受け入れる。"""
    assert sanitize_price_digits("3") == 3
    assert sanitize_price_digits(10) == 10
    assert sanitize_price_digits("-1") is None
    assert sanitize_price_digits("abc") is None


def test_mt5_price_digits_reads_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    """EA/batから渡された価格桁数をPython側で参照できる。"""
    monkeypatch.setenv(ENV_MT5_PRICE_DIGITS, "3")

    assert mt5_price_digits() == 3


def test_mt5_price_digits_accepts_settings() -> None:
    """テストや手動実行では設定オブジェクトから価格桁数を渡せる。"""
    settings = Mt5PathSettings(price_digits=2)

    assert mt5_price_digits(settings) == 2
