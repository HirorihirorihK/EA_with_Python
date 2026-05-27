---
applyTo: "**/oracle/**/*.py,**/repositories/**/*oracle*.py,**/db/**/*oracle*.py,**/sql/oracle/**/*.sql"
---

# OracleDB Instructions

- OracleDB は外部システムからデータを取得するための参照専用DBとして扱う。
- OracleDB に対しては原則 `SELECT` のみ実行する。
- `INSERT` / `UPDATE` / `DELETE` / `MERGE` / `CREATE` / `ALTER` / `DROP` は実行しない。
- OracleDB用SQLは `sql/oracle/` または `docs/sql/oracle/` に分離する。
- SQL Server用SQLとOracleDB用SQLを混在させない。
- OracleDB用RepositoryとSQL Server用Repositoryを分離する。
- OracleDBから取得したデータを加工・保存する場合、保存先はSQL Server側Repositoryで扱う。
- 認証情報、接続文字列、ユーザー名、パスワードをコードに直書きしない。
- パラメータ付きSQLを使用し、文字列連結でSQLを組み立てない。