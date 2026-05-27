---
name: python-base
description: Python 3.13プロジェクトで基本的なコーディング、型ヒント、pathlib、例外処理、関数分割を行うときに使用する。
---

# Python Base Skill

## When to use

- Pythonコードを新規作成するとき
- 既存コードをリファクタリングするとき
- 関数分割、型ヒント追加、pathlib化を行うとき
- UI、DB、I/O、ビジネスロジックを分離するとき

## Rules

- Python 3.13 を前提にする。
- すべての関数に引数と戻り値の型ヒントを付ける。
- 戻り値がない関数には `-> None` を付ける。
- `Any` は必要最小限にする。
- `os.path` ではなく `pathlib.Path` を使用する。
- `print` ではなく `logging` を使用する。
- magic number は定数化する。
- 例外は握りつぶさない。
- UI、DB、I/O、ビジネスロジックを分離する。
- 副作用がある関数は、関数名から意図が分かるようにする。

## Example

```python
from __future__ import annotations

from pathlib import Path


def load_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")
```

## Checklist

- [ ] 型ヒントがある
- [ ] 戻り値型がある
- [ ] `Path` を使用している
- [ ] `print` を使用していない
- [ ] 例外を握りつぶしていない
- [ ] 1関数1責務になっている
