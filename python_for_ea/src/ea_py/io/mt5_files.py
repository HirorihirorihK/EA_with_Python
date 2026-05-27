"""MT5連携ファイルの読み書き補助。"""

from __future__ import annotations

from pathlib import Path
from typing import Collection


def write_text_atomic(path: Path, text: str, encoding: str) -> None:
    """一時ファイルへ書いてから対象ファイルへ置換する。"""
    tmp_path = path.with_name(f"{path.name}.tmp")
    tmp_path.write_text(text, encoding=encoding, newline="")
    tmp_path.replace(path)


def write_result_then_done(
    *,
    result_path: Path,
    result_text: str,
    result_encoding: str,
    done_path: Path,
) -> None:
    """MT5へ結果ファイルの完成を通知する順序で書き込む。

    手順は必ず以下の順序にする。
    1. 古いdoneファイルを削除する。
    2. 結果ファイルを一時ファイルへ書き、atomic replaceで本番名へ置換する。
    3. 結果ファイルが完成した後にdoneファイルを作成する。

    MT5 EAはdoneファイルを完了シグナルとして扱うため、古いdoneが残った状態で
    新しい結果を書き始めないことが重要。結果書き込みに失敗した場合はdoneを作らず、
    EA側が未完成の結果を読むリスクを避ける。
    """
    done_path.unlink(missing_ok=True)
    write_text_atomic(result_path, result_text, result_encoding)
    write_text_atomic(done_path, "", "utf-8")


def write_results_then_done(
    *,
    result_files: Collection[tuple[Path, str, str]],
    done_path: Path,
) -> None:
    """複数の結果ファイルを書き終えてからdoneファイルを作成する。"""
    done_path.unlink(missing_ok=True)
    for result_path, result_text, result_encoding in result_files:
        write_text_atomic(result_path, result_text, result_encoding)
    write_text_atomic(done_path, "", "utf-8")


def read_int_file(
    path: Path,
    *,
    encoding: str,
    allowed_values: Collection[int],
    default: int,
) -> int:
    """整数ファイルを読み、許可値以外や失敗時はdefaultを返す。"""
    try:
        if not path.exists():
            return default

        value = int(path.read_text(encoding=encoding).strip())
        return value if value in allowed_values else default
    except Exception:
        return default
