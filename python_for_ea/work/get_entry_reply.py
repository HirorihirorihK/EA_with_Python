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

gpt_model = "gpt-5.4"

# =========================
# 入出力ファイル
# =========================
input_file_path = f"{terminal_path}\\ohlc_H1.csv"
output_file_path = f"{terminal_path}\\target_prices.txt"

trend_file_path = os.path.join(terminal_path, "trend_state.txt")
done_entry_file_path = os.path.join(terminal_path, "process_done_entry.txt")

DEBUG_PRINT = False  # True: 数値+理由をデバッグファイルへ / False: 現行通り数値のみ

# ★追加：デバッグ理由ログ
DEBUG_ENTRY_REASON_PATH = os.path.join(terminal_path, "debug_entry.txt")

# =========================
# ローソク足画像の設定
# =========================
CANDLE_SHORT = 36
CANDLE_LONG = 72

instrument = "GOLD"
timeframe = "H1"

TMP_SHORT_PATH = os.path.join(terminal_path, "tmp_chart_short.png")
TMP_LONG_PATH = os.path.join(terminal_path, "tmp_chart_long.png")

# =========================
# OpenAI クライアント
# =========================
client = openai.OpenAI(api_key=YOUR_API_KEY)

# =========================
# トレンド読み取り（H4側の結果を読む）
# =========================
def read_trend_state(path: str) -> int:
    """
    return: 0=RANGE / 1=UP / 2=DOWN
    読めない場合は 0（安全側）
    """
    try:
        if not os.path.exists(path):
            return 0
        s = open(path, "r", encoding=MT_encoding).read().strip()
        v = int(s)
        return v if v in (0, 1, 2) else 0
    except Exception:
        return 0

def strategies_by_trend(trend_state: int):
    """
    トレンドに応じて「GPTへ依頼する戦略」を絞る
    """
    if trend_state == 1:
        return [1, 2]  # 上昇: 順張り買い + 逆張り買い
    if trend_state == 2:
        return [3, 4]  # 下降: 順張り売り + 逆張り売り
    return [2, 4]      # 横ばい: 逆張り買い + 逆張り売り

# =========================
# 数値要約作成
# =========================
def summarize_ohlc(ohlc):
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
    timeframe="H1",
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
# system / prompt ブロック
# =========================
def build_system_content_block():
    # ★通常（DEBUG=False）：現行の「数値のみ」指示を維持
    return (
        "あなたは優秀な投資アドバイザーです。"
        "ユーザーの指示を厳密に守り、指定された形式の数値のみを出力してください。"
        "思考過程や説明文は一切出力してはいけません。"
    ).strip()

def build_system_content_block_debug():
    # ★DEBUG=True：ブロック構造で「数値部分」と「理由」を同時出力
    return (
        "あなたは優秀な投資アドバイザーです。"
        "ユーザーの指示を厳密に守ってください。"
        "出力は必ず指定されたブロック構造に従ってください。"
        "NUMERIC OUTPUT では指定フォーマットの数値行のみ。"
        "REASON OUTPUT では理由を文章で簡潔に。"
    ).strip()

def build_numeric_summary(current_price, ohlc_short, ohlc_long):
    sum_short = summarize_ohlc(ohlc_short)
    sum_long = summarize_ohlc(ohlc_long)

    return f"""
【数値要約（チャートと同一データ）】
- 現在価格: {current_price:.2f}

- 短期({sum_short["n"]}本):
  高値={sum_short["high"]:.2f}, 安値={sum_short["low"]:.2f}, レンジ={sum_short["range"]:.2f},
  ATR={sum_short["atr"]:.2f}, 平均実体={sum_short["avg_body"]:.2f},
  上昇本数={sum_short["up"]}, 下落本数={sum_short["down"]}, 傾き={sum_short["slope"]:.4f}

- 中期({sum_long["n"]}本):
  高値={sum_long["high"]:.2f}, 安値={sum_long["low"]:.2f}, レンジ={sum_long["range"]:.2f},
  ATR={sum_long["atr"]:.2f}, 平均実体={sum_long["avg_body"]:.2f},
  上昇本数={sum_long["up"]}, 下落本数={sum_long["down"]}, 傾き={sum_long["slope"]:.4f}
""".strip()

def build_header(current_price, numeric_summary, trend_state, candle_short=CANDLE_SHORT, candle_long=CANDLE_LONG):
    header = f"""
以下はXAUUSD（GOLD）の{timeframe}足チャート画像です。

- 1枚目：短期（直近{candle_short}本）
- 2枚目：中期（直近{candle_long}本）

現在価格は {current_price:.2f}（短期チャートの最後の足の終値）とします。

【重要：外部トレンド判定（H4）】
trend_state = {trend_state} （0=RANGE, 1=UP, 2=DOWN）
この trend_state は外部ロジックで確定した前提情報です。必ず尊重してください。
- trend_state=1（UP）のとき：買い優先（売り方向の提案は避ける）
- trend_state=2（DOWN）のとき：売り優先（買い方向の提案は避ける）
- trend_state=0（RANGE）のとき：逆張り優先
""".strip()

    if numeric_summary:
        header = f"{header}\n\n{numeric_summary}".strip()

    return header

def build_common_rules_block(selected_strategies):
    desc = {
        1: "1. 順張りエントリーの買い",
        2: "2. 逆張りエントリーの買い",
        3: "3. 順張りエントリーの売り",
        4: "4. 逆張りエントリーの売り",
    }
    cond = {
        1: "(エントリー基準 > 現在価格, 利確目標 > エントリー基準, エントリー基準 > ロスカット基準)",
        2: "(現在価格 > エントリー基準, 利確目標 > エントリー基準, エントリー基準 > ロスカット基準)",
        3: "(現在価格 > エントリー基準, エントリー基準 > 利確目標, ロスカット基準 > エントリー基準)",
        4: "(エントリー基準 > 現在価格, エントリー基準 > 利確目標, ロスカット基準 > エントリー基準)",
    }

    lines = []
    for k in selected_strategies:
        lines.append(f"{desc[k]}\n  {cond[k]}")
    strategy_block = "\n\n".join(lines).strip()

    out_order = " → ".join(str(x) for x in selected_strategies)

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
- 各価格の大小関係が、その戦略の条件と整合しているか必ず検証してください。
- それぞれの戦略において、利益の期待値が最大になるように価格を設定してください。

【時間条件（全戦略共通）】
- 現在価格から1時間以内にエントリー基準価格に到達しなければ、その戦略はキャンセル。
- エントリー後12時間以内に利確・損切に到達しなければ、その時点の価格でクローズ。

【出力ルール（最重要）】
以下の形式で **対象戦略の行だけ** 出力してください。

- 1行につき1戦略
- 行の順序は {out_order}
- 各行は以下の4つをカンマ区切りで出力

  戦略番号,エントリー基準価格,利確目標価格,ロスカット基準価格

- 数値のみを出力し、説明文・空行・記号は一切出力してはいけません。
- 各行の価格は必ず小数点以下2桁まで出力すること（例: 4812.62）。
""".strip()

def build_common_rules_block_debug(selected_strategies):
    # 元のルールは変えずに末尾へデバッグ出力を足す
    base = build_common_rules_block(selected_strategies)
    tail = """
【デバッグ追加ルール】
デバッグモードのため、出力を次の3ブロック構成にしてください（順番固定）。

### NUMERIC OUTPUT ###
ここには、上記「出力ルール（最重要）」に従った“数値行のみ”をそのまま出力してください。
（余計な文字や空行は禁止）

### REASON OUTPUT ###
各出力行について、entry/tp/sl をそのように置いた意図を各1〜2行で説明してください。
最後に「trend_state をどう解釈したか」を1〜2行でまとめてください。

### END ###
""".strip()
    return f"{base}\n\n{tail}".strip()

def build_caution_block():
    return """
※ trend_state とチャート/数値要約が矛盾すると判断した場合は、安全側に倒してください。
  具体的には「エントリーしづらい価格（現在価格から遠い）」にするか、条件が成立しない価格にしてください。
""".strip()

# =========================
# GPT呼び出し（画像付き）
# =========================
def call_gpt(client, model, system_content: str, user_text: str, images_data_urls, max_output_tokens: int = 220):
    content_parts = [{"type": "input_text", "text": user_text}]
    for u in images_data_urls:
        content_parts.append({"type": "input_image", "image_url": u})

    resp = client.responses.create(
        model=model,
        input=[
            {"role": "system", "content": system_content},
            {"role": "user", "content": content_parts},
        ],
        temperature=0.0,
        max_output_tokens=max_output_tokens,
    )
    return resp.output_text or ""

# =========================
# subset行 → 13数値（res + (en,tp,sl)*4）
# =========================
TARGET_SIZE = 13

def parse_lines_to_13_allow_subset(gpt_reply: str):
    out = [1] + [0.0] * 12  # res=1, あとは0埋め

    try:
        lines = [l.strip() for l in gpt_reply.strip().splitlines() if l.strip()]
        for line in lines:
            nums = re.findall(r"[-+]?\d+(?:\.\d+)?", line)
            if len(nums) < 4:
                continue

            s = int(float(nums[0]))
            if s not in (1, 2, 3, 4):
                continue

            entry = float(nums[1])
            tp = float(nums[2])
            sl = float(nums[3])

            base = 1 + (s - 1) * 3
            out[base + 0] = entry
            out[base + 1] = tp
            out[base + 2] = sl

        any_price = any(v != 0.0 for v in out[1:])
        if not any_price:
            return [0] * TARGET_SIZE

        return out

    except Exception:
        return [0] * TARGET_SIZE

# =========================
# デバッグブロック抽出（ENTRY用）
# =========================
def extract_entry_blocks_debug(gpt_text: str):
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
# デバッグ理由ログ（追加）
# =========================
def _now_str() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def write_debug_entry(
    path: str,
    current_price: float,
    trend_state: int,
    selected_strategies: list,
    numeric_summary: str,
    numeric_lines: str,
    reason_text: str,
):
    try:
        with open(path, "a", encoding="utf-8") as f:
            f.write("=" * 60 + "\n")
            f.write(f"DEBUG TIME        : {_now_str()}\n")
            f.write(f"MODEL             : {gpt_model}\n")
            f.write(f"TIMEFRAME         : {timeframe}\n")
            f.write(f"TREND_STATE(H4)   : {trend_state} (0=RANGE,1=UP,2=DOWN)\n")
            f.write(f"SELECTED_STRATEGY : {','.join(str(x) for x in selected_strategies)}\n")
            f.write(f"CURRENT PRICE     : {current_price:.2f}\n")
            f.write("=" * 60 + "\n\n")
            f.write("---- NUMERIC SUMMARY START ----\n")
            f.write((numeric_summary or "").strip() + "\n")
            f.write("---- NUMERIC SUMMARY END ----\n\n")
            f.write("---- GPT NUMERIC LINES START ----\n")
            f.write((numeric_lines or "").strip() + "\n")
            f.write("---- GPT NUMERIC LINES END ----\n\n")
            f.write("---- REASON START ----\n")
            f.write((reason_text or "").strip() + "\n")
            f.write("---- REASON END ----\n\n")
    except Exception as e:
        print("debug_entry.txt write error:", e)

# =========================
# メイン処理：CSV→画像→GPT→13数値→保存→done
# =========================
def run_pipeline():
    # ===== トレンド読み取り（H4側結果） =====
    trend_state = read_trend_state(trend_file_path)
    selected_strategies = strategies_by_trend(trend_state)

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
        numeric_list = [0] * TARGET_SIZE
        _write_outputs(numeric_list)
        return

    if len(df) < CANDLE_LONG:
        print(f"データ本数不足: len(df)={len(df)} (need >= {CANDLE_LONG})")
        numeric_list = [0] * TARGET_SIZE
        _write_outputs(numeric_list)
        return

    # OHLC整形（DateTimeキーで統一）
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

    ohlc_short = ohlc_all[-CANDLE_SHORT:]
    ohlc_long = ohlc_all[-CANDLE_LONG:]
    current_price = float(ohlc_short[-1]["Close"])

    # 画像生成
    try:
        ohlc_to_candlestick_png_file(
            ohlc_data=ohlc_short,
            save_path=TMP_SHORT_PATH,
            instrument=instrument,
            timeframe=timeframe,
            dark=True,
        )
        ohlc_to_candlestick_png_file(
            ohlc_data=ohlc_long,
            save_path=TMP_LONG_PATH,
            instrument=instrument,
            timeframe=timeframe,
            dark=True,
        )
        img_short_url = png_file_to_data_url(TMP_SHORT_PATH)
        img_long_url = png_file_to_data_url(TMP_LONG_PATH)
        images_data_urls = [img_short_url, img_long_url]
    except Exception as e:
        print("画像生成エラー:", e)
        numeric_list = [0] * TARGET_SIZE
        _write_outputs(numeric_list)
        return

    # プロンプト作成（トレンドに応じて対象戦略を変更）
    numeric_summary = build_numeric_summary(
        current_price=current_price,
        ohlc_short=ohlc_short,
        ohlc_long=ohlc_long,
    )
    header = build_header(
        current_price=current_price,
        numeric_summary=numeric_summary,
        trend_state=trend_state,
    )
    caution = build_caution_block()

    if DEBUG_PRINT:
        system_content = build_system_content_block_debug()
        common_rules = build_common_rules_block_debug(selected_strategies)
        max_tokens = 650
    else:
        system_content = build_system_content_block()
        common_rules = build_common_rules_block(selected_strategies)
        max_tokens = 220

    user_text = "\n\n".join([header, common_rules, caution]).strip()

    # GPT呼び出し
    gpt_reply = ""
    try:
        gpt_reply = call_gpt(
            client=client,
            model=gpt_model,
            system_content=system_content,
            user_text=user_text,
            images_data_urls=images_data_urls,
            max_output_tokens=max_tokens,
        ).strip()
    except Exception as e:
        print("OpenAI APIエラー:", e)
        numeric_list = [0] * TARGET_SIZE
        _write_outputs(numeric_list)
        return

    if DEBUG_PRINT:
        print("---- TREND ----", trend_state, "selected=", selected_strategies)
        print("---- GPT REPLY START ----")
        print(gpt_reply)
        print("---- GPT REPLY END ----")

    # =========================
    # DEBUG: ブロック抽出して「数値部分」と「理由」を分離
    # =========================
    if DEBUG_PRINT:
        numeric_lines, reason_text = extract_entry_blocks_debug(gpt_reply)

        # numeric_lines が取れない場合は、全文から数値部分をパース（フォールバック）
        if not numeric_lines:
            numeric_lines = gpt_reply

        numeric_list = parse_lines_to_13_allow_subset(numeric_lines)

        # debug_entry.txt に保存
        try:
            write_debug_entry(
                path=DEBUG_ENTRY_REASON_PATH,
                current_price=current_price,
                trend_state=trend_state,
                selected_strategies=selected_strategies,
                numeric_summary=numeric_summary,
                numeric_lines=numeric_lines,
                reason_text=reason_text,
            )
        except Exception as e:
            print("debug_entry.txt write error:", e)

    else:
        # 通常運用：現行通り数値だけ
        numeric_list = parse_lines_to_13_allow_subset(gpt_reply)

    # 保存 & done
    _write_outputs(numeric_list)

def _write_outputs(numeric_list):
    # 結果をファイルに保存（MT5向け：utf-16 LE / 1行1数値）
    try:
        with open(output_file_path, mode="w", encoding=MT_encoding) as f:
            for number in numeric_list:
                f.write(f"{number}\n")
    except Exception as e:
        print("ファイル保存中にエラーが発生しました:", e)

    # done（entry）
    try:
        with open(done_entry_file_path, "w", encoding="utf-8") as f:
            f.write("")
    except Exception as e:
        print("process_done_entry.txt 作成エラー:", e)

# =========================
# 実行
# =========================
if __name__ == "__main__":
    run_pipeline()