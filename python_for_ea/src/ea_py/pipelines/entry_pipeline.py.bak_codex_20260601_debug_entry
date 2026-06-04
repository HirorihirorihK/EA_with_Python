"""H1 OHLCとH4 market_stateからtarget_pricesを生成するパイプライン。"""

from __future__ import annotations

import logging
from collections.abc import Sequence

from ea_py.charting.candlestick import ohlc_to_candlestick_png_file, png_file_to_data_url
from ea_py.config import load_runtime_config
from ea_py.constants import (
    CANDLE_LONG,
    CANDLE_SHORT,
    DEBUG_PRINT,
    ENTRY_MAX_DISTANCE_LIMIT_EATR_MULTIPLIER,
    ENTRY_MAX_DISTANCE_MIN_PRICE,
    ENTRY_MAX_DISTANCE_STOP_EATR_MULTIPLIER,
    ENTRY_MAX_OUTPUT_TOKENS,
    ENTRY_TIMEFRAME,
    IMBALANCE_AVG_BODY_PERIOD,
    IMBALANCE_MIN_AVG_BODY_SIZE,
    IMBALANCE_SENSITIVITY,
    INSTRUMENT,
    MARKET_STATE_LABELS,
    MIN_ENTRY_REWARD_RISK_RATIO,
    MT_ENCODING,
    TECHNICAL_ERROR_STOP,
    USE_IMBALANCE_FILTER,
)
from ea_py.io.debug_logs import append_debug_entry
from ea_py.io.mt5_files import read_int_file, write_results_then_done
from ea_py.io.ohlc_csv import read_ohlc_csv
from ea_py.market.volatility import summarize_ohlc
from ea_py.market.target_prices import (
    stop_numeric_list,
    strategies_by_trend,
)
from ea_py.market.target_zones import (
    build_candidate_id,
    format_target_zones,
    parse_json_to_entry_zones,
    sanitize_entry_zones,
    stop_entry_zones,
    zones_to_numeric_list,
)
from ea_py.market.imbalance import (
    adjust_strategies_for_imbalance,
    detect_imbalance_signal,
    format_imbalance_summary,
)
from ea_py.openai_client import call_responses_api, create_openai_client
from ea_py.paths import build_entry_paths
from ea_py.prompts.entry_prompt import (
    build_imbalance_guidance,
    build_caution_block,
    build_common_rules_block,
    build_entry_response_text_format,
    build_header,
    build_market_state_guidance,
    build_numeric_summary,
    build_system_content_block,
    build_system_content_block_debug,
)
from ea_py.types import NumericList

logger = logging.getLogger(__name__)

TREND_STOP_STRATEGIES = frozenset({1, 3})


def write_entry_output(numeric_list: NumericList, zone_text: str | None = None) -> None:
    """target_prices.txtとtarget_zones.txtを書き、完了後にprocess_done_entry.txtを作る。"""
    paths = build_entry_paths()
    content = "".join(f"{number}\n" for number in numeric_list)
    zone_content = zone_text if zone_text is not None else format_target_zones(stop_entry_zones(), "0")
    write_results_then_done(
        result_files=[
            (paths.output_prices, content, MT_ENCODING),
            (paths.output_zones, zone_content, MT_ENCODING),
        ],
        done_path=paths.done_entry,
    )


def build_entry_distance_limits(h1_eatr: float, selected_strategies: Sequence[int]) -> dict[int, float]:
    """H1 EATRから戦略別のエントリー許容距離を作る。"""
    limits: dict[int, float] = {}
    for strategy in selected_strategies:
        multiplier = (
            ENTRY_MAX_DISTANCE_STOP_EATR_MULTIPLIER
            if strategy in TREND_STOP_STRATEGIES
            else ENTRY_MAX_DISTANCE_LIMIT_EATR_MULTIPLIER
        )
        limits[strategy] = max(h1_eatr * multiplier, ENTRY_MAX_DISTANCE_MIN_PRICE)
    return limits


def run_pipeline() -> None:
    """H1 OHLCとH4 market_stateからMT5向けtarget_pricesを生成する。

    実行契約:
    - `trend_state.txt` のH4 `market_state` を読み、許可戦略だけを選ぶ。
    - `ohlc_H1.csv` から短期・中期チャート画像と数値要約を作る。
    - OpenAIには選択済み戦略の候補価格だけを依頼し、返却行を13値形式へ展開する。
    - GPT出力は `sanitize_numeric_list` で検証し、`target_prices.txt` を書いた後に
      `process_done_entry.txt` を作成する。

    安全側フォールバック:
    H4が技術エラー停止値、CSV読込失敗、H1データ不足、画像生成失敗、OpenAI設定/API失敗、
    GPT出力不正、または全候補が価格条件違反の場合は13値すべてを停止値にする。
    Pythonは候補価格を作るだけで、注文送信やポジション操作は行わない。
    """
    paths = build_entry_paths()
    trend_state = read_int_file(
        paths.trend_state,
        encoding=MT_ENCODING,
        allowed_values=MARKET_STATE_LABELS.keys(),
        default=TECHNICAL_ERROR_STOP,
    )
    selected_strategies = strategies_by_trend(trend_state)

    if trend_state == TECHNICAL_ERROR_STOP or not selected_strategies:
        logger.info(
            "market_state=%s (%s). New entries stopped.",
            trend_state,
            MARKET_STATE_LABELS.get(trend_state, "UNKNOWN"),
        )
        write_entry_output(stop_numeric_list())
        return

    try:
        ohlc_all = read_ohlc_csv(paths.input_csv)
    except Exception:
        logger.exception("CSV 読み込みエラー")
        write_entry_output(stop_numeric_list())
        return

    if len(ohlc_all) < CANDLE_LONG:
        logger.error("データ本数不足: len(ohlc)=%s (need >= %s)", len(ohlc_all), CANDLE_LONG)
        write_entry_output(stop_numeric_list())
        return

    ohlc_short = ohlc_all[-CANDLE_SHORT:]
    ohlc_long = ohlc_all[-CANDLE_LONG:]
    current_price = float(ohlc_short[-1]["Close"])
    candidate_id = build_candidate_id(str(ohlc_short[-1].get("DateTime", "")))
    imbalance_analysis = detect_imbalance_signal(
        ohlc_all,
        avg_body_period=IMBALANCE_AVG_BODY_PERIOD,
        sensitivity=IMBALANCE_SENSITIVITY,
        min_avg_body_size=IMBALANCE_MIN_AVG_BODY_SIZE,
    )
    imbalance_summary = format_imbalance_summary(imbalance_analysis)
    selected_strategies = adjust_strategies_for_imbalance(
        selected_strategies,
        trend_state=trend_state,
        analysis=imbalance_analysis,
        use_filter=USE_IMBALANCE_FILTER,
    )

    if not selected_strategies:
        logger.info(
            "H1 imbalance conflicts with market_state=%s (%s). New entries stopped. %s",
            trend_state,
            MARKET_STATE_LABELS.get(trend_state, "UNKNOWN"),
            imbalance_summary,
        )
        write_entry_output(stop_numeric_list())
        return

    try:
        ohlc_to_candlestick_png_file(
            ohlc_data=ohlc_short,
            save_path=paths.tmp_short_chart,
            instrument=INSTRUMENT,
            timeframe=ENTRY_TIMEFRAME,
            dark=True,
        )
        ohlc_to_candlestick_png_file(
            ohlc_data=ohlc_long,
            save_path=paths.tmp_long_chart,
            instrument=INSTRUMENT,
            timeframe=ENTRY_TIMEFRAME,
            dark=True,
        )
        images_data_urls = [
            png_file_to_data_url(paths.tmp_short_chart),
            png_file_to_data_url(paths.tmp_long_chart),
        ]
    except Exception:
        logger.exception("画像生成エラー")
        write_entry_output(stop_numeric_list())
        return

    numeric_summary = build_numeric_summary(
        current_price=current_price,
        ohlc_short=ohlc_short,
        ohlc_long=ohlc_long,
    )
    short_summary = summarize_ohlc(ohlc_short)
    h1_eatr = float(short_summary.get("eatr", 0.0))
    max_entry_distance = build_entry_distance_limits(h1_eatr, selected_strategies)
    post_filter_summary = (
        "entry_distance_guard="
        f"max_distance_by_strategy={max_entry_distance}, "
        f"h1_eatr={h1_eatr:.2f}, "
        f"stop_multiplier={ENTRY_MAX_DISTANCE_STOP_EATR_MULTIPLIER:.2f}, "
        f"limit_multiplier={ENTRY_MAX_DISTANCE_LIMIT_EATR_MULTIPLIER:.2f}, "
        f"floor={ENTRY_MAX_DISTANCE_MIN_PRICE:.2f}, "
        f"min_reward_risk={MIN_ENTRY_REWARD_RISK_RATIO:.2f}"
    )
    header = build_header(
        current_price=current_price,
        numeric_summary=numeric_summary,
        trend_state=trend_state,
    )
    market_state_guidance = build_market_state_guidance(trend_state)
    imbalance_guidance = build_imbalance_guidance(imbalance_analysis)
    caution = build_caution_block()

    try:
        config = load_runtime_config(debug_print=DEBUG_PRINT)
    except RuntimeError:
        logger.exception("OpenAI 設定エラー")
        write_entry_output(stop_numeric_list())
        return

    system_content = build_system_content_block_debug() if config.debug_print else build_system_content_block()
    common_rules = build_common_rules_block(selected_strategies, max_entry_distance)
    response_text_format = build_entry_response_text_format(selected_strategies)
    max_tokens = ENTRY_MAX_OUTPUT_TOKENS

    user_text = "\n\n".join([header, market_state_guidance, imbalance_guidance, common_rules, caution]).strip()

    api_diagnostics = ""
    try:
        client = create_openai_client(config.api_key)
        gpt_result = call_responses_api(
            client=client,
            model=config.model,
            reasoning_effort=config.reasoning_effort,
            system_content=system_content,
            user_text=user_text,
            image_data_urls=images_data_urls,
            max_output_tokens=max_tokens,
            response_text_format=response_text_format,
        )
        gpt_reply = gpt_result.text
        api_diagnostics = gpt_result.diagnostics.to_log_text()
        if not gpt_result.diagnostics.is_completed():
            logger.error("OpenAI response incomplete or failed: %s", api_diagnostics)
            write_entry_output(stop_numeric_list())
            return
    except Exception:
        logger.exception("OpenAI APIエラー")
        write_entry_output(stop_numeric_list())
        return

    if config.debug_print:
        logger.info(
            "---- TREND ---- %s selected=%s\n---- GPT REPLY START ----\n%s\n---- GPT REPLY END ----",
            trend_state,
            selected_strategies,
            gpt_reply,
        )

    entry_zones = parse_json_to_entry_zones(gpt_reply)
    entry_zones = sanitize_entry_zones(
        entry_zones,
        selected_strategies,
        current_price,
        max_entry_distance=max_entry_distance,
        min_reward_risk_ratio=MIN_ENTRY_REWARD_RISK_RATIO,
    )
    numeric_list = zones_to_numeric_list(entry_zones)
    zone_text = format_target_zones(entry_zones, candidate_id)

    if config.debug_print:
        try:
            append_debug_entry(
                path=paths.debug_reason,
                model=config.model,
                reasoning_effort=config.reasoning_effort,
                max_output_tokens=max_tokens,
                api_diagnostics=api_diagnostics,
                timeframe=ENTRY_TIMEFRAME,
                current_price=current_price,
                trend_state=trend_state,
                selected_strategies=selected_strategies,
                imbalance_summary=imbalance_summary,
                numeric_summary=numeric_summary,
                numeric_lines=gpt_reply,
                post_filter_summary=post_filter_summary,
                sanitized_numeric_list=numeric_list,
                reason_text=f"STRUCTURED_JSON\n{gpt_reply}\n\nTARGET_ZONES\n{zone_text}".strip(),
            )
        except Exception:
            logger.exception("debug_entry.txt write error")

    write_entry_output(numeric_list, zone_text)


def main() -> None:
    """ログ設定を行ってH1エントリー候補生成パイプラインを起動する。"""
    logging.basicConfig(level=logging.INFO, format="%(levelname)s:%(name)s:%(message)s")
    run_pipeline()
