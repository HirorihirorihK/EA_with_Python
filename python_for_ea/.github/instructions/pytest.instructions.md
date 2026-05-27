---
applyTo: "tests/**/*.py"
---

# Pytest Instructions

## Basic Rules

- pytest を使用する。
- AAA パターンで書く。
- 1テスト1責務にする。
- 1テスト1Actにする。
- テスト名は `test_<対象>_<条件>_<期待結果>` にする。

## Arrange / Act / Assert

- Arrange: 前提データ、fixture、mockを準備する。
- Act: 対象処理を1回だけ実行する。
- Assert: 結果を検証する。

## Fixtures

- fixture は前提条件の名前にする。
- fixture には assert を書かない。
- fixture にテストロジックを書かない。
- Arrange が長くなる場合は fixture 化する。

## Parametrize

- 分岐、境界値、異常系は `pytest.mark.parametrize` を優先する。
- テスト内で if/else を増やしすぎない。

## Exception Test

- 例外テストでは `pytest.raises(..., match=...)` を使用する。
- 例外の型だけでなく、必要に応じてメッセージも検証する。

## Mock / Integration

- Unit TestではDB、ファイルI/O、現在時刻、外部APIをmockする。
- Integration Testには `@pytest.mark.integration` を付ける。
- 通常実行では以下を使用する。

```bash
uv run pytest -m "not integration"
```
