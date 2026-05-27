---
name: oracle-select
description: Oracle Database から SELECT 文でデータを取得する処理、SQL作成、Python連携コードを作成・修正するときに使用する。Oracleは参照専用とし、INSERT、UPDATE、DELETE、MERGE、DDLは扱わない。
---

# Oracle SELECT Skill

## When to use

- Oracle Database から `SELECT` でデータを取得するとき
- Oracle用の参照SQLを作成・修正するとき
- Python から Oracle Database に接続して読み取り処理を実装するとき
- Oracle のテーブル・ビューから取得したデータを pandas DataFrame に変換するとき
- SQL Server や他DBではなく、Oracle固有のSQL構文に合わせる必要があるとき

## Scope

このSkillでは Oracle Database に対する読み取り専用処理のみを扱う。

許可する操作:

- `SELECT`
- `WITH`
- `JOIN`
- `WHERE`
- `GROUP BY`
- `HAVING`
- `ORDER BY`
- `FETCH FIRST n ROWS ONLY`
- Pythonからの読み取り処理
- pandas DataFrame への変換

扱わない操作:

- `INSERT`
- `UPDATE`
- `DELETE`
- `MERGE`
- `CREATE`
- `ALTER`
- `DROP`
- `TRUNCATE`
- `GRANT`
- `COMMIT`
- `ROLLBACK`

## Rules

- Oracle Database 用の `SELECT` 文として作成する。
- 参照専用を前提にし、データ更新系SQLは作成しない。
- 認証情報、接続文字列、パスワードをコードに直書きしない。
- 接続情報は `.env`、環境変数、Settings クラスなどから取得する。
- SQLには必要な列を明示し、原則 `SELECT *` は避ける。
- 条件値は文字列連結せず、バインド変数を使用する。
- Pythonで実行する場合は `oracledb` の使用を基本にする。
- pandasで取得する場合は `pd.read_sql_query()` または `pd.read_sql()` を使用する。
- 大量データ取得が想定される場合は、取得期間、キー条件、件数制限を検討する。
- 日付条件では `TO_DATE()`、`TRUNC()`、バインド変数の型に注意する。
- Oracleの文字列結合は `||` を使用する。
- SQL Server 固有構文は使用しない。
  - `TOP`
  - `GETDATE()`
  - `ISNULL()`
  - `LEN()`
  - `DATEADD()`
  - `DATEDIFF()`
  - `[]` による識別子囲み
- 件数制限は Oracle 12c 以降では `FETCH FIRST n ROWS ONLY` を優先する。
- 古いOracle互換が必要な場合のみ `ROWNUM` を使用する。
- テーブル名・カラム名は既存DBの定義に合わせる。
- 別名を付ける場合は読みやすい名前にする。
- SQLは保守しやすいように整形する。
- エラー時はユーザー向けメッセージと詳細ログを分ける。

## SQL Style

### 基本

```sql
SELECT
    T.TOOL_ID,
    T.PROCESS_DATE,
    T.STATUS_CODE,
    T.CREATED_AT
FROM
    SAMPLE_TABLE T
WHERE
    T.TOOL_ID = :tool_id
    AND T.PROCESS_DATE >= :start_date
    AND T.PROCESS_DATE < :end_date
ORDER BY
    T.PROCESS_DATE DESC
```

### 件数制限

```sql
SELECT
    T.TOOL_ID,
    T.PROCESS_DATE,
    T.STATUS_CODE
FROM
    SAMPLE_TABLE T
WHERE
    T.TOOL_ID = :tool_id
ORDER BY
    T.PROCESS_DATE DESC
FETCH FIRST 100 ROWS ONLY
```

### WITH句

```sql
WITH TARGET_DATA AS (
    SELECT
        T.TOOL_ID,
        T.PROCESS_DATE,
        T.STATUS_CODE
    FROM
        SAMPLE_TABLE T
    WHERE
        T.PROCESS_DATE >= :start_date
        AND T.PROCESS_DATE < :end_date
)
SELECT
    TOOL_ID,
    STATUS_CODE,
    COUNT(*) AS CNT
FROM
    TARGET_DATA
GROUP BY
    TOOL_ID,
    STATUS_CODE
ORDER BY
    TOOL_ID,
    STATUS_CODE
```

## Python Rules

- Oracle接続は `oracledb` を基本にする。
- 接続情報は環境変数やSettingsから取得する。
- SQLとパラメータは分離する。
- SQL文字列へユーザー入力を直接埋め込まない。
- DataFrame取得時は `params` を使用する。
- 接続とカーソルは `with` で管理する。
- SELECT専用の処理として実装し、更新処理は追加しない。

## Python Example

```python
from __future__ import annotations

import os
from datetime import datetime

import oracledb
import pandas as pd


def get_oracle_connection() -> oracledb.Connection:
    user = os.environ["ORACLE_USER"]
    password = os.environ["ORACLE_PASSWORD"]
    dsn = os.environ["ORACLE_DSN"]

    return oracledb.connect(
        user=user,
        password=password,
        dsn=dsn,
    )


def fetch_sample_data(
    tool_id: str,
    start_date: datetime,
    end_date: datetime,
) -> pd.DataFrame:
    sql = '''
        SELECT
            T.TOOL_ID,
            T.PROCESS_DATE,
            T.STATUS_CODE,
            T.CREATED_AT
        FROM
            SAMPLE_TABLE T
        WHERE
            T.TOOL_ID = :tool_id
            AND T.PROCESS_DATE >= :start_date
            AND T.PROCESS_DATE < :end_date
        ORDER BY
            T.PROCESS_DATE DESC
    '''

    params = {
        "tool_id": tool_id,
        "start_date": start_date,
        "end_date": end_date,
    }

    with get_oracle_connection() as conn:
        return pd.read_sql_query(sql, conn, params=params)
```

## Output Format

1. 目的
2. Oracle SELECT SQL
3. Pythonから実行する場合のコード
4. バインド変数の説明
5. 注意点

## Example Output

### 目的

指定した装置IDと処理期間に一致するOracle上の測定結果を取得する。

### Oracle SELECT SQL

```sql
SELECT
    T.TOOL_ID,
    T.PROCESS_DATE,
    T.STATUS_CODE,
    T.RESULT_VALUE
FROM
    MEASURE_RESULT T
WHERE
    T.TOOL_ID = :tool_id
    AND T.PROCESS_DATE >= :start_date
    AND T.PROCESS_DATE < :end_date
ORDER BY
    T.PROCESS_DATE DESC
```

### Python Code

```python
params = {
    "tool_id": tool_id,
    "start_date": start_date,
    "end_date": end_date,
}

with get_oracle_connection() as conn:
    df = pd.read_sql_query(sql, conn, params=params)
```

### 注意点

- `:tool_id`、`:start_date`、`:end_date` はバインド変数として渡す。
- `SELECT *` は避け、必要な列だけ取得する。
- 大量データになる場合は、期間条件や件数制限を追加する。
- このSkillでは更新系SQLは作成しない。
