"""ローソク足チャート画像の生成とdata URL変換。"""

from __future__ import annotations

import base64
from pathlib import Path
from typing import Sequence

import matplotlib.pyplot as plt

from ea_py.types import OhlcBar


def ohlc_to_candlestick_png_file(
    *,
    ohlc_data: Sequence[OhlcBar],
    save_path: Path,
    instrument: str = "GOLD",
    timeframe: str = "H4",
    dark: bool = True,
    dpi: int = 180,
    figsize: tuple[int, int] = (12, 4),
) -> None:
    """OHLCバー配列をローソク足PNGとして保存する。"""
    if not ohlc_data:
        raise ValueError("ohlc_data is empty")

    if dark:
        plt.style.use("dark_background")

    fig, ax = plt.subplots(figsize=figsize, dpi=dpi)
    ax.grid(True, linestyle=":", linewidth=0.6, alpha=0.6)

    candle_w = 0.55
    wick_lw = 1.0

    for index, bar in enumerate(ohlc_data):
        open_price = bar["Open"]
        high_price = bar["High"]
        low_price = bar["Low"]
        close_price = bar["Close"]

        is_up = close_price >= open_price
        color = "#00ff66" if is_up else "#ff3355"

        ax.vlines(index, low_price, high_price, linewidth=wick_lw, color=color)

        body_low = min(open_price, close_price)
        body_height = max(abs(close_price - open_price), 1e-8)

        rect = plt.Rectangle(
            (index - candle_w / 2, body_low),
            candle_w,
            body_height,
            color=color,
            alpha=0.95,
        )
        ax.add_patch(rect)

    ax.yaxis.tick_right()
    ax.yaxis.set_label_position("right")

    dt_labels = [bar["DateTime"] for bar in ohlc_data]
    candle_count = len(ohlc_data)
    show_idx = [0, candle_count // 2, candle_count - 1] if candle_count >= 3 else list(range(candle_count))

    ax.set_xticks(show_idx)
    ax.set_xticklabels([dt_labels[i] for i in show_idx], fontsize=8)

    ax.set_xlim(-1, candle_count)
    ax.set_title(f"{instrument} {timeframe} ({candle_count} candles)", fontsize=10)

    plt.tight_layout()
    fig.savefig(save_path, format="png")
    plt.close(fig)


def png_file_to_data_url(path: Path) -> str:
    """PNGファイルをOpenAI Vision入力用のdata URLへ変換する。"""
    encoded = base64.b64encode(path.read_bytes()).decode("utf-8")
    return f"data:image/png;base64,{encoded}"
