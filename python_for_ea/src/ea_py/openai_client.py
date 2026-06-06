"""OpenAI Responses API呼び出しの薄いラッパー。"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
import json
import logging
from typing import Any

from openai import OpenAI
from openai.types.responses import (
    EasyInputMessageParam,
    ResponseInputImageParam,
    ResponseInputMessageContentListParam,
    ResponseInputParam,
    ResponseInputTextParam,
)

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class ResponsesApiDiagnostics:
    """Responses APIの空出力診断に必要な最小メタデータ。"""

    model: str
    status: str
    incomplete_details: str
    error: str
    usage: str

    def is_completed(self) -> bool:
        """ライブ判定に使える完了レスポンスかどうかを返す。"""
        return self.status == "completed" and not self.incomplete_details and not self.error

    def to_log_text(self) -> str:
        """デバッグログへそのまま書ける1行診断文字列を返す。"""
        parts = [
            f"model={self.model or '-'}",
            f"status={self.status or '-'}",
            f"incomplete_details={self.incomplete_details or '-'}",
            f"error={self.error or '-'}",
            f"usage={self.usage or '-'}",
        ]
        return "; ".join(parts)


@dataclass(frozen=True)
class ResponsesApiResult:
    """Responses APIの本文と診断情報。"""

    text: str
    diagnostics: ResponsesApiDiagnostics


def create_openai_client(api_key: str) -> OpenAI:
    """APIキーからOpenAIクライアントを生成する。"""
    return OpenAI(api_key=api_key)


def _format_response_field(value: object) -> str:
    """SDKオブジェクトを短いJSON文字列へ変換する。"""
    if value is None:
        return ""

    try:
        if hasattr(value, "model_dump"):
            dumped = value.model_dump(mode="json", exclude_none=True)  # type: ignore[attr-defined]
            return json.dumps(dumped, ensure_ascii=False, separators=(",", ":"))
        return str(value)
    except Exception:
        return repr(value)


def _extract_response_diagnostics(response: object) -> ResponsesApiDiagnostics:
    """Responses APIレスポンスから安全な診断情報を抽出する。"""
    return ResponsesApiDiagnostics(
        model=str(getattr(response, "model", "") or ""),
        status=str(getattr(response, "status", "") or ""),
        incomplete_details=_format_response_field(getattr(response, "incomplete_details", None)),
        error=_format_response_field(getattr(response, "error", None)),
        usage=_format_response_field(getattr(response, "usage", None)),
    )


def call_responses_api(
    *,
    client: OpenAI,
    model: str,
    reasoning_effort: str,
    system_content: str,
    user_text: str,
    image_data_urls: Sequence[str],
    max_output_tokens: int,
    response_text_format: Mapping[str, Any] | None = None,
    text_verbosity: str | None = None,
) -> ResponsesApiResult:
    """Responses APIへテキストとチャート画像を送り、出力テキストを返す。

    `system_content` は判定器としての役割と出力制約を指定する。
    `user_text` はH4/H1の具体的な分析依頼、数値要約、出力フォーマットを含む。
    `image_data_urls` にはPNGをdata URL化したチャート画像を渡す。空文字は無視する。

    `response_text_format` が指定された場合は Responses API の `text.format` へ渡し、
    JSON Schemaなどの構造化出力をAPI側でも強制する。
    `text_verbosity` はGPT-5.5の最終出力長を制御し、reasoning品質とは独立して扱う。

    戻り値は `response.output_text` をstripした文字列とAPI診断情報。
    API例外や空/不正な出力の安全側処理は、この薄いラッパーではなく
    呼び出し元のパイプラインとパース関数が担当する。
    """
    text_part: ResponseInputTextParam = {"type": "input_text", "text": user_text}
    content_parts: ResponseInputMessageContentListParam = [text_part]
    for image_data_url in image_data_urls:
        if image_data_url:
            image_part: ResponseInputImageParam = {
                "type": "input_image",
                "image_url": image_data_url,
                "detail": "auto",
            }
            content_parts.append(image_part)

    system_message: EasyInputMessageParam = {"role": "system", "content": system_content}
    user_message: EasyInputMessageParam = {"role": "user", "content": content_parts}
    input_messages: ResponseInputParam = [system_message, user_message]

    create_params: dict[str, Any] = {
        "model": model,
        "input": input_messages,
        "reasoning": {"effort": reasoning_effort},
        "max_output_tokens": max_output_tokens,
    }
    text_config: dict[str, Any] = {}
    if response_text_format is not None:
        text_config["format"] = dict(response_text_format)
    if text_verbosity is not None:
        text_config["verbosity"] = text_verbosity
    if text_config:
        create_params["text"] = text_config

    response = client.responses.create(**create_params)
    diagnostics = _extract_response_diagnostics(response)
    text = (response.output_text or "").strip()
    if not text:
        logger.warning("OpenAI response output_text is empty: %s", diagnostics.to_log_text())

    return ResponsesApiResult(text=text, diagnostics=diagnostics)
