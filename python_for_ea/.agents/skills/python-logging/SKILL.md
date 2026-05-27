---
name: python-logging
description: Pythonプロジェクトでlogging設定、TOML設定、logger分離、例外ログを実装・修正するときに使用する。
---

# Python Logging Skill

## When to use

- logging設定を新規作成するとき
- TOMLからlogging設定を読み込むとき
- `print` を logging に置き換えるとき
- SQL、アプリ、Workerなどloggerを分離するとき
- 例外ログの出力を修正するとき

## Rules

- `print` は使用しない。
- `logging` を使用する。
- logging設定は TOML で管理する。
- logger は用途別に分離する。
- SQL、アプリ、バッチ、Worker、外部I/Oは必要に応じて別loggerにする。
- 例外発生時は `logger.exception(...)` を優先する。
- ユーザー向けメッセージと内部ログを分離する。

## Example

```python
from __future__ import annotations

import logging
import logging.config
import tomllib
from pathlib import Path


def setup_logging(toml_path: Path) -> None:
    with toml_path.open("rb") as f:
        config = tomllib.load(f)

    logging.config.dictConfig(config)


logger = logging.getLogger(__name__)
```

## Exception Example

```python
try:
    run_task()
except Exception:
    logger.exception("Task failed")
    raise
```

## Checklist

- [ ] `print` を使用していない
- [ ] `logger = logging.getLogger(__name__)` を使っている
- [ ] 例外時に `logger.exception` を使っている
- [ ] ユーザー表示と内部ログが分離されている
