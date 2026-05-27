---
applyTo: "**/*.sql,**/db/**/*.py,**/repository/**/*.py,**/repositories/**/*.py,**/models/**/*.py"
---

# SQL Server Instructions

## Basic Rules

- SQL Server 用の構文で書く。
- DB接続は `pyodbc` または既存のDB接続クラスを使用する。
- テーブル名・カラム名は既存DDLに合わせる。
- SQLは可能な限り `.sql` ファイルに分離する。
- 認証情報、接続文字列、パスワードをコードに直書きしない。

## Transaction

- INSERT / UPDATE / DELETE では commit / rollback を明示する。
- 例外発生時は rollback する。
- 例外は握りつぶさず、ログに記録して再raiseまたは独自例外に変換する。

## DDL

- 主キーは原則 `IDENTITY(1,1)` を使用する。
- 日時型は特別な理由がなければ `DATETIME2(0)` を使用する。
- 作成日時は `CREATED_AT DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()` を基本にする。
- 検索条件に使う列には INDEX を検討する。
- 重複防止が必要な組み合わせには UNIQUE 制約を検討する。
