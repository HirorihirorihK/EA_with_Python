"""MT5連携ファイルのパスを組み立てる。"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


DEFAULT_USER_NAME = "new"
DEFAULT_TERMINAL_ID = "5BDB0B60344C088C2FA5CA35699BAAFD"


@dataclass(frozen=True)
class Mt5PathSettings:
    """MT5データフォルダを特定するための設定。"""

    user_name: str = DEFAULT_USER_NAME
    terminal_id: str = DEFAULT_TERMINAL_ID


@dataclass(frozen=True)
class TrendPaths:
    """H4トレンド判定パイプラインが使用するファイル群。"""

    input_csv: Path
    trend_state: Path
    done_trend: Path
    tmp_chart: Path
    debug_reason: Path


@dataclass(frozen=True)
class EntryPaths:
    """H1エントリー候補生成パイプラインが使用するファイル群。"""

    input_csv: Path
    output_prices: Path
    output_zones: Path
    trend_state: Path
    done_entry: Path
    tmp_short_chart: Path
    tmp_long_chart: Path
    debug_reason: Path


def terminal_files_dir(settings: Mt5PathSettings | None = None) -> Path:
    """MT5のMQL5/Filesディレクトリを返す。"""
    mt5_settings = settings or Mt5PathSettings()
    return (
        Path("C:/Users")
        / mt5_settings.user_name
        / "AppData"
        / "Roaming"
        / "MetaQuotes"
        / "Terminal"
        / mt5_settings.terminal_id
        / "MQL5"
        / "Files"
    )


def build_trend_paths(settings: Mt5PathSettings | None = None) -> TrendPaths:
    """H4トレンド判定用の入出力パスをまとめて返す。"""
    base_dir = terminal_files_dir(settings)
    return TrendPaths(
        input_csv=base_dir / "ohlc_H4.csv",
        trend_state=base_dir / "trend_state.txt",
        done_trend=base_dir / "process_done_trend.txt",
        tmp_chart=base_dir / "tmp_chart_trend.png",
        debug_reason=base_dir / "debug_trend.txt",
    )


def build_entry_paths(settings: Mt5PathSettings | None = None) -> EntryPaths:
    """H1エントリー候補生成用の入出力パスをまとめて返す。"""
    base_dir = terminal_files_dir(settings)
    return EntryPaths(
        input_csv=base_dir / "ohlc_H1.csv",
        output_prices=base_dir / "target_prices.txt",
        output_zones=base_dir / "target_zones.txt",
        trend_state=base_dir / "trend_state.txt",
        done_entry=base_dir / "process_done_entry.txt",
        tmp_short_chart=base_dir / "tmp_chart_short.png",
        tmp_long_chart=base_dir / "tmp_chart_long.png",
        debug_reason=base_dir / "debug_entry.txt",
    )
