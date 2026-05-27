"""H4 OHLCからmarket_stateを生成するパイプライン。"""

from __future__ import annotations

import logging

from ea_py.constants import (
    CANDLE_TREND,
    DEBUG_PRINT,
    MIN_VOL_BARS,
    MT_ENCODING,
    TECHNICAL_ERROR_STOP,
)
from ea_py.io.debug_logs import append_debug_trend
from ea_py.io.mt5_files import write_result_then_done
from ea_py.io.ohlc_csv import read_ohlc_csv
from ea_py.market.trend_state import (
    classify_direction_from_ohlc,
    classify_market_state,
)
from ea_py.market.volatility import summarize_ohlc
from ea_py.paths import build_trend_paths
from ea_py.prompts.trend_prompt import build_trend_numeric_summary

logger = logging.getLogger(__name__)


def write_trend_output(market_state: int) -> None:
    """trend_state.txtを書き、完了後にprocess_done_trend.txtを作る。"""
    paths = build_trend_paths()
    write_result_then_done(
        result_path=paths.trend_state,
        result_text=str(market_state),
        result_encoding=MT_ENCODING,
        done_path=paths.done_trend,
    )


def run_pipeline() -> None:
    """H4 OHLCからMT5向けのmarket_stateを生成する。

    実行契約:
    - `ohlc_H4.csv` を読み、直近H4足を数値要約へ変換する。
    - EMA、レンジ内位置、高安更新、DMI系方向優位、効率比から
      H4方向0/1/2を判定する。
    - 方向0/1/2をEATRベースのボラティリティ分類と合成して
      `market_state` 0..6 を決定する。
    - 最後に `trend_state.txt` をMT5用エンコーディングで書き、
      書き込み完了後に `process_done_trend.txt` を作成する。

    安全側フォールバック:
    CSV読込失敗、データ不足、EATR異常値は
    技術エラー停止値として6を出力し、H1側で新規注文を抑止する。
    相場ボラティリティが旧異常閾値を超えた場合は、停止せず高ボラstateへ吸収する。
    """
    paths = build_trend_paths()
    market_state = TECHNICAL_ERROR_STOP

    try:
        ohlc_all = read_ohlc_csv(paths.input_csv)
    except Exception:
        logger.exception("CSV 読み込みエラー")
        write_trend_output(market_state)
        return

    if len(ohlc_all) < MIN_VOL_BARS:
        logger.error("データ本数不足: len(ohlc)=%s (need >= %s)", len(ohlc_all), MIN_VOL_BARS)
        write_trend_output(market_state)
        return

    ohlc_trend = ohlc_all[-min(CANDLE_TREND, len(ohlc_all)) :]
    current_price = float(ohlc_trend[-1]["Close"])
    summary = summarize_ohlc(ohlc_trend)
    numeric_summary = build_trend_numeric_summary(current_price=current_price, ohlc_trend=ohlc_trend)

    direction_val, direction_reason = classify_direction_from_ohlc(ohlc_trend, summary)
    market_state, market_state_reason = classify_market_state(direction_val, summary)
    classification_reason = f"{direction_reason}\n{market_state_reason}"

    if DEBUG_PRINT:
        try:
            append_debug_trend(
                path=paths.debug_reason,
                model="rule-based-h4-direction",
                reasoning_effort="none",
                max_output_tokens=0,
                api_diagnostics="OpenAI trend direction call is not used.",
                current_price=current_price,
                numeric_summary=numeric_summary,
                direction_numeric=str(direction_val),
                market_state=market_state,
                classification_reason=classification_reason,
                reason_text=direction_reason,
            )
        except Exception:
            logger.exception("debug_trend.txt write error")

    write_trend_output(market_state)


def main() -> None:
    """ログ設定を行ってH4トレンド判定パイプラインを起動する。"""
    logging.basicConfig(level=logging.INFO, format="%(levelname)s:%(name)s:%(message)s")
    run_pipeline()
