# Project Agent Instructions

## 位置づけ

- このファイルは、`C:\ea_py` プロジェクトで作業するAIエージェント共通の正本とする。
- GitHub Copilot 固有の動作指示は、必要になった時点で `.github/copilot-instructions.md` に分離する。
- ファイル種別・技術領域ごとの詳細指示は、必要に応じて `.github/instructions/`、`.cursor/rules/`、`.agents/skills/` に分離する。
- 長文ルールを複数ファイルへ重複記載しない。共通ルールはこのファイルを優先する。

## プロジェクト概要

- このプロジェクトは、MT5のHIT-EAから出力されたOHLC CSVを読み取り、XAUUSD/GOLD向けのH4相場環境判定とH1エントリー候補価格を生成するPython補助アプリケーションである。
- 現行ソースでは、H4相場環境判定はルールベースで行い、H1エントリー候補価格の生成にOpenAI APIを使用する。
- Pythonは直接発注しない。発注、注文管理、M15確定足による最終タイミング判定はMQL5 EA側で行う。
- Pythonの主な責務は以下とする。
  - `get_trend_reply.py`: H4 OHLCから相場環境 `market_state` を判定し、`trend_state.txt` を出力する。
  - `get_entry_reply.py`: H1 OHLCとH4 `market_state` からエントリー候補 `target_prices.txt` を出力する。
  - `bat/*.bat`: MT5 EAからPythonスクリプトを起動する固定エントリーポイント。
- 現在の実行入口はルート直下の `get_trend_reply.py` / `get_entry_reply.py` である。ファイル名や配置を変更する場合は、必ず `bat/` とMQL5 EA側の呼び出し設定も更新する。

## 基本方針

- 読みやすさ、保守性、安全なリファクタリングを優先する。
- 既存の実行契約を壊さない。特にMT5の入出力ファイル名、文字コード、doneファイル作成順序を変更する場合は慎重に行う。
- 不明点がある場合は、既存コード、`docs/architecture/folder-structure.md`、`docs/refactor/` 配下の設計メモを優先して判断する。
- 新しい仕組みを追加する前に、既存スクリプト内の類似処理を確認する。
- 認証情報、接続文字列、APIキー、パスワードをコードに直書きしない。OpenAI APIキーは `OPENAI_API_KEY` 環境変数から取得する。
- 取引ロジックは利益を保証しない。異常値、読込失敗、API失敗、パース失敗時は必ず新規注文を抑止する安全側へ倒す。

## 取引ロジック上の責務分離

- H4は相場環境判定を担当する。
  - `0 = LOW_VOL_RANGE`
  - `1 = HIGH_VOL_RANGE`
  - `2 = LOW_VOL_UP`
  - `3 = HIGH_VOL_UP`
  - `4 = LOW_VOL_DOWN`
  - `5 = HIGH_VOL_DOWN`
  - `6 = TECHNICAL_ERROR_STOP`
  - 旧異常ボラ閾値に達した場合も、現行ソースでは停止値6にせず、方向に応じた高ボラstateへ吸収する。
  - データ不足、不正な方向値、EATR異常値など技術的に安全判定できない場合のみ、停止値6へ倒す。
- H1はエントリー候補価格の作成を担当する。
  - H4 `market_state` と整合する戦略だけを候補にする。
  - H4と矛盾する方向、レンジ中央、技術エラー停止、根拠が弱い候補は `0.00` で見送る。
- M15は最終的な発注タイミング確認を担当する。
  - M15の判定はMQL5 EA側で行う。
  - PythonのH1プロンプトでは、M15の細かな反転を先読みしすぎない。
- Pythonは売買判断の候補を作るだけで、注文送信、ポジション操作、未約定注文キャンセルは行わない。

## 入出力契約

- MT5連携ファイルは原則としてMT5の `MQL5\Files` 配下に置く。
- 入力CSV:
  - `ohlc_H4.csv`: H4トレンド判定用。
  - `ohlc_H1.csv`: H1エントリー候補生成用。
  - CSVは `Time,Open,High,Low,Close` の列を前提にする。
- 出力ファイル:
  - `trend_state.txt`: H4 `market_state` を1つの整数で出力する。
  - `target_prices.txt`: 13行の数値を出力する。
  - `process_done_trend.txt`: `trend_state.txt` の出力完了後に作成する。
  - `process_done_entry.txt`: `target_prices.txt` の出力完了後に作成する。
- `target_prices.txt` の形式:
  - 1行目: `res_chk`
  - 2-4行目: T1 Buy Stop の `entry`, `tp`, `sl`
  - 5-7行目: T2 Buy Limit の `entry`, `tp`, `sl`
  - 8-10行目: T3 Sell Stop の `entry`, `tp`, `sl`
  - 11-13行目: T4 Sell Limit の `entry`, `tp`, `sl`
- MT5が読む出力ファイルは、既存仕様に合わせて `utf-16 LE` を維持する。
- 結果ファイルを書き終えてからdoneファイルを作成する。古いdoneファイルが残った状態で新しい結果を書かない。

## Python

- Python 3.13 を前提にする。
- パッケージ管理と仮想環境管理は `uv` を使用する。
- すべての新規関数に引数と戻り値の型ヒントを付ける。戻り値がない関数は `-> None` とする。
- 変数名・関数名は `snake_case`、クラス名は `PascalCase`、定数名は `UPPER_SNAKE_CASE` を使用する。
- 新規コードでは `pathlib.Path` を優先する。既存の `os.path` は、該当箇所を触るタイミングで段階的に置き換える。
- 新規コードでは `logging` を使用する。既存のbat実行向け `print` は、ロギング整備時に段階的に置き換える。
- magic number は定数化する。
- 例外は握りつぶさない。外部連携失敗を捕捉する場合も、ログを残し、出力は安全側へ倒す。
- DataFrame加工、チャート描画、OpenAI呼び出し、プロンプト生成、パース、ファイルI/Oは関数またはモジュール単位で分離する。
- OpenAI APIのレスポンスは必ずバリデーションする。期待形式に合わない場合は新規注文停止または対象戦略見送りにする。

## フォルダ構成

- 詳細なフォルダ構成は `docs/architecture/folder-structure.md` を正本として参照する。
- 現在の実行入口はルート直下の2スクリプトとする。
- 主要処理は `src/ea_py/` 配下へ移行済みである。今後のリファクタリングでも共通処理は `src/ea_py/` 配下へ追加・整理し、ルート直下スクリプトは互換用の薄いエントリーポイントとして残す。
- テストコードは `tests/` 配下に配置する。
- ドキュメントは `docs/` 配下に配置する。
- 設定ファイルを追加する場合は `config/` 配下に配置する。ただしAPIキーなどの秘密情報は置かない。
- `work/` 配下は作業用・参照用の一時ファイルとして扱い、実行時の正本にしない。
- FastAPI、Streamlit、DB関連のフォルダは、実際にその機能を追加するまで作らない。

## 品質チェック / テスト

- pytest を使用する。
- 変更によりロジックが変わる場合は、テストの追加・修正を検討する。
- Unit TestではOpenAI API、ファイルI/O、現在時刻などの外部依存をmockする。
- Integration Testは `@pytest.mark.integration` を付けて通常実行から分離する。
- 変更後は、影響範囲に応じて以下を確認する。

```bash
uv run python -m py_compile C:/ea_py/get_trend_reply.py C:/ea_py/get_entry_reply.py
uv run ruff check .
uv run ty check
uv run pytest
```

## MQL5 / MT5 連携

- MQL5 EAファイルはこのリポジトリ外のMT5データフォルダに存在する場合がある。
- MT5配下のEAファイルを変更する場合は、変更前にバックアップを作成する。
- Python側の出力仕様を変更する場合は、MQL5側の読込処理も同時に確認する。
- batファイルのパス、Pythonスクリプト名、doneファイル名、出力ファイル名を変更する場合は、EA側の定義も合わせて更新する。

## Logging / Error Handling

- ユーザー表示用エラーと内部ログ用エラーを分離する。
- 内部エラーは詳細をログへ記録する。
- MT5へ返す結果は、EAが安全に処理できる単純な数値ファイルにする。
- APIやCSV読込で失敗した場合は、未定義状態のまま処理を続けず、停止値を出力する。

