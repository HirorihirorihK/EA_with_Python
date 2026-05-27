"""MT5が出力したOHLC CSVを読み込む。"""

from __future__ import annotations

from pathlib import Path

import pandas as pd

from ea_py.types import OhlcBar

REQUIRED_COLUMNS = ("Time", "Open", "High", "Low", "Close")


def read_ohlc_csv(path: Path) -> list[OhlcBar]:
    """MT5が出力したOHLC CSVを検証してOhlcBar配列へ変換する。

    入力CSVは `Time,Open,High,Low,Close` 列を必須とする。
    `Time` は文字列、価格列はfloatへ変換し、内部表現では既存プロンプトと
    チャート生成処理に合わせて `Time` を `DateTime` キーへ写す。

    必須列が欠けている場合や価格列のfloat変換に失敗した場合は例外を送出する。
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
    for _, row in df.iterrows():
        ohlc.append(
            {
                "DateTime": row["Time"],
                "Open": float(row["Open"]),
                "High": float(row["High"]),
                "Low": float(row["Low"]),
                "Close": float(row["Close"]),
            }
        )

    return ohlc
