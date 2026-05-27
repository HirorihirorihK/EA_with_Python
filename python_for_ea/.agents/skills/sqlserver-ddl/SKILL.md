---
name: sqlserver-ddl
description: SQL Server の CREATE TABLE、INDEX、UNIQUE制約、DDL修正、SQLファイル作成を行うときに使用する。
---

# SQL Server DDL Skill

## When to use

- SQL Server のテーブルを新規作成するとき
- CREATE TABLE を修正するとき
- INDEX、UNIQUE制約、FOREIGN KEY を追加するとき
- SQL Server用DDLをMarkdownやSQLファイルに整理するとき

## Rules

- SQL Server 用のDDLとして作成する。
- テーブル名・カラム名は既存ルールに合わせる。
- 主キーは原則 `ID INT IDENTITY(1,1) NOT NULL` を基本にする。
- 日時型は `DATETIME2(0)` を優先する。
- 作成日時は `CREATED_AT DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()` を基本にする。
- 更新日時が必要な場合は `UPDATED_AT DATETIME2(0) NULL` を使用する。
- 検索条件に使う列には INDEX を検討する。
- 重複防止が必要な組み合わせには UNIQUE 制約を作成する。
- DDL、INDEX、補足説明をセットで出力する。

## Output Format

1. CREATE TABLE
2. CREATE INDEX
3. UNIQUE制約
4. 補足説明

## Example

```sql
CREATE TABLE dbo.SAMPLE_TABLE (
    ID INT IDENTITY(1,1) NOT NULL,
    TOOL_ID NVARCHAR(50) NOT NULL,
    STATUS_CODE NVARCHAR(20) NOT NULL,
    CREATED_AT DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    UPDATED_AT DATETIME2(0) NULL,
    CONSTRAINT PK_SAMPLE_TABLE PRIMARY KEY CLUSTERED (ID)
);

CREATE INDEX IX_SAMPLE_TABLE_TOOL_ID
ON dbo.SAMPLE_TABLE (TOOL_ID);
```
