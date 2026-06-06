import os
import re
import base64
from datetime import datetime

import pandas as pd
import matplotlib.pyplot as plt
import openai

# =========================
# ユーザー環境設定
# =========================

user_name = "new"
user_path = f"C:\\Users\\{user_name}"
terminal_ID = "5BDB0B60344C088C2FA5CA35699BAAFD"
terminal_path = f"{user_path}\\AppData\\Roaming\\MetaQuotes\\Terminal\\{terminal_ID}\\MQL5\\Files"

MT_encoding = "utf-16 LE"

YOUR_API_KEY = os.getenv("OPENAI_API_KEY")
if YOUR_API_KEY is None:
    raise RuntimeError("OPENAI_API_KEY が環境変数に設定されていません。")

gpt_model = "gpt-5.5"
reasoning_effort = os.getenv("OPENAI_REASONING_EFFORT", "low")
text_verbosity = os.getenv("OPENAI_TEXT_VERBOSITY", "low")

# =========================
# 入出力ファイル
# =========================
input_file_path = os.path.join(terminal_path, "ohlc_H4.csv")
trend_state_path = os.path.join(terminal_path, "trend_state.txt")
done_trend_path = os.path.join(terminal_path, "process_done_trend.txt")

# =========================
# チャート画像の設定
# =========================
CANDLE_TREND = 72
instrument = "GOLD"
timeframe = "H4"
TMP_TREND_PATH = os.path.join(terminal_path, "tmp_chart_trend.png")

DEBUG_PRINT = False  # True: 理由も取得してファイル保存 / False: 数値(0/1/2)のみ

# デバッグ理由ログ
DEBUG_TREND_REASON_PATH = os.path.join(terminal_path, "debug_trend.txt")

# =========================
# OpenAI クライアント
# =========================
client = openai.OpenAI(api_key=YOUR_API_KEY)

# =========================
# ユーティリティ
# =========================
def _now_str() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def write_debug_trend(path: str, current_price: float, numeric_summary: str, gpt_numeric: str, reason_text: str):
    """debug_trend.txt に追記（数値 + 理由）"""
    try:
        with open(path, "a", encoding="utf-8") as f:
            f.write("=" * 60 + "\n")
            f.write(f"DEBUG TIME    : {_now_str()}\n")
            f.write(f"MODEL         : {gpt_model}\n")
            f.write(f"REASONING     : {reasoning_effort}\n")
            f.write(f"VERBOSITY     : {text_verbosity}\n")
            f.write(f"CURRENT PRICE : {current_price:.2f}\n")
            f.write("=" * 60 + "\n\n")
            f.write("---- NUMERIC SUMMARY START ----\n")
            f.write((numeric_summary or "").strip() + "\n")
            f.write("---- NUMERIC SUMMARY END ----\n\n")
            f.write("---- GPT NUMERIC (0/1/2) START ----\n")
            f.write((gpt_numeric or "").strip() + "\n")
            f.write("---- GPT NUMERIC (0/1/2) END ----\n\n")
            f.write("---- REASON START ----\n")
            f.write((reason_text or "").strip() + "\n")
            f.write("---- REASON END ----\n\n")
    except Exception as e:
        print("debug_trend.txt write error:", e)

# =========================
# 数値要約作成
# =========================
def summarize_ohlc(ohlc):
    """
    ohlc: [{"DateTime","Open","High","Low","Close"}, ...]
    """
    n = len(ohlc)
    highs = [b["High"] for b in ohlc]
    lows = [b["Low"] for b in ohlc]
    opens = [b["Open"] for b in ohlc]
    closes = [b["Close"] for b in ohlc]

    hi = max(highs)
    lo = min(lows)

    trs = []
    prev_close = closes[0]
    for b in ohlc:
        tr = max(
            b["High"] - b["Low"],
            abs(b["High"] - prev_close),
            abs(b["Low"] - prev_close),
        )
        trs.append(tr)
        prev_close = b["Close"]

    atr = sum(trs) / max(1, len(trs))

    bodies = [abs(c - o) for o, c in zip(opens, closes)]
    avg_body = sum(bodies) / max(1, len(bodies))

    up_cnt = sum(1 for o, c in zip(opens, closes) if c >= o)
    dn_cnt = n - up_cnt

    slope = (closes[-1] - closes[0]) / max(1, n - 1)

    return {
        "n": n,
        "high": hi,
        "low": lo,
        "range": hi - lo,
        "atr": atr,
        "avg_body": avg_body,
        "up": up_cnt,
        "down": dn_cnt,
        "slope": slope,
    }

# =========================
# ローソク足描画
# =========================
def ohlc_to_candlestick_png_file(
    ohlc_data,
    save_path,
    instrument="XAUUSD",
    timeframe="H4",
    dark=True,
    dpi=180,
    figsize=(12, 4),
):
    if not ohlc_data:
        raise ValueError("ohlc_data is empty")

    if dark:
        plt.style.use("dark_background")

    fig, ax = plt.subplots(figsize=figsize, dpi=dpi)
    ax.grid(True, linestyle=":", linewidth=0.6, alpha=0.6)

    candle_w = 0.55
    wick_lw = 1.0

    for i, bar in enumerate(ohlc_data):
        o = bar["Open"]
        h = bar["High"]
        l = bar["Low"]
        c = bar["Close"]

        up = c >= o
        color = "#00ff66" if up else "#ff3355"

        ax.vlines(i, l, h, linewidth=wick_lw, color=color)

        body_low = min(o, c)
        body_h = max(abs(c - o), 1e-8)

        rect = plt.Rectangle(
            (i - candle_w / 2, body_low),
            candle_w,
            body_h,
            color=color,
            alpha=0.95,
        )
        ax.add_patch(rect)

    ax.yaxis.tick_right()
    ax.yaxis.set_label_position("right")

    dt_labels = [b["DateTime"] for b in ohlc_data]
    n = len(ohlc_data)
    show_idx = [0, n // 2, n - 1] if n >= 3 else list(range(n))

    ax.set_xticks(show_idx)
    ax.set_xticklabels([dt_labels[i] for i in show_idx], fontsize=8)

    ax.set_xlim(-1, n)
    ax.set_title(f"{instrument} {timeframe} ({n} candles)", fontsize=10)

    plt.tight_layout()
    fig.savefig(save_path, format="png")
    plt.close(fig)

# =========================
# PNG → Base64(data URL)
# =========================
def png_file_to_data_url(path: str) -> str:
    with open(path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("utf-8")
    return f"data:image/png;base64,{b64}"

# =========================
# system / prompt
# =========================
def build_trend_system_content():
    # ★通常（DEBUG=False）：現行通り「数値1つのみ」を強制
    return (
        "あなたは相場分析の判定器です。"
        "出力は数字1つ（0/1/2）のみ。"
        "説明文、記号、空行、追加の数値は一切出力しない。"
        "出力は必ず 0 または 1 または 2。"
    ).strip()

def build_trend_system_content_debug():
    # ★DEBUG=True：数値 + 理由を同時に返させる（ブロックで分離）
    return (
        "あなたは相場分析の判定器です。"
        "ユーザーの指示を厳密に守ってください。"
        "出力は必ず指定されたブロック構造に従ってください。"
        "NUMERIC OUTPUT では 0/1/2 の数字1つのみ。"
        "REASON OUTPUT では理由を文章で簡潔に。"
    ).strip()

def build_trend_numeric_summary(current_price: float, ohlc_trend):
    s = summarize_ohlc(ohlc_trend)
    return f"""
【数値要約（チャートと同一データ）】
- 現在価格: {current_price:.2f}
- 対象本数: {s["n"]}本（H4）
  高値={s["high"]:.2f}, 安値={s["low"]:.2f}, レンジ={s["range"]:.2f},
  ATR={s["atr"]:.2f}, 平均実体={s["avg_body"]:.2f},
  上昇本数={s["up"]}, 下落本数={s["down"]}, 傾き={s["slope"]:.4f}
""".strip()

def build_trend_user_prompt(current_price: float, numeric_summary: str, candle_count: int):
    # ★元のプロンプト（変更なし）
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

def build_trend_user_prompt_debug(current_price: float, numeric_summary: str, candle_count: int):
    # ★元のプロンプトは変えず、末尾に「デバッグ出力形式」を追加
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

# =========================
# GPT呼び出し（画像付き）
# =========================
def call_gpt_trend(client, model, system_content: str, user_text: str, image_data_url: str | None, max_output_tokens: int):
    content_parts = [{"type": "input_text", "text": user_text}]
    if image_data_url:
        content_parts.append({"type": "input_image", "image_url": image_data_url})

    resp = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": system_content},
            {"role": "user", "content": content_parts},
        ],
        reasoning={"effort": reasoning_effort},
        text={"verbosity": text_verbosity},
        max_output_tokens=max_output_tokens,
    )
    return (resp.output_text or "").strip()

# =========================
# デバッグブロック抽出（trend用）
# =========================
def extract_trend_blocks_debug(gpt_text: str):
    """
    ### NUMERIC OUTPUT ### ... ### REASON OUTPUT ### ... ### END ###
    を抽出
    """
    if not gpt_text:
        return "", ""

    m_num = re.search(
        r"###\s*NUMERIC OUTPUT\s*###\s*(.*?)\s*###\s*REASON OUTPUT\s*###",
        gpt_text,
        re.DOTALL,
    )
    numeric_part = m_num.group(1).strip() if m_num else ""

    m_reason = re.search(
        r"###\s*REASON OUTPUT\s*###\s*(.*?)\s*###\s*END\s*###",
        gpt_text,
        re.DOTALL,
    )
    reason_part = m_reason.group(1).strip() if m_reason else ""

    return numeric_part, reason_part

# =========================
# GPT返信 → 0/1/2 に正規化
# =========================
def parse_trend_012(text: str) -> int:
    if not isinstance(text, str):
        return 0
    m = re.findall(r"[-+]?\d+", text.strip())
    if not m:
        return 0
    v = int(m[0])
    return v if v in (0, 1, 2) else 0

# =========================
# 出力（0/1/2のみ） + done
# =========================
def _write_outputs(trend_val: int):
    # trend_state.txt（0/1/2 だけ）
    try:
        with open(trend_state_path, mode="w", encoding=MT_encoding, newline="") as f:
            f.write(str(trend_val))
    except Exception as e:
        print("trend_state.txt 書き込みエラー:", e)

    # doneファイル（空ファイルでOK）
    try:
        with open(done_trend_path, mode="w", encoding="utf-8", newline="") as f:
            f.write("")
    except Exception as e:
        print("process_done_trend.txt 作成エラー:", e)

# =========================
# メイン処理：CSV→画像→GPT→trend_state.txt→done
#  - DEBUG=False: 数値(0/1/2)のみ（現行通り）
#  - DEBUG=True : 数値+理由（debug_trend.txtに保存）
# =========================
def run_pipeline():
    trend_val = 0  # 安全側デフォルト

    # CSV読み込み
    try:
        df = pd.read_csv(input_file_path, encoding="utf-8")
        df["Time"] = df["Time"].astype(str)
        df["Open"] = df["Open"].astype(float)
        df["High"] = df["High"].astype(float)
        df["Low"] = df["Low"].astype(float)
        df["Close"] = df["Close"].astype(float)
    except Exception as e:
        print("CSV 読み込みエラー:", e)
        _write_outputs(trend_val)
        return

    if len(df) < 5:
        print(f"データ本数不足: len(df)={len(df)}")
        _write_outputs(trend_val)
        return

    # OHLC整形
    ohlc_all = []
    for _, r in df.iterrows():
        ohlc_all.append(
            {
                "DateTime": r["Time"],
                "Open": float(r["Open"]),
                "High": float(r["High"]),
                "Low": float(r["Low"]),
                "Close": float(r["Close"]),
            }
        )

    # 直近 CANDLE_TREND 本
    ohlc_trend = ohlc_all[-min(CANDLE_TREND, len(ohlc_all)) :]
    current_price = float(ohlc_trend[-1]["Close"])

    # 画像生成
    image_url = None
    try:
        ohlc_to_candlestick_png_file(
            ohlc_data=ohlc_trend,
            save_path=TMP_TREND_PATH,
            instrument=instrument,
            timeframe=timeframe,
            dark=True,
        )
        image_url = png_file_to_data_url(TMP_TREND_PATH)
    except Exception as e:
        print("画像生成エラー（画像なしで続行）:", e)
        image_url = None

    # 数値要約（共通）
    numeric_summary = build_trend_numeric_summary(current_price=current_price, ohlc_trend=ohlc_trend)

    # =========================
    # GPT呼び出し（DEBUGで完全分離）
    # =========================
    if DEBUG_PRINT:
        system_content = build_trend_system_content_debug()
        user_text = build_trend_user_prompt_debug(
            current_price=current_price,
            numeric_summary=numeric_summary,
            candle_count=len(ohlc_trend),
        )
        max_tokens = 250
    else:
        system_content = build_trend_system_content()
        user_text = build_trend_user_prompt(
            current_price=current_price,
            numeric_summary=numeric_summary,
            candle_count=len(ohlc_trend),
        )
        max_tokens = 16

    gpt_reply = ""
    try:
        gpt_reply = call_gpt_trend(
            client=client,
            model=gpt_model,
            system_content=system_content,
            user_text=user_text,
            image_data_url=image_url,
            max_output_tokens=max_tokens,
        )
    except Exception as e:
        print("OpenAI APIエラー:", e)
        gpt_reply = ""

    if DEBUG_PRINT:
        print("---- GPT TREND REPLY START ----")
        print(gpt_reply)
        print("---- GPT TREND REPLY END ----")

    # =========================
    # 解析・保存
    # =========================
    if DEBUG_PRINT:
        numeric_part, reason_part = extract_trend_blocks_debug(gpt_reply)

        # numeric抽出に失敗したら、全文からフォールバック
        if not numeric_part:
            numeric_part = gpt_reply

        trend_val = parse_trend_012(numeric_part)

        # debug_trend.txt に保存（数値+理由）
        try:
            write_debug_trend(
                path=DEBUG_TREND_REASON_PATH,
                current_price=current_price,
                numeric_summary=numeric_summary,
                gpt_numeric=str(trend_val),
                reason_text=reason_part,
            )
        except Exception as e:
            print("debug_trend.txt write error:", e)

    else:
        trend_val = parse_trend_012(gpt_reply)

    # 出力（EA側は常に 0/1/2 のみ）
    _write_outputs(trend_val)

# =========================
# 実行
# =========================
if __name__ == "__main__":
    run_pipeline()
