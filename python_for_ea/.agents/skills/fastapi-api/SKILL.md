---
name: fastapi-api
description: FastAPIでAPIRouter、Pydanticスキーマ、Service、Repository、Depends、SQLAlchemy、APIテストを分離して実装・修正するときに使用する。
---

# FastAPI API Skill

## When to use

- FastAPIのエンドポイントを新規作成するとき
- 既存APIを修正するとき
- API層、Service層、Repository層を分離するとき
- SQLAlchemyを使用してDBアクセスを実装するとき
- ORMだけでは複雑になる処理を `sqlalchemy.text()` またはSQLファイルで実装するとき
- Pydanticのリクエスト・レスポンススキーマを作成するとき
- FastAPIの依存関係を `Depends` で整理するとき
- FastAPIのAPIテストを追加するとき

## 基本方針

- FastAPIはバックエンドAPIとして使用する。
- API層、Service層、Repository層を分離する。
- エンドポイント関数は薄く保つ。
- エンドポイント関数にDBアクセス、ファイルI/O、外部システム連携、重い処理を直接書かない。
- FastAPIでDBアクセスを行う場合は、原則としてSQLAlchemyを使用する。
- 単純なCRUDはSQLAlchemy ORMを優先する。
- 複雑なJOIN、集計、ウィンドウ関数、帳票用SQL、大量データ取得、N+1問題の回避でORM記述が複雑になる場合は、`sqlalchemy.text()` または `.sql` ファイルのSQLを使用する。
- 既存の設計、命名、ディレクトリ構成を優先する。
- 新規ファイルを作る場合は、既存の類似機能と同じ配置・命名に合わせる。

## Standard files

FastAPIの新規APIを追加する場合は、原則として以下のファイルを作成・修正する。

```text
src/app/api/routers/<feature>.py
src/app/schemas/<feature>.py
src/app/services/<feature>_service.py
src/app/repositories/<feature>_repository.py
src/app/api/dependencies.py
tests/api/test_<feature>.py
```

既存の構成がある場合は、新規構成を勝手に作らず、既存構成を優先する。

## Router

- `APIRouter` を使用する。
- `prefix`、`tags` を適切に設定する。
- ルーターは機能単位で分割する。
- エンドポイント関数では以下のみを行う。
  - リクエストデータの受け取り
  - `Depends` による依存関係の受け取り
  - Serviceの呼び出し
  - レスポンスの返却
- DB処理はRepository層に書く。
- 業務ロジックはService層に書く。

## Request / Response

- リクエストボディはPydanticモデルで定義する。
- レスポンスはPydanticモデルで定義する。
- 可能な限り `response_model` を指定する。
- DBモデル、DB行、内部オブジェクトをそのままAPIレスポンスとして返さない。
- APIレスポンスには、外部に公開してよい項目だけを含める。
- Pydantic v2を前提にする場合は、ORMオブジェクト変換に `ConfigDict(from_attributes=True)` と `model_validate()` を使用する。

## Service

- 業務ロジックはService層に書く。
- ServiceはRepositoryを呼び出して必要なデータを取得・保存する。
- ServiceはFastAPI固有の `Request` や `Response` に依存しすぎない。
- Service内で例外を握りつぶさない。
- 必要に応じて独自例外に変換して呼び出し元へ伝える。
- トランザクション境界をService層で管理する場合は、成功時commit、失敗時rollbackを明確にする。

## Repository

- DBアクセスはRepository層に書く。
- FastAPIでDBアクセスを行う場合は、原則としてSQLAlchemyを使用する。
- RepositoryはSQLAlchemyの `Session` またはDB接続を受け取る。
- Router層から直接SQLAlchemyのクエリを組み立てない。
- 単純なCRUD、主キー検索、単純な条件検索はSQLAlchemy ORMを優先する。
- SQL Server用RepositoryとOracleDB用Repositoryを分離する。
- OracleDBは参照専用とし、原則 `SELECT` のみ実行する。
- OracleDBに対して `INSERT` / `UPDATE` / `DELETE` / `MERGE` / `CREATE` / `ALTER` / `DROP` は実行しない。
- SQL Server用SQLとOracleDB用SQLを混在させない。
- 認証情報、接続文字列、ユーザー名、パスワードをコードに直書きしない。

## SQLAlchemy / SQL

- SQLAlchemyは可能な限り2.x系の記述スタイルを優先する。
- ORMモデルはDBテーブル構造を表すものとして扱い、APIレスポンスにはPydanticモデルを使用する。
- ORMのリレーションを使用する場合は、N+1問題に注意する。
- N+1問題が発生する可能性がある場合は、`selectinload()`、`joinedload()`、明示的な `join()`、またはSQLを使用する。
- 複雑なJOIN、集計、ウィンドウ関数、帳票用SQL、大量データ取得、性能要件が強い処理は、無理にORMだけで書かない。
- ORMで記述すると可読性や性能が悪くなる場合は、`sqlalchemy.text()` を使用してSQLを明示的に記述する。
- 長いSQL、再利用するSQL、DBごとに差があるSQLは `.sql` ファイルに分離する。
- `text()` を使用する場合も、ユーザー入力値をSQL文字列へ直接埋め込まない。
- `text()` では必ずバインドパラメータを使用する。
- 文字列連結でSQLを組み立てない。
- RepositoryはDBアクセス結果をServiceが扱いやすい形で返す。
- レスポンス生成時に遅延ロードが発生しないよう、Repository層で必要なデータを取得しきる。

## Dependency Injection

- FastAPIの `Depends` を使用する。
- Settings、SQLAlchemy `Session`、DB接続、Repository、Service は依存関係として注入できる形にする。
- SQLAlchemy `Session` はリクエスト単位で生成・終了する。
- Repository生成時にSQLAlchemy `Session` を渡し、Repository内部でグローバルなSessionを直接参照しない。
- テストで差し替えやすいように、依存関係は関数化する。

## Error Handling

- 入力不正は `HTTPException` で適切なHTTPステータスコードを返す。
- リソースが存在しない場合は `404` を返す。
- 内部例外の詳細をAPIレスポンスにそのまま返さない。
- 内部エラーは `logging` で記録する。
- クライアント向けレスポンスと内部ログを分離する。
- 必要に応じて独自例外をService層で発生させ、Router層でHTTPレスポンスへ変換する。

## Async / Sync

- `async def` と `def` は処理内容に応じて使い分ける。
- 同期DBドライバや同期SQLAlchemy Sessionを使う場合は、無理に `async def` にしない。
- ブロッキングI/Oを `async def` の中で直接実行しない。
- 長時間処理はAPIリクエスト内で完結させず、WorkerやJob Queueへの分離を検討する。

## Testing

- FastAPIのAPIテストでは `TestClient` を使用する。
- DB、外部API、ファイルI/Oはmockまたはdependency overrideで差し替える。
- Repositoryのテストでは、ORMで取得するケースと `text()` で取得するケースを必要に応じて分ける。
- 正常系、異常系、バリデーションエラー、権限エラーをテストする。
- dependency override を使用した場合は、テスト後に `app.dependency_overrides.clear()` を実行する。

## Output checklist

FastAPI APIを作成・修正する場合は、必要に応じて以下をセットで検討する。

1. Router
2. Schema
3. Service
4. Repository
5. SQLAlchemy Session / Dependency
6. ORMモデルまたはSQLファイル
7. Test
8. 実行・確認コマンド

## Example

### ORMを使用するRepository

```python
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.job import Job


class JobRepository:
    def __init__(self, session: Session) -> None:
        self._session = session

    def fetch_job(self, job_id: int) -> Job | None:
        stmt = select(Job).where(Job.job_id == job_id)
        return self._session.scalars(stmt).first()
```

### text() を使用するRepository

```python
from sqlalchemy import text
from sqlalchemy.orm import Session


class JobRepository:
    def __init__(self, session: Session) -> None:
        self._session = session

    def fetch_job_summary(self, job_id: int) -> dict[str, object] | None:
        stmt = text("""
            SELECT
                J.JOB_ID,
                J.STATUS,
                COUNT(S.SLOT_ID) AS SLOT_COUNT
            FROM dbo.SAW6_JOB_QUEUE AS J
            LEFT JOIN dbo.SAW6_JOB_QUEUE_SLOT AS S
                ON S.JOB_ID = J.JOB_ID
            WHERE J.JOB_ID = :job_id
            GROUP BY
                J.JOB_ID,
                J.STATUS
        """)
        row = self._session.execute(stmt, {"job_id": job_id}).mappings().first()
        return dict(row) if row is not None else None
```
