---
name: streamlit-page
description: Streamlitページからロジックを分離し、UI、session_state、service、repositoryに整理するときに使用する。
---

# Streamlit Page Refactor Skill

## When to use

- Streamlitページの処理が長くなったとき
- UIとロジックを分離したいとき
- `st.session_state` の管理を専用クラスに寄せたいとき
- DB処理、ファイルI/O、集計処理を `src/` 側へ移したいとき

## Rules

- ページファイルには画面表示、入力受付、結果表示を中心に残す。
- ビジネスロジックは service 層へ移す。
- DBアクセスは repository 層へ移す。
- DataFrame加工は pure function として分離する。
- `st.session_state` は専用クラスまたは専用関数で管理する。
- ユーザー向けエラーと内部ログを分離する。
- 長時間処理はJob Queue / Workerへの分離を検討する。

## Suggested Structure

```text
src/
├─ pages/
├─ services/
├─ repositories/
├─ models/
├─ settings.py
└─ exceptions.py
```

## Checklist

- [ ] ページファイルにDB処理が残っていない
- [ ] ページファイルに重い処理が残っていない
- [ ] session_stateのキーが散らばっていない
- [ ] ユーザー表示エラーと内部ログが分かれている
- [ ] service / repository / utility の責務が分かれている
