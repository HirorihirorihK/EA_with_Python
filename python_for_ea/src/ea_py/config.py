"""環境変数から実行時設定を読み込む。"""

from __future__ import annotations

from dataclasses import dataclass
import os

from ea_py.constants import (
    DEBUG_PRINT,
    DEFAULT_GPT_MODEL,
    DEFAULT_REASONING_EFFORT,
    DEFAULT_TEXT_VERBOSITY,
    VALID_REASONING_EFFORTS,
    VALID_TEXT_VERBOSITIES,
)


@dataclass(frozen=True)
class RuntimeConfig:
    """OpenAI呼び出しに必要な実行時設定。"""

    api_key: str
    model: str
    reasoning_effort: str
    text_verbosity: str
    debug_print: bool


def load_runtime_config(
    *,
    model: str | None = None,
    reasoning_effort: str | None = None,
    text_verbosity: str | None = None,
    debug_print: bool = DEBUG_PRINT,
) -> RuntimeConfig:
    """OpenAI呼び出しに必要な実行時設定を読み込む。

    APIキーは秘密情報のためコードや設定ファイルへ直書きせず、
    `OPENAI_API_KEY` 環境変数からのみ取得する。
    未設定の場合は `RuntimeError` を送出し、上位パイプラインで停止値を出力する。

    `model` / `reasoning_effort` / `text_verbosity` / `debug_print` は呼び出し側から上書き可能だが、
    通常は `constants.py` のデフォルト値を使う。
    `OPENAI_MODEL` / `OPENAI_REASONING_EFFORT` / `OPENAI_TEXT_VERBOSITY` が設定されている場合は、
    引数未指定時の実行時上書きとして扱う。
    """
    api_key = os.getenv("OPENAI_API_KEY")
    if api_key is None:
        raise RuntimeError("OPENAI_API_KEY が環境変数に設定されていません。")

    selected_model = model or os.getenv("OPENAI_MODEL") or DEFAULT_GPT_MODEL
    selected_reasoning_effort = reasoning_effort or os.getenv("OPENAI_REASONING_EFFORT") or DEFAULT_REASONING_EFFORT
    selected_text_verbosity = text_verbosity or os.getenv("OPENAI_TEXT_VERBOSITY") or DEFAULT_TEXT_VERBOSITY
    if selected_reasoning_effort not in VALID_REASONING_EFFORTS:
        allowed = ", ".join(sorted(VALID_REASONING_EFFORTS))
        raise RuntimeError(
            f"OPENAI_REASONING_EFFORT が不正です: {selected_reasoning_effort!r}. "
            f"allowed={allowed}"
        )
    if selected_text_verbosity not in VALID_TEXT_VERBOSITIES:
        allowed = ", ".join(sorted(VALID_TEXT_VERBOSITIES))
        raise RuntimeError(
            f"OPENAI_TEXT_VERBOSITY が不正です: {selected_text_verbosity!r}. "
            f"allowed={allowed}"
        )

    return RuntimeConfig(
        api_key=api_key,
        model=selected_model,
        reasoning_effort=selected_reasoning_effort,
        text_verbosity=selected_text_verbosity,
        debug_print=debug_print,
    )
