# ea_py

MT5 の HIT-EA から出力された OHLC CSV を読み取り、GOLD/XAUUSD 向けの相場環境判定とエントリー候補価格を返す Python 補助アプリケーションです。

Python 側は注文送信を行いません。発注、注文管理、M15 確定足による最終タイミング判定は MT5/MQL5 EA 側が担当します。

## 現在の実行入口

MT5 EA からは `bat/` 経由でルート直下の互換スクリプトを起動します。

```text
<TerminalDataPath>/MQL5/python_for_ea/
├─ get_trend_reply.py
├─ get_entry_reply.py
├─ bat/
│  ├─ get_trend_reply.bat
│  └─ get_entry_reply.bat
└─ src/
   └─ ea_py/
```

- `get_trend_reply.py`: `src/ea_py/pipelines/trend_pipeline.py` を起動する薄い入口。
- `get_entry_reply.py`: `src/ea_py/pipelines/entry_pipeline.py` を起動する薄い入口。
- `bat/get_trend_reply.bat`: bat自身の親フォルダをプロジェクトルートとして `uv run python get_trend_reply.py` を実行。
- `bat/get_entry_reply.bat`: bat自身の親フォルダをプロジェクトルートとして `uv run python get_entry_reply.py` を実行。

入口ファイル名や配置を変える場合は、`bat/` と MQL5 EA 側の呼び出し設定も合わせて更新してください。

## MT5 連携ファイル

既定の連携先は、このプロジェクトの親にある MT5 `MQL5/Files` ディレクトリです。

```text
<TerminalDataPath>/MQL5/Files/
```

パスの組み立ては `src/ea_py/paths.py` で定義しています。特殊な配置では `MT5_FILES_DIR` または `MT5_DATA_PATH` 環境変数で上書きできます。

EAからbat経由で起動する場合は、第1引数で渡された `HIT_<symbol>_<magic_number>` 接頭辞が `MT5_EA_FILE_PREFIX` として設定されます。第2引数で渡された `_Symbol` の価格桁数は `MT5_PRICE_DIGITS` として設定されます。Pythonはこの接頭辞をすべての連携ファイル名へ付けるため、同じTerminal内で複数EAや複数シンボルを動かしてもファイルが衝突しません。手動実行で接頭辞が未設定の場合は、従来のファイル名を使います。

### 入力

```text
[<prefix>_]ohlc_H4.csv
[<prefix>_]ohlc_H1.csv
```

CSV は UTF-8 読み込みで、次の列を必須とします。価格列はfloatへ変換し、NaN/infや `High < Low`、High/LowがOpen/Closeを含まない行は停止値へ倒すため例外にします。

```text
Time,Open,High,Low,Close
```

### 出力

```text
[<prefix>_]trend_state.txt
[<prefix>_]target_prices.txt
[<prefix>_]target_zones.txt
[<prefix>_]process_done_trend.txt
[<prefix>_]process_done_entry.txt
```

MT5 が読む結果ファイルは `utf-16 LE` で出力します。結果ファイルを書き終えたあとに done ファイルを作成します。古い done ファイルは結果書き込み前に削除されます。

## H4 トレンド判定

`get_trend_reply.py` は H4 OHLC から `trend_state.txt` を生成します。

現在の H4 判定は OpenAI API ではなく、ソースコード上のルールベース判定です。直近 72 本を使い、EMA、レンジ内位置、高安更新、DMI 系方向優位、効率比、EATR ベースのボラティリティを組み合わせて `market_state` を決定します。

```text
0 = LOW_VOL_RANGE
1 = HIGH_VOL_RANGE
2 = LOW_VOL_UP
3 = HIGH_VOL_UP
4 = LOW_VOL_DOWN
5 = HIGH_VOL_DOWN
6 = TECHNICAL_ERROR_STOP
```

`6` は現在の実装では技術エラー停止値です。CSV 読み込み失敗、データ不足、EATR 異常値など、安全側へ倒す必要がある場合に出力されます。

## H1 エントリー候補生成

`get_entry_reply.py` は `trend_state.txt` と H1 OHLC から `target_prices.txt` と `target_zones.txt` を生成します。

処理の概要:

1. H4 の `market_state` を読み込む。
2. `market_state` と整合する戦略だけを選ぶ。
3. H1 の短期 36 本、中期 72 本からチャート PNG と数値要約を作る。
4. H1 インバランス初動を Python 側で判定し、矛盾する候補を抑止する。
5. OpenAI Responses API に候補価格・予測ゾーン生成を依頼する。
   出力は Structured Outputs のJSON Schemaで固定する。
6. GPT JSON出力を既存13行形式と分割エントリー用ゾーン形式へ展開し、価格の大小関係、距離、reward/riskを検証する。
7. `target_prices.txt` と `target_zones.txt` を書き、両方の完了後に `process_done_entry.txt` を作成する。

H4 状態ごとの許可戦略:

```text
0,1: T2 Buy Limit / T4 Sell Limit
2,3: T1 Buy Stop  / T2 Buy Limit
4,5: T3 Sell Stop / T4 Sell Limit
6  : 全停止
```

`target_prices.txt` は 13 行です。

```text
1行目     : res_chk
2-4行目   : T1 Buy Stop  の entry, tp, sl
5-7行目   : T2 Buy Limit の entry, tp, sl
8-10行目  : T3 Sell Stop の entry, tp, sl
11-13行目 : T4 Sell Limit の entry, tp, sl
```

有効候補が残らない場合や、CSV/API/パース/検証に失敗した場合は、13 行すべて `0` の停止値を返します。

分割エントリー用の `target_zones.txt` は7行です。

```text
1行目     : schema_version（2）
2行目     : res_chk
3行目     : candidate_id（H1確定足時刻由来）
4-7行目   : strategy, zone_low, zone_high, tp, sl
```

EA側で分割エントリーを有効にした場合は、この予測ゾーンを `split_entry_count` 本に分割してpending注文を出します。ロットは総量分割または1注文固定を選択できます。

`target_zones.txt` の価格小数桁は `MT5_PRICE_DIGITS` に合わせます。EA/bat経由では自動設定され、手動実行で未指定の場合は安全側で5桁を使います。

## OpenAI 設定

H1 エントリー候補生成では OpenAI API を使用します。
Responses APIの `text.format` にJSON Schemaを渡し、GPT出力を自然文やCSV風テキストではなく
`schema_version` と `strategies` を持つ構造化JSONに固定します。
JSONが不正、API応答が未完了、価格条件やreward/risk条件に合わない場合は停止値へ倒します。

必須:

```powershell
$env:OPENAI_API_KEY = "..."
```

任意:

```powershell
$env:OPENAI_MODEL = "..."
$env:OPENAI_REASONING_EFFORT = "low"
$env:MT5_EA_FILE_PREFIX = "HIT_GOLD_10001"
$env:MT5_PRICE_DIGITS = "2"
```

`OPENAI_MODEL` 未設定時は `src/ea_py/constants.py` の `DEFAULT_GPT_MODEL` を使います。`OPENAI_REASONING_EFFORT` は `none`, `low`, `medium`, `high`, `xhigh` のいずれかです。`MT5_EA_FILE_PREFIX` と `MT5_PRICE_DIGITS` は手動実行時だけ指定すればよく、EA/bat経由では自動設定されます。

## 主なモジュール

```text
src/ea_py/config.py              環境変数から実行時設定を読み込む
src/ea_py/constants.py           共通定数
src/ea_py/paths.py               MT5 連携ファイルパス
src/ea_py/io/ohlc_csv.py         OHLC CSV 読み込みと検証
src/ea_py/io/mt5_files.py        結果ファイルと done ファイルの書き込み
src/ea_py/charting/candlestick.py ローソク足 PNG 生成
src/ea_py/market/volatility.py   True Range / EATR / 数値要約
src/ea_py/market/trend_state.py  H4 方向判定と market_state 合成
src/ea_py/market/target_prices.py GPT 出力のパースと価格検証
src/ea_py/market/target_zones.py 分割エントリー用ゾーン出力
src/ea_py/market/imbalance.py    H1 インバランス初動判定
src/ea_py/openai_client.py       OpenAI Responses API ラッパー
src/ea_py/pipelines/             H4/H1 パイプライン
```

詳細なフォルダ構成は `docs/architecture/folder-structure.md` も参照してください。

## 開発

Python 3.13 と `uv` を前提にします。

```powershell
uv sync
```

個別実行:

```powershell
uv run python get_trend_reply.py
uv run python get_entry_reply.py
```

品質チェック:

```powershell
uv run python -m py_compile get_trend_reply.py get_entry_reply.py
uv run ruff check .
uv run ty check
uv run pytest
```

## 注意

- API キーや接続情報はコードへ直書きしないでください。
- `work/` 配下は作業用・参照用であり、実行時の正本ではありません。
- Python は候補価格を作るだけで、注文送信、ポジション操作、未約定注文キャンセルは行いません。
- 出力仕様を変える場合は、MQL5 EA 側の読み込み処理も同時に確認してください。
