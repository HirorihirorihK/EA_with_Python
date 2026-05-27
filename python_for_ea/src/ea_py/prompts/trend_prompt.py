"""H4トレンド判定用のプロンプトを生成する。"""

from __future__ import annotations

from typing import Sequence

from ea_py.market.volatility import summarize_ohlc
from ea_py.types import OhlcBar


def build_trend_system_content() -> str:
    """通常モード用のシステムメッセージを返す。"""
    return (
        "あなたは相場分析の判定器です。"
        "出力は数字1つ（0/1/2）のみ。"
        "説明文、記号、空行、追加の数値は一切出力しない。"
        "出力は必ず 0 または 1 または 2。"
    ).strip()


def build_trend_system_content_debug() -> str:
    """デバッグモード用のシステムメッセージを返す。"""
    return (
        "あなたは相場分析の判定器です。"
        "ユーザーの指示を厳密に守ってください。"
        "出力は必ず指定されたブロック構造に従ってください。"
        "NUMERIC OUTPUT では 0/1/2 の数字1つのみ。"
        "REASON OUTPUT では理由を文章で簡潔に。"
    ).strip()


def build_trend_numeric_summary(current_price: float, ohlc_trend: Sequence[OhlcBar]) -> str:
    """H4チャートと同一データ由来の数値要約文を作る。"""
    summary = summarize_ohlc(ohlc_trend)
    return f"""
【数値要約（チャートと同一データ）】
- 現在価格: {current_price:.2f}
- 対象本数: {summary["n"]}本（H4）
  高値={summary["high"]:.2f}, 安値={summary["low"]:.2f}, レンジ={summary["range"]:.2f},
  EATR={summary["eatr"]:.2f}, 基準EATR={summary["eatr_baseline"]:.2f}, EATR比={summary["eatr_ratio"]:.2f},
  直近足レンジ={summary["latest_range"]:.2f}, 直近足レンジ/EATR={summary["latest_range_to_eatr"]:.2f},
  上ヒゲ={summary["latest_upper_wick"]:.2f}, 下ヒゲ={summary["latest_lower_wick"]:.2f},
  平均実体={summary["avg_body"]:.2f},
  上昇本数={summary["up"]}, 下落本数={summary["down"]}, 傾き={summary["slope"]:.4f}
""".strip()


def build_trend_user_prompt(current_price: float, numeric_summary: str, candle_count: int) -> str:
    """H4方向判定用のユーザープロンプトを作る。

    GPTにはXAUUSD/GOLDの今後12時間目線で、0=レンジ、1=上昇、2=下降の
    いずれか1つだけを返すよう強制する。
    チャート画像と同一データ由来の数値要約を併用させるが、方向が混在する場合は
    事故回避としてレンジ(0)を選ぶよう指示する。

    この関数はプロンプト文字列を作るだけで、OpenAI呼び出しや出力検証は行わない。
    """
    return f"""
あなたはXAUUSD（GOLD）のH4の今後12時間のトレンドを判定し、
次のいずれかを **数字1つ** で出力してください。

0 = 横ばい（レンジ）
1 = 上昇トレンド
2 = 下降トレンド

【入力】
- 現在価格: {current_price:.2f}
- 添付のH4チャート画像（直近{candle_count}本）
- 数値要約（同一データ由来）:
{numeric_summary}

【判定の考え方】
- 画像と数値要約の両方を参考にして良い。
- 判定ロジック（傾き、ATR、MA、ダウ理論、レンジ幅など）はあなたが最適だと思う方法でよい。
- ただし「自信がない」「方向が混在している」場合は事故回避のため 0（横ばい）を選ぶこと。

【出力ルール】
- 出力は 0 / 1 / 2 のどれか数字1つのみ。
- それ以外は一切出力しない。
""".strip()


def build_trend_user_prompt_debug(current_price: float, numeric_summary: str, candle_count: int) -> str:
    """理由出力を含むH4トレンド判定ユーザープロンプトを作る。"""
    base = build_trend_user_prompt(current_price, numeric_summary, candle_count)
    tail = """
【デバッグ追加ルール】
デバッグモードのため、出力を次の3ブロック構成にしてください（順番固定）。

### NUMERIC OUTPUT ###
0 / 1 / 2 のどれか数字1つのみ
（余計な文字、空行、記号は禁止）

### REASON OUTPUT ###
なぜその判定（0/1/2）にしたかを、箇条書きで3〜6点で簡潔に。
最後に「12時間目線での注意点」を1行で。

### END ###
""".strip()
    return f"{base}\n\n{tail}".strip()
