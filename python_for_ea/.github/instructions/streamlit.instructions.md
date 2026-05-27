---
applyTo: "app.py,pages/**/*.py,**/streamlit/**/*.py"
---

# Streamlit Instructions

## Basic Rules

- UIとロジックを分離する。
- Streamlitページには画面表示、入力受付、結果表示を中心に書く。
- DBアクセス、ファイルI/O、集計処理は `src/` 側に分離する。
- `st.session_state` は専用クラスまたは専用関数で管理する。
- ユーザー向けエラーと内部エラーを分離する。

## Error Handling

- ユーザーに表示するメッセージは分かりやすくする。
- 詳細な例外情報は logging に出力する。
- 例外を握りつぶさない。
- 既存のユーザー向け例外クラスがある場合は、それを優先する。

## Long Running Task

- 長時間処理をStreamlitのリクエスト内で直接実行しない。
- 時間がかかる処理はWorker、Job Queue、外部プロセスへの分離を検討する。
- Streamlit側はジョブ登録とステータス表示を担当する。
