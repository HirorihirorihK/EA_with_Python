"""H1エントリー候補生成用のプロンプトを生成する。"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

from ea_py.constants import CANDLE_LONG, CANDLE_SHORT, ENTRY_RESPONSE_SCHEMA_VERSION, ENTRY_TIMEFRAME, MARKET_STATE_LABELS
from ea_py.market.imbalance import ImbalanceAnalysis, format_imbalance_summary
from ea_py.market.volatility import summarize_ohlc
from ea_py.types import OhlcBar, OhlcSummary

ENTRY_REASON_CODES = (
    "trend_breakout",
    "pullback",
    "range_edge",
    "range_reversal",
    "skip_weak_signal",
    "skip_mid_range",
    "skip_distance",
    "skip_risk",
    "skip_conflict",
    "skip_other",
)


def build_system_content_block() -> str:
    """通常モード用のシステムメッセージを返す。"""
    return (
        "あなたはアルゴリズム取引用の価格候補生成器です。"
        "投資助言や自然文説明ではなく、指定JSON Schemaに一致する機械可読な候補だけを返してください。"
        "ユーザーの制約、market_state、選択戦略、価格関係を厳密に守ってください。"
        "迷う場合は必ずskipにしてください。"
    ).strip()


def build_system_content_block_debug() -> str:
    """デバッグモード用のシステムメッセージを返す。"""
    return (
        "あなたはアルゴリズム取引用の価格候補生成器です。"
        "指定JSON Schemaに一致する機械可読な候補だけを返してください。"
        "自然文の理由や思考過程は出力せず、理由はreason_codeだけで表してください。"
    ).strip()


def _safe_ratio(numerator: float, denominator: float) -> float:
    """0除算を避けて比率を返す。"""
    if denominator <= 0.0:
        return 0.0
    return numerator / denominator


def _format_position_metrics(summary: OhlcSummary, current_price: float) -> str:
    """レンジ内位置と高安までの距離を要約行へ追加する。"""
    high = float(summary["high"])
    low = float(summary["low"])
    price_range = float(summary["range"])
    eatr = float(summary["eatr"])
    range_position = _safe_ratio(current_price - low, price_range)
    distance_to_high = high - current_price
    distance_to_low = current_price - low

    return (
        f"  現在価格レンジ位置={range_position:.2f}（0=安値付近, 1=高値付近）, "
        f"高値まで={distance_to_high:.2f}({_safe_ratio(distance_to_high, eatr):.2f}EATR), "
        f"安値まで={distance_to_low:.2f}({_safe_ratio(distance_to_low, eatr):.2f}EATR)"
    )


def build_numeric_summary(
    current_price: float,
    ohlc_short: Sequence[OhlcBar],
    ohlc_long: Sequence[OhlcBar],
) -> str:
    """短期・中期H1チャートからプロンプト用の数値要約文を作る。"""
    sum_short = summarize_ohlc(ohlc_short)
    sum_long = summarize_ohlc(ohlc_long)

    return f"""
【数値要約（チャートと同一データ）】
- 現在価格: {current_price:.2f}

- 短期({sum_short["n"]}本):
  高値={sum_short["high"]:.2f}, 安値={sum_short["low"]:.2f}, レンジ={sum_short["range"]:.2f},
  EATR={sum_short["eatr"]:.2f}, 基準EATR={sum_short["eatr_baseline"]:.2f}, EATR比={sum_short["eatr_ratio"]:.2f},
  直近足レンジ={sum_short["latest_range"]:.2f}, 直近足レンジ/EATR={sum_short["latest_range_to_eatr"]:.2f},
  上ヒゲ={sum_short["latest_upper_wick"]:.2f}, 下ヒゲ={sum_short["latest_lower_wick"]:.2f},
  平均実体={sum_short["avg_body"]:.2f},
  上昇本数={sum_short["up"]}, 下落本数={sum_short["down"]}, 傾き={sum_short["slope"]:.4f}
{_format_position_metrics(sum_short, current_price)}

- 中期({sum_long["n"]}本):
  高値={sum_long["high"]:.2f}, 安値={sum_long["low"]:.2f}, レンジ={sum_long["range"]:.2f},
  EATR={sum_long["eatr"]:.2f}, 基準EATR={sum_long["eatr_baseline"]:.2f}, EATR比={sum_long["eatr_ratio"]:.2f},
  直近足レンジ={sum_long["latest_range"]:.2f}, 直近足レンジ/EATR={sum_long["latest_range_to_eatr"]:.2f},
  上ヒゲ={sum_long["latest_upper_wick"]:.2f}, 下ヒゲ={sum_long["latest_lower_wick"]:.2f},
  平均実体={sum_long["avg_body"]:.2f},
  上昇本数={sum_long["up"]}, 下落本数={sum_long["down"]}, 傾き={sum_long["slope"]:.4f}
{_format_position_metrics(sum_long, current_price)}
""".strip()


def build_header(
    current_price: float,
    numeric_summary: str,
    trend_state: int,
    candle_short: int = CANDLE_SHORT,
    candle_long: int = CANDLE_LONG,
) -> str:
    """現在価格、画像説明、H4 market_stateを含むヘッダー文を作る。"""
    header = f"""
以下はXAUUSD（GOLD）の{ENTRY_TIMEFRAME}足チャート画像です。

- 1枚目：短期（直近{candle_short}本）
- 2枚目：中期（直近{candle_long}本）

現在価格は {current_price:.2f}（短期チャートの最後の足の終値）とします。

【重要：外部環境判定（H4）】
market_state = {trend_state}（{MARKET_STATE_LABELS.get(trend_state, "UNKNOWN")}）
この market_state は外部ロジックで確定した前提情報です。必ず尊重してください。
- 0 = 低ボラレンジ: レンジ端からの逆張りのみ候補
- 1 = 高ボラレンジ: レンジ端かつ反転根拠が強い逆張りのみ候補
- 2 = 低ボラ上昇: 買い優先
- 3 = 高ボラ上昇: 買い優先、売り逆張りは禁止
- 4 = 低ボラ下降: 売り優先
- 5 = 高ボラ下降: 売り優先、買い逆張りは禁止
- 6 = 技術エラー停止: Python/CSV/API/パース失敗時のみ。新規注文停止

【H1の役割】
- H1では、H4 market_state と整合する方向・セットアップだけを候補にしてください。
- H1がH4方向と明確に逆行、またはレンジ中央で優位性が弱い場合は見送ってください。
- 画像と数値要約が矛盾する場合は、バックテスト再現性を優先して数値要約を主根拠にしてください。
- 外部ニュース、経済指標、未知のファンダメンタル材料は考慮しないでください。
- 実際の発注タイミングはEA側のM15確定足フィルターで確認します。
  H1ではM15の細かな反転を先読みせず、1時間以内に到達しうる妥当な候補価格を重視してください。
""".strip()

    if numeric_summary:
        header = f"{header}\n\n{numeric_summary}".strip()

    return header


def build_imbalance_guidance(analysis: ImbalanceAnalysis) -> str:
    """Pythonで決定済みのH1インバランス判定をGPTへ伝える補助ルールを返す。"""
    summary = format_imbalance_summary(analysis)
    if analysis.signal == "BUY":
        signal_rule = (
            "- H1では買い方向の初動が検出されています。"
            "ただしH4 market_stateと整合する戦略だけを維持し、H4と逆方向の直接候補は出さないでください。"
        )
    elif analysis.signal == "SELL":
        signal_rule = (
            "- H1では売り方向の初動が検出されています。"
            "ただしH4 market_stateと整合する戦略だけを維持し、H4と逆方向の直接候補は出さないでください。"
        )
    else:
        signal_rule = "- H1では明確なインバランス初動は検出されていません。既存のmarket_state別ルールを優先してください。"

    return f"""
【H1インバランス判定（Pythonの数値ロジックで確定済み）】
- {summary}
{signal_rule}
- インバランス有無をあなたが再判定しないでください。
- 実際の発注直前にはEA側のM15確定足フィルターが別途確認します。
""".strip()


def build_market_state_guidance(trend_state: int) -> str:
    """H4 market_state別のH1候補生成ルールを返す。

    H1は候補価格作成だけを担当し、H4環境と矛盾する方向は出さない。
    レンジでは端からの逆張り条件を厳しくし、トレンドではH4方向に沿う戦略だけを
    許可する。高ボラトレンドでは逆方向の逆張りを禁止し、異常ボラや未知状態では
    新規停止を指示する。
    """
    if trend_state == 0:
        return """
【market_state別の追加条件】
- 低ボラレンジのため、T2/T4はレンジ上限・下限に十分近い場合だけ候補にしてください。
- 価格がレンジ中央付近なら、対象戦略を 0.00,0.00,0.00 で見送ってください。
""".strip()

    if trend_state == 1:
        return """
【market_state別の追加条件】
- 高ボラレンジのため、逆張り条件を通常より厳しくしてください。
- T2はレンジ下限付近、下ヒゲ、ブレイク直後ではないことを重視してください。
- T4はレンジ上限付近、上ヒゲ、ブレイク直後ではないことを重視してください。
- 直近足レンジ/EATRが大きすぎる、または端を強く抜けた直後なら、対象戦略を 0.00,0.00,0.00 で見送ってください。
""".strip()

    if trend_state == 3:
        return """
【market_state別の追加条件】
- 高ボラ上昇のため、売り方向の逆張りは禁止です。
- T1は上方向ブレイク、T2は浅い押し目買いだけを候補にしてください。
- 深い押し目や急落直後で買い根拠が弱い場合は、対象戦略を 0.00,0.00,0.00 で見送ってください。
""".strip()

    if trend_state == 5:
        return """
【market_state別の追加条件】
- 高ボラ下降のため、買い方向の逆張りは禁止です。
- T3は下方向ブレイク、T4は浅い戻り売りだけを候補にしてください。
- 深い戻りや急騰直後で売り根拠が弱い場合は、対象戦略を 0.00,0.00,0.00 で見送ってください。
""".strip()

    if trend_state == 2:
        return """
【market_state別の追加条件】
- 低ボラ上昇のため、買い方向のみ候補にしてください。
- T1は上方向ブレイク、T2は押し目買いとして妥当な距離だけを候補にしてください。
""".strip()

    if trend_state == 4:
        return """
【market_state別の追加条件】
- 低ボラ下降のため、売り方向のみ候補にしてください。
- T3は下方向ブレイク、T4は戻り売りとして妥当な距離だけを候補にしてください。
""".strip()

    return """
【market_state別の追加条件】
- 技術エラー停止または不明な状態のため、新規注文は停止してください。
""".strip()


def build_strategy_distance_rules(
    selected_strategies: Sequence[int],
    max_entry_distance: float | dict[int, float] | None,
) -> str:
    """戦略別の現在価格からの距離制限ルール文を返す。"""
    if max_entry_distance is None:
        return ""

    if isinstance(max_entry_distance, dict):
        lines = []
        for strategy in selected_strategies:
            distance = max_entry_distance.get(strategy)
            if distance is None or distance <= 0.0:
                continue
            lines.append(
                f"- 戦略{strategy}のエントリー基準価格は現在価格から最大 {distance:.2f} 以内にしてください。"
            )
        if not lines:
            return ""
        return "\n".join(lines) + "\n  この範囲を超える深い指値・遠いブレイク待ちは、遅延エントリーになりやすいため見送ってください。"

    if max_entry_distance <= 0.0:
        return ""

    return (
        f"- エントリー基準価格は現在価格から最大 {max_entry_distance:.2f} 以内にしてください。"
        "この範囲を超える深い指値・遠いブレイク待ちは、遅延エントリーになりやすいため見送ってください。"
    )


def build_common_rules_block(
    selected_strategies: Sequence[int],
    max_entry_distance: float | dict[int, float] | None = None,
) -> str:
    """選択戦略に応じた価格決定ルールとGPT出力形式を作る。

    `selected_strategies` にはH4 market_stateと整合する戦略番号だけを渡す。
    GPTには対象戦略の候補だけを、JSON Schemaに一致するオブジェクトで返すよう指定する。
    各戦略のentry/tp/slの大小関係、1時間以内の到達条件、12時間以内の決済目線、
    条件が弱い場合に `0.00,0.00,0.00,0.00,0.00` で見送るルールもここで明示する。

    出力の実検証は `parse_lines_to_13_allow_subset` と `sanitize_numeric_list` が担当する。
    """
    descriptions = {
        1: "1. 順張りエントリーの買い",
        2: "2. 逆張りエントリーの買い",
        3: "3. 順張りエントリーの売り",
        4: "4. 逆張りエントリーの売り",
    }
    conditions = {
        1: "(エントリー基準 > 現在価格, 利確目標 > エントリー基準, エントリー基準 > ロスカット基準)",
        2: "(現在価格 > エントリー基準, 利確目標 > エントリー基準, エントリー基準 > ロスカット基準)",
        3: "(現在価格 > エントリー基準, エントリー基準 > 利確目標, ロスカット基準 > エントリー基準)",
        4: "(エントリー基準 > 現在価格, エントリー基準 > 利確目標, ロスカット基準 > エントリー基準)",
    }

    lines = []
    for strategy in selected_strategies:
        lines.append(f"{descriptions[strategy]}\n  {conditions[strategy]}")
    strategy_block = "\n\n".join(lines).strip()

    out_order = " → ".join(str(strategy) for strategy in selected_strategies)
    distance_rule = build_strategy_distance_rules(selected_strategies, max_entry_distance)

    return f"""
このデータを用いて、以下の戦略パターンについてのみ、
それぞれ独立にエントリー条件を検討してください。

【対象戦略】
{strategy_block}

【価格決定ルール】
- 各戦略ごとに、以下の3つの価格を必ず決定してください。
  - エントリー基準価格
  - 利確目標価格
  - ロスカット基準価格
- 各戦略ごとに、エントリー基準価格の周辺にある「予測ゾーン」も必ず決定してください。
  - zone_low は予測ゾーンの低い価格
  - zone_high は予測ゾーンの高い価格
  - エントリー基準価格は必ず zone_low 以上 zone_high 以下にしてください。
- 各価格の大小関係が、その戦略の条件と整合しているか必ず検証してください。
- reward/risk が 1.20 未満になる候補は、期待値が弱いため見送ってください。
- SL距離がH1の値幅に対して広すぎる、またはTPまでの余地が小さすぎる候補は見送ってください。
- 条件が弱い、ブレイク直後、レンジ中央付近、EATR基準でリスクが大きすぎる等で見送る場合は、
  decision を "skip" とし、entry/tp/sl/zone_low/zone_high をすべて 0.0 にしてください。
{distance_rule}

【時間条件（全戦略共通）】
- 現在価格から1時間以内にエントリー基準価格に到達しなければ、その戦略はキャンセル。
- 実際の発注はEA側でM15確定足の勢い・反転・候補価格への接近を確認してから行う。
- エントリー後12時間以内に利確・損切に到達しなければ、その時点の価格でクローズ。

【出力ルール（最重要）】
- Responses APIのJSON Schemaに一致するJSONオブジェクトだけを出力してください。
- schema_version は {ENTRY_RESPONSE_SCHEMA_VERSION}。
- strategies には対象戦略だけを入れ、順序は {out_order}。
- 各strategy要素は strategy, decision, entry, tp, sl, zone_low, zone_high, reason_code を必ず含めてください。
- decision は "use" または "skip" のみ。
- reason_code は次のいずれかのみ: {", ".join(ENTRY_REASON_CODES)}
- 自然文、Markdown、余分なキー、空行は一切出力しないでください。
""".strip()


def build_common_rules_block_debug(
    selected_strategies: Sequence[int],
    max_entry_distance: float | dict[int, float] | None = None,
) -> str:
    """デバッグ時もライブと同じStructured Outputsルールを使う。"""
    return build_common_rules_block(selected_strategies, max_entry_distance)


def build_caution_block() -> str:
    """market_stateとH1判断が矛盾した場合の安全側ルールを返す。"""
    return """
※ market_state とチャート/数値要約が矛盾すると判断した場合は、安全側に倒してください。
  具体的には対象戦略を 0.00,0.00,0.00 で見送ってください。
""".strip()


def build_entry_response_text_format(selected_strategies: Sequence[int]) -> dict[str, Any]:
    """Responses API Structured Outputs用のJSON Schemaを返す。"""
    strategy_enum = [int(strategy) for strategy in selected_strategies if strategy in (1, 2, 3, 4)]
    if not strategy_enum:
        strategy_enum = [1, 2, 3, 4]

    strategy_item_schema: dict[str, Any] = {
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "strategy": {"type": "integer", "enum": strategy_enum},
            "decision": {"type": "string", "enum": ["use", "skip"]},
            "entry": {"type": "number"},
            "tp": {"type": "number"},
            "sl": {"type": "number"},
            "zone_low": {"type": "number"},
            "zone_high": {"type": "number"},
            "reason_code": {"type": "string", "enum": list(ENTRY_REASON_CODES)},
        },
        "required": [
            "strategy",
            "decision",
            "entry",
            "tp",
            "sl",
            "zone_low",
            "zone_high",
            "reason_code",
        ],
    }

    return {
        "type": "json_schema",
        "name": "hit_ea_entry_candidates",
        "strict": True,
        "schema": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "schema_version": {"type": "integer", "enum": [ENTRY_RESPONSE_SCHEMA_VERSION]},
                "strategies": {"type": "array", "items": strategy_item_schema},
            },
            "required": ["schema_version", "strategies"],
        },
    }
