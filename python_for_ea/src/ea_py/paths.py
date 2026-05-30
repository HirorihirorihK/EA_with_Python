"""MT5連携ファイルのパスを組み立てる。"""

from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path


DEFAULT_USER_NAME = "new"
DEFAULT_TERMINAL_ID = "5BDB0B60344C088C2FA5CA35699BAAFD"
ENV_MT5_FILES_DIR = "MT5_FILES_DIR"
ENV_MT5_DATA_PATH = "MT5_DATA_PATH"
ENV_MT5_EA_FILE_PREFIX = "MT5_EA_FILE_PREFIX"
ENV_MT5_PRICE_DIGITS = "MT5_PRICE_DIGITS"


@dataclass(frozen=True)
class Mt5PathSettings:
    """MT5データフォルダを特定するための設定。"""

    files_dir: Path | None = None
    data_path: Path | None = None
    user_name: str | None = None
    terminal_id: str | None = None
    file_prefix: str | None = None
    price_digits: int | None = None


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


def discover_mql5_dir(start_path: Path | None = None) -> Path | None:
    """このPythonプロジェクトの配置からMQL5ルートを探す。"""
    path = (start_path or Path(__file__)).resolve()
    candidates = [path, *path.parents]
    for candidate in candidates:
        if candidate.name.lower() == "mql5":
            return candidate

    return None


def files_dir_from_data_path(data_path: Path) -> Path:
    """MT5データフォルダまたはMQL5フォルダからFilesパスを作る。"""
    resolved = data_path.resolve()
    if resolved.name.lower() == "mql5":
        return resolved / "Files"

    return resolved / "MQL5" / "Files"


def sanitize_file_prefix(prefix: str) -> str:
    """EAから渡されたファイル接頭辞を安全なファイル名トークンへ丸める。"""
    stripped = prefix.strip()
    if not stripped:
        return ""

    safe_chars = []
    for char in stripped:
        if (char.isascii() and char.isalnum()) or char in {"_", "-"}:
            safe_chars.append(char)
        else:
            safe_chars.append("_")

    return "".join(safe_chars)


def mt5_file_prefix(settings: Mt5PathSettings | None = None) -> str:
    """MT5連携ファイル名へ付けるEA固有接頭辞を返す。"""
    if settings and settings.file_prefix is not None:
        return sanitize_file_prefix(settings.file_prefix)

    return sanitize_file_prefix(os.getenv(ENV_MT5_EA_FILE_PREFIX, ""))


def prefixed_file_name(base_name: str, settings: Mt5PathSettings | None = None) -> str:
    """接頭辞がある場合だけ `prefix_base_name` 形式にする。"""
    prefix = mt5_file_prefix(settings)
    if not prefix:
        return base_name

    return f"{prefix}_{base_name}"


def sanitize_price_digits(value: int | str | None) -> int | None:
    """MT5から渡された価格桁数を安全な範囲へ丸める。"""
    if value is None:
        return None

    try:
        digits = int(value)
    except (TypeError, ValueError):
        return None

    if 0 <= digits <= 10:
        return digits

    return None


def mt5_price_digits(settings: Mt5PathSettings | None = None) -> int | None:
    """MT5連携価格の小数桁数を返す。未指定や不正値はNone。"""
    if settings and settings.price_digits is not None:
        return sanitize_price_digits(settings.price_digits)

    return sanitize_price_digits(os.getenv(ENV_MT5_PRICE_DIGITS))


def terminal_files_dir(settings: Mt5PathSettings | None = None) -> Path:
    """MT5のMQL5/Filesディレクトリを返す。

    既定では `MQL5/python_for_ea` 配置から親の `MQL5/Files` を発見する。
    テストや特殊運用では `MT5_FILES_DIR` または `MT5_DATA_PATH` で上書きできる。
    """
    if settings and settings.files_dir is not None:
        return settings.files_dir

    env_files_dir = os.getenv(ENV_MT5_FILES_DIR)
    if env_files_dir:
        return Path(env_files_dir)

    if settings and settings.data_path is not None:
        return files_dir_from_data_path(settings.data_path)

    env_data_path = os.getenv(ENV_MT5_DATA_PATH)
    if env_data_path:
        return files_dir_from_data_path(Path(env_data_path))

    mt5_settings = settings or Mt5PathSettings()
    if mt5_settings.user_name is not None or mt5_settings.terminal_id is not None:
        user_name = mt5_settings.user_name or DEFAULT_USER_NAME
        terminal_id = mt5_settings.terminal_id or DEFAULT_TERMINAL_ID
        return (
            Path("C:/Users")
            / user_name
            / "AppData"
            / "Roaming"
            / "MetaQuotes"
            / "Terminal"
            / terminal_id
            / "MQL5"
            / "Files"
        )

    discovered_mql5_dir = discover_mql5_dir()
    if discovered_mql5_dir is not None:
        return discovered_mql5_dir / "Files"

    user_name = mt5_settings.user_name or DEFAULT_USER_NAME
    terminal_id = mt5_settings.terminal_id or DEFAULT_TERMINAL_ID
    return (
        Path("C:/Users")
        / user_name
        / "AppData"
        / "Roaming"
        / "MetaQuotes"
        / "Terminal"
        / terminal_id
        / "MQL5"
        / "Files"
    )


def build_trend_paths(settings: Mt5PathSettings | None = None) -> TrendPaths:
    """H4トレンド判定用の入出力パスをまとめて返す。"""
    base_dir = terminal_files_dir(settings)
    return TrendPaths(
        input_csv=base_dir / prefixed_file_name("ohlc_H4.csv", settings),
        trend_state=base_dir / prefixed_file_name("trend_state.txt", settings),
        done_trend=base_dir / prefixed_file_name("process_done_trend.txt", settings),
        tmp_chart=base_dir / prefixed_file_name("tmp_chart_trend.png", settings),
        debug_reason=base_dir / prefixed_file_name("debug_trend.txt", settings),
    )


def build_entry_paths(settings: Mt5PathSettings | None = None) -> EntryPaths:
    """H1エントリー候補生成用の入出力パスをまとめて返す。"""
    base_dir = terminal_files_dir(settings)
    return EntryPaths(
        input_csv=base_dir / prefixed_file_name("ohlc_H1.csv", settings),
        output_prices=base_dir / prefixed_file_name("target_prices.txt", settings),
        output_zones=base_dir / prefixed_file_name("target_zones.txt", settings),
        trend_state=base_dir / prefixed_file_name("trend_state.txt", settings),
        done_entry=base_dir / prefixed_file_name("process_done_entry.txt", settings),
        tmp_short_chart=base_dir / prefixed_file_name("tmp_chart_short.png", settings),
        tmp_long_chart=base_dir / prefixed_file_name("tmp_chart_long.png", settings),
        debug_reason=base_dir / prefixed_file_name("debug_entry.txt", settings),
    )
