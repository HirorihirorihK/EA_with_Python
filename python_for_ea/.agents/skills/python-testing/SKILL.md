---
name: python-testing
description: Pythonプロジェクトでpytestの単体テスト、例外テスト、fixture、parametrize、integration testを作成・修正するときに使用する。
---

# Python Testing Skill

## When to use

- pytest のテストを新規作成するとき
- 既存ロジックのテストを追加するとき
- リファクタリング前に仕様を固定するとき
- 例外・境界値・異常系をテストするとき
- DB / I/O を含む処理をmockまたはintegration testに分離するとき

## Purpose

- 仕様をコードとして固定する。
- 変更によるデグレードを防ぐ。
- ロジックを安全にリファクタリングできる状態を作る。

## Rules

- AAA パターンを使用する。
- 1テスト1Actにする。
- テスト名は `test_<対象>_<条件>_<期待結果>` にする。
- fixture は前提条件の名前にする。
- fixture には assert を書かない。
- 分岐パターンは `pytest.mark.parametrize` で表現する。
- 例外は型とメッセージの両方を確認する。
- DB、I/O、現在時刻、外部APIはUnit Testではmockする。
- Integration Testには `@pytest.mark.integration` を付ける。

## Example

```python
import pytest


@pytest.mark.parametrize(
    ("input_value", "expected"),
    [
        ("OK", True),
        ("NG", False),
        ("", False),
    ],
)
def test_judge_status_various_inputs_returns_expected(
    input_value: str,
    expected: bool,
) -> None:
    assert judge_status(input_value) is expected


def test_validate_input_missing_column_raises_value_error() -> None:
    with pytest.raises(ValueError, match="missing column"):
        validate_input(df)
```

## Commands

```bash
uv run pytest
uv run pytest -m "not integration"
uv run pytest -q
```

## Checklist

- [ ] AAAパターンになっている
- [ ] 1テスト1Actになっている
- [ ] テスト名で条件と期待結果が分かる
- [ ] 境界値と異常系が含まれている
- [ ] 外部依存がUnit Testに混ざっていない
