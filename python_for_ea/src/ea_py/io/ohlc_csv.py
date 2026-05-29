"""MT5が出力したOHLC CSVを読み込む。"""

from __future__ import annotations

import math
from pathlib import Path

import pandas as pd

from ea_py.types import OhlcBar

REQUIRED_COLUMNS = ("Time", "Open", "High", "Low", "Close")
PRICE_COLUMNS = ("Open", "High", "Low", "Close")


def read_ohlc_csv(path: Path) -> list[OhlcBar]:
    """MT5が出力したOHLC CSVを検証してOhlcBar配列へ変換する。

    入力CSVは `Time,Open,High,Low,Close` 列を必須とする。
    `Time` は文字列、価格列はfloatへ変換し、内部表現では既存プロンプトと
    チャート生成処理に合わせて `Time` を `DateTime` キーへ写す。

    必須列が欠けている場合、価格列のfloat変換に失敗した場合、
    NaN/infやOHLC整合性違反がある場合は例外を送出する。
    上位パイプラインはその例外を捕捉し、MT5へ停止値を返す。
    """
    df = pd.read_csv(path, encoding="utf-8")
    missing_columns = [column for column in REQUIRED_COLUMNS if column not in df.columns]
    if missing_columns:
        joined = ", ".join(missing_columns)
        raise ValueError(f"OHLC CSV missing column(s): {joined}")

    df["Time"] = df["Time"].astype(str)
    df["Open"] = df["Open"].astype(float)
    df["High"] = df["High"].astype(float)
    df["Low"] = df["Low"].astype(float)
    df["Close"] = df["Close"].astype(float)

    ohlc: list[OhlcBar] = []
    for index, row in df.iterrows():
        prices = {column: float(row[column]) for column in PRICE_COLUMNS}
        invalid_columns = [column for column, value in prices.items() if not math.isfinite(value)]
        if invalid_columns:
            joined = ", ".join(invalid_columns)
            raise ValueError(f"OHLC CSV row {index} has non-finite price(s): {joined}")

        high = prices["High"]
        low = prices["Low"]
        open_price = prices["Open"]
        close_price = prices["Close"]
        if high < low:
            raise ValueError(f"OHLC CSV row {index} has High < Low")
        if high < max(open_price, close_price):
            raise ValueError(f"OHLC CSV row {index} has High below Open/Close")
        if low > min(open_price, close_price):
            raise ValueError(f"OHLC CSV row {index} has Low above Open/Close")

        ohlc.append(
            {
                "DateTime": row["Time"],
                "Open": open_price,
                "High": high,
                "Low": low,
                "Close": close_price,
            }
        )

    return ohlc
