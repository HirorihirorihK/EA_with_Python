---
name: python-settings
description: Pythonプロジェクトでpydantic-settingsを使った環境変数、.env.dev、設定クラスを実装・修正するときに使用する。
---

# Python Settings Skill

## When to use

- `settings.py` を新規作成するとき
- pydantic-settings で設定クラスを作るとき
- `.env.dev` とOS環境変数の切り替えを実装するとき
- DB接続情報、ログ出力先、共有フォルダなどを設定化するとき

## Rules

- 設定は `pydantic_settings.BaseSettings` で一元管理する。
- 開発環境は `.env.dev` を使用する。
- テスト環境と本番環境はOS環境変数を使用する。
- パス系の設定値は `pathlib.Path` で扱う。
- DB接続情報、APIキー、パスワードをコードに直書きしない。
- Settingsクラスはアプリ起動時に1回読み込む。
- 必須設定が不足した場合は、明確なValidationErrorとして扱う。

## Example

```python
from __future__ import annotations

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="APP_",
        env_file=".env.dev",
        env_file_encoding="utf-8",
    )

    db_server: str
    db_database: str
    db_username: str | None = None
    db_password: str | None = None
    log_root: Path
    output_root: Path


def get_settings() -> Settings:
    return Settings()
```

## Checklist

- [ ] 秘密情報をコードに直書きしていない
- [ ] 環境変数prefixが統一されている
- [ ] パス系設定に `Path` を使っている
- [ ] 必須設定の不足を隠していない
