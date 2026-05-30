# Folder Structure

## 目的

このドキュメントは、MT5データフォルダ配下の `MQL5\python_for_ea` のフォルダ構成に関する正本である。

現在のプロジェクトは、MT5 HIT-EAから出力されたOHLC CSVをPythonで解析し、OpenAI APIを使ってGOLD/XAUUSD向けの相場環境とエントリー候補価格を返す補助アプリケーションである。

MT5 EAから `bat/` 経由でルート直下のPythonスクリプトが呼ばれているため、現時点ではルート直下の `get_trend_reply.py` と `get_entry_reply.py` を実行入口として維持する。

## 現在のフォルダ構成

```text
<TerminalDataPath>/MQL5/python_for_ea/
├─ AGENTS.md
├─ README.md
├─ pyproject.toml
├─ uv.lock
├─ get_trend_reply.py
├─ get_entry_reply.py
├─ src/
│  └─ ea_py/
│     ├─ __init__.py
│     ├─ config.py
│     ├─ constants.py
│     ├─ paths.py
│     ├─ types.py
│     ├─ io/
│     │  ├─ __init__.py
│     │  ├─ debug_logs.py
│     │  ├─ mt5_files.py
│     │  └─ ohlc_csv.py
│     ├─ charting/
│     │  ├─ __init__.py
│     │  └─ candlestick.py
│     ├─ market/
│     │  ├─ __init__.py
│     │  ├─ imbalance.py
│     │  ├─ target_prices.py
│     │  ├─ target_zones.py
│     │  ├─ volatility.py
│     │  └─ trend_state.py
│     ├─ prompts/
│     │  ├─ __init__.py
│     │  ├─ trend_prompt.py
│     │  └─ entry_prompt.py
│     ├─ openai_client.py
│     └─ pipelines/
│        ├─ __init__.py
│        ├─ trend_pipeline.py
│        └─ entry_pipeline.py
├─ tests/
│  └─ unit/
│     ├─ test_config.py
│     ├─ test_imbalance.py
│     ├─ test_openai_client.py
│     ├─ test_paths.py
│     ├─ test_target_prices.py
│     ├─ test_trend_state.py
│     └─ test_volatility.py
├─ bat/
│  ├─ get_trend_reply.bat
│  └─ get_entry_reply.bat
├─ docs/
│  ├─ architecture/
│  │  └─ folder-structure.md
│  └─ refactor/
│     └─ gold_strategy_20260503.md
└─ work/
   ├─ get_trend_reply.py
   └─ get_entry_reply.py
```

## 現在の各ファイル・フォルダの責務

| パス | 責務 |
|---|---|
| `AGENTS.md` | AIエージェント向けの共通作業方針。 |
| `pyproject.toml` | Pythonバージョン、依存関係、開発ツール定義。 |
| `uv.lock` | `uv` による依存関係ロックファイル。 |
| `get_trend_reply.py` | H4判定パイプラインを呼び出すMT5/bat互換用の薄い実行入口。 |
| `get_entry_reply.py` | H1候補生成パイプラインを呼び出すMT5/bat互換用の薄い実行入口。 |
| `src/ea_py/` | Python補助アプリケーションの正本コード。設定、I/O、チャート生成、相場計算、プロンプト、OpenAI呼び出し、パイプラインを分離して置く。 |
| `tests/unit/` | 外部APIやMT5 I/Oに依存しない純粋ロジックのUnit Test。 |
| `bat/get_trend_reply.bat` | MT5 EAから `get_trend_reply.py` を起動するためのバッチファイル。 |
| `bat/get_entry_reply.bat` | MT5 EAから `get_entry_reply.py` を起動するためのバッチファイル。 |
| `docs/architecture/` | 構成、責務、設計方針の正本を置く。 |
| `docs/refactor/` | 戦略改善案、リファクタリングメモ、検討資料を置く。 |
| `work/` | 作業用・参照用の一時ファイル置き場。実行時の正本として扱わない。 |

## 外部連携ファイル

MT5側の `MQL5\Files` 配下に、Pythonとの連携ファイルが置かれる。

EA/bat経由では `HIT_<symbol>_<magic_number>` 形式の接頭辞が `MT5_EA_FILE_PREFIX` としてPythonへ渡され、すべての連携ファイル名へ付与される。さらに `_Symbol` の価格桁数が `MT5_PRICE_DIGITS` として渡され、`target_zones.txt` の価格出力桁数に使われる。接頭辞が未設定の手動実行では旧ファイル名を維持し、価格桁数が未指定の場合は5桁を使う。

代表例:

```text
C:/Users/new/AppData/Roaming/MetaQuotes/Terminal/{terminal_ID}/MQL5/Files/
├─ HIT_GOLD_10001_ohlc_H4.csv
├─ HIT_GOLD_10001_ohlc_H1.csv
├─ HIT_GOLD_10001_trend_state.txt
├─ HIT_GOLD_10001_target_prices.txt
├─ HIT_GOLD_10001_target_zones.txt
├─ HIT_GOLD_10001_process_done_trend.txt
├─ HIT_GOLD_10001_process_done_entry.txt
├─ HIT_GOLD_10001_process_running_trend.txt
├─ HIT_GOLD_10001_process_running_entry.txt
├─ HIT_GOLD_10001_debug_trend.txt
├─ HIT_GOLD_10001_debug_entry.txt
├─ HIT_GOLD_10001_tmp_chart_trend.png
├─ HIT_GOLD_10001_tmp_chart_short.png
└─ HIT_GOLD_10001_tmp_chart_long.png
```

これらは実行時生成物であり、原則として `MQL5\python_for_ea` 配下へコピーして正本化しない。

## MQL5 EAファイル

MQL5 EAファイルは、MT5データフォルダ配下に存在する。

例:

```text
C:/Users/new/AppData/Roaming/MetaQuotes/Terminal/{terminal_ID}/MQL5/Experts/MyProject/
└─ HIT-EA_refactor_ver6.mq5
```

EAファイルはこのPythonプロジェクトの外部連携先として扱う。Python側の出力形式を変更する場合は、EA側の読込処理も同時に確認する。

## 推奨フォルダ構成

現在は、以下の構成へ移行済みである。今後は必要に応じて、設定ファイルやIntegration Testを追加する。

ルート直下の `get_trend_reply.py` と `get_entry_reply.py` は、MT5/bat互換のため薄いエントリーポイントとして残す。

```text
<TerminalDataPath>/MQL5/python_for_ea/
├─ AGENTS.md
├─ README.md
├─ pyproject.toml
├─ uv.lock
├─ get_trend_reply.py
├─ get_entry_reply.py
├─ bat/
│  ├─ get_trend_reply.bat
│  └─ get_entry_reply.bat
├─ src/
│  └─ ea_py/
│     ├─ __init__.py
│     ├─ config.py
│     ├─ paths.py
│     ├─ constants.py
│     ├─ types.py
│     ├─ io/
│     │  ├─ __init__.py
│     │  ├─ debug_logs.py
│     │  ├─ mt5_files.py
│     │  └─ ohlc_csv.py
│     ├─ charting/
│     │  ├─ __init__.py
│     │  └─ candlestick.py
│     ├─ market/
│     │  ├─ __init__.py
│     │  ├─ imbalance.py
│     │  ├─ target_prices.py
│     │  ├─ target_zones.py
│     │  ├─ volatility.py
│     │  └─ trend_state.py
│     ├─ prompts/
│     │  ├─ __init__.py
│     │  ├─ trend_prompt.py
│     │  └─ entry_prompt.py
│     ├─ openai_client.py
│     └─ pipelines/
│        ├─ __init__.py
│        ├─ trend_pipeline.py
│        └─ entry_pipeline.py
├─ tests/
│  └─ unit/
│     ├─ test_config.py
│     ├─ test_imbalance.py
│     ├─ test_openai_client.py
│     ├─ test_paths.py
│     ├─ test_target_prices.py
│     ├─ test_trend_state.py
│     └─ test_volatility.py
└─ docs/
   ├─ architecture/
   │  └─ folder-structure.md
   └─ refactor/
      └─ gold_strategy_20260503.md
```

## 推奨モジュール責務

| モジュール | 責務 |
|---|---|
| `src/ea_py/config.py` | 環境変数、モデル名、デバッグ設定などの設定読み込み。 |
| `src/ea_py/paths.py` | MT5データフォルダ、入力CSV、出力ファイルパスの組み立て。 |
| `src/ea_py/constants.py` | `market_state`、ATR期間、出力サイズなどの定数。 |
| `src/ea_py/types.py` | OHLCバー、OHLC要約、13行出力などの型定義。 |
| `src/ea_py/io/mt5_files.py` | doneファイル、runningファイル、atomic writeなどMT5連携I/O。 |
| `src/ea_py/io/ohlc_csv.py` | OHLC CSVの読込、型変換、バリデーション。 |
| `src/ea_py/io/debug_logs.py` | デバッグ理由ログの追記処理。 |
| `src/ea_py/charting/candlestick.py` | ローソク足PNG生成。 |
| `src/ea_py/market/volatility.py` | True Range、Exponential ATR、ボラティリティ分類。 |
| `src/ea_py/market/trend_state.py` | H4方向判定結果とボラティリティ分類の合成。 |
| `src/ea_py/market/target_prices.py` | GPT出力のパース、価格整合性チェック、13行形式への変換。 |
| `src/ea_py/market/target_zones.py` | GPT出力の予測ゾーンを分割エントリー用7行形式へ変換。 |
| `src/ea_py/market/imbalance.py` | H1インバランス初動判定。 |
| `src/ea_py/prompts/trend_prompt.py` | H4相場環境判定プロンプトの生成。 |
| `src/ea_py/prompts/entry_prompt.py` | H1候補価格生成プロンプトの生成。 |
| `src/ea_py/openai_client.py` | OpenAI API呼び出しの薄いラッパー。 |
| `src/ea_py/pipelines/trend_pipeline.py` | H4判定処理全体のオーケストレーション。 |
| `src/ea_py/pipelines/entry_pipeline.py` | H1候補生成処理全体のオーケストレーション。 |

## 移行ルール

- まずは既存のルート直下スクリプトの実行契約を壊さない。
- 共通化する処理から `src/ea_py/` へ移し、ルート直下スクリプトは `main()` を呼ぶだけの薄い入口へ近づける。
- 1回の変更で、ファイル移動、ロジック変更、戦略変更を同時に大きく混ぜない。
- ファイル移動を行う場合は、`bat/`、import、テスト、ドキュメントを同時に更新する。
- `work/` 配下のファイルを実装の正本として参照しない。必要な差分だけを確認し、正本へ取り込む。
- FastAPI、Streamlit、SQL Server、OracleDBなどのフォルダは、実際にその機能を追加するまで作らない。

## テスト配置方針

- Unit Testは `tests/unit/` に置く。
- Integration Testは `tests/integration/` に置き、`@pytest.mark.integration` を付ける。
- OpenAI API、MT5ファイルI/O、現在時刻はUnit Testではmockする。
- 重要なテスト対象:
  - `market_state` の分類
  - ATR/ボラティリティ計算
  - GPT出力パース
  - `target_prices.txt` の13行契約
  - ファイル書込順序とdoneファイル作成順序
  - 異常時に安全側へ倒す処理

## 生成物・一時ファイル

- `__pycache__/`、`.pytest_cache/`、チャートPNG、MT5連携のdone/runningファイルは生成物として扱う。
- 生成物を設計上の正本にしない。
- デバッグログは原因調査に使うが、恒久的な仕様はドキュメントへ反映する。

