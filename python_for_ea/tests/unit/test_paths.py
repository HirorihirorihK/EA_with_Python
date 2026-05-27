"""MT5 path discovery tests."""

from __future__ import annotations

from pathlib import Path

import pytest

from ea_py.paths import (
    ENV_MT5_DATA_PATH,
    ENV_MT5_FILES_DIR,
    Mt5PathSettings,
    discover_mql5_dir,
    files_dir_from_data_path,
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
