"""OHLC CSV reader tests."""

from __future__ import annotations

from pathlib import Path

import pytest

from ea_py.io.ohlc_csv import read_ohlc_csv


def write_csv(path: Path, body: str) -> None:
    """Write a small MT5-style OHLC CSV for tests."""
    path.write_text("Time,Open,High,Low,Close\n" + body, encoding="utf-8")


def test_read_ohlc_csv_rejects_non_finite_prices(tmp_path: Path) -> None:
    """NaN/inf values are rejected before market calculations."""
    csv_path = tmp_path / "ohlc.csv"
    write_csv(csv_path, "2026.05.24 13:00,1900.0,nan,1890.0,1895.0\n")

    with pytest.raises(ValueError, match="non-finite"):
        read_ohlc_csv(csv_path)


def test_read_ohlc_csv_rejects_inconsistent_high_low(tmp_path: Path) -> None:
    """High/Low must contain Open and Close."""
    csv_path = tmp_path / "ohlc.csv"
    write_csv(csv_path, "2026.05.24 13:00,1900.0,1899.0,1890.0,1895.0\n")

    with pytest.raises(ValueError, match="High below Open/Close"):
        read_ohlc_csv(csv_path)


def test_read_ohlc_csv_accepts_valid_mt5_rows(tmp_path: Path) -> None:
    """Valid MT5 rows are converted to the internal DateTime schema."""
    csv_path = tmp_path / "ohlc.csv"
    write_csv(csv_path, "2026.05.24 13:00,1900.0,1902.0,1890.0,1895.0\n")

    actual = read_ohlc_csv(csv_path)

    assert actual == [
        {
            "DateTime": "2026.05.24 13:00",
            "Open": 1900.0,
            "High": 1902.0,
            "Low": 1890.0,
            "Close": 1895.0,
        }
    ]
