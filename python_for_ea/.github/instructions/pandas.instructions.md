---
applyTo: "**/*.py"
---

# Pandas Instructions

## Basic Rules

- DataFrame操作は関数に分離する。
- 可能な限りベクトル化された操作を使用する。
- 不要な for ループは避ける。
- index の不一致による NaN 混入に注意する。
- concat / merge / join の後は、必要に応じて index と列を検証する。
- 入力DataFrameを破壊的に変更する場合は、関数名またはdocstringで明示する。

## Validation

- 必須列が存在するか確認する。
- 行数、index、列名の整合性を確認する。
- 欠損値、0、空文字、型不一致を考慮する。

## Visualization

- 可視化は原則 matplotlib を使用する。
- seaborn は明示的に依頼された場合のみ使用する。
