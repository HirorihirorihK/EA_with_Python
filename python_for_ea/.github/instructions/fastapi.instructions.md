---
applyTo: "**/api/**/*.py,**/routers/**/*.py,**/routes/**/*.py,**/schemas/**/*.py,**/services/**/*.py,**/repositories/**/*.py,**/main.py,**/app.py"
---

# FastAPI Instructions

## 基本方針

- FastAPI はバックエンドAPIとして使用する。
- API層、Service層、Repository層を分離する。
- FastAPIでDBアクセスを行う場合は、原則としてSQLAlchemyを使用する。
- 単純なCRUDはSQLAlchemy ORMを優先し、複雑なJOIN・集計・N+1問題の回避でORM記述が複雑になる場合は、`sqlalchemy.text()` または `.sql` ファイルのSQLを使用する。
- エンドポイント関数にビジネスロジック、DBアクセス、ファイルI/Oを直接書かない。
- 既存の設計、命名、ディレクトリ構成を優先する。
- 新規ファイルを作成する場合は、既存の類似機能と同じ配置・命名に合わせる。
- 詳細なフォルダ構成は `docs/architecture/folder-structure.md` を参照する。

## 標準フォルダ構成

FastAPI関連コードは、原則として以下の配置を優先する。

```text
src/app/main.py
src/app/api/dependencies.py
src/app/api/routers/<feature>.py
src/app/schemas/<feature>.py
src/app/services/<feature>_service.py
src/app/repositories/<feature>_repository.py
tests/api/test_<feature>.py
```

既存の構成がある場合は、新規構成を勝手に作らず、既存構成を優先する。

## 構成

- ルーティングは `APIRouter` を使用する。
- ルーターは機能単位で分割する。
- `main.py` または `app.py` では FastAPI アプリ作成、middleware、router登録を中心に書く。
- 共通依存関係は `dependencies.py` または `api/dependencies.py` に分離する。
- リクエスト・レスポンスのPydanticモデルは `schemas.py` または `schemas/` に分離する。
- 業務ロジックは `services/` に分離する。
- DBアクセスは `repositories/` に分離する。

## Router

- `APIRouter` を使用する。
- `prefix`、`tags` を適切に設定する。
- ルーターは機能単位で分割する。
- エンドポイント関数は薄く保つ。
- エンドポイントでは以下のみを行う。
  - リクエストデータの受け取り
  - `Depends` による依存関係の受け取り
  - Serviceの呼び出し
  - レスポンスの返却
- DB処理はRepository層に書く。
- 業務ロジックはService層に書く。
- ファイルI/O、外部システム連携、重い処理をエンドポイントに直接書かない。

## Request / Response

- リクエストボディは Pydantic モデルで定義する。
- レスポンスは Pydantic モデルで定義する。
- 可能な限り `response_model` を指定する。
- DBモデル、DB行、内部オブジェクトをそのままAPIレスポンスとして返さない。
- APIレスポンスには、外部に公開してよい項目だけを含める。
- 入力値の制約は、可能な範囲でPydantic側に定義する。
- Pydantic v2 を前提にする場合は、ORMオブジェクト変換に `ConfigDict(from_attributes=True)` と `model_validate()` を使用する。

## Service

- 業務ロジックはService層に書く。
- ServiceはRepositoryを呼び出して必要なデータを取得・保存する。
- ServiceはFastAPI固有の `Request` や `Response` に依存しすぎない。
- Serviceはテストしやすいように、入力と出力を明確にする。
- Service内で例外を握りつぶさない。
- 必要に応じて独自例外に変換して呼び出し元へ伝える。

## Repository

- DBアクセスはRepository層に書く。
- DBアクセスは既存のDB接続クラス・Repository層を優先する。
- FastAPIでDBアクセスを行う場合は、原則としてSQLAlchemyを使用する。
- SQLAlchemyは可能な限り2.x系の記述スタイルを優先する。
- RepositoryはSQLAlchemyの `Session` またはDB接続を受け取り、Router層から直接DBへアクセスさせない。
- SQL Server用RepositoryとOracleDB用Repositoryを分離する。
- SQL Server と OracleDB の接続処理、Repository、SQLファイルは分離する。
- OracleDBは参照専用とし、原則 `SELECT` のみ実行する。
- OracleDBに対して `INSERT` / `UPDATE` / `DELETE` / `MERGE` / `CREATE` / `ALTER` / `DROP` は実行しない。
- SQL Serverへの保存・更新・削除はSQL Server用Repositoryで行う。
- SQLは可能な限り `.sql` ファイルに分離する。
- SQL Server用SQLとOracleDB用SQLを混在させない。
- 文字列連結でSQLを組み立てない。
- パラメータ付きSQLを使用する。
- 認証情報、接続文字列、ユーザー名、パスワードをコードに直書きしない。

## SQLAlchemy / SQL

- 単純なCRUD、主キー検索、単純な条件検索はSQLAlchemy ORMを優先する。
- ORMモデルはDBテーブル構造を表すものとして扱い、APIレスポンスにはPydanticモデルを使用する。
- ORMのリレーションを使用する場合は、N+1問題に注意する。
- N+1問題が発生する可能性がある場合は、以下のいずれかで対策する。
  - `selectinload()` を使用する。
  - `joinedload()` を使用する。
  - 明示的な `join()` を使用する。
  - `sqlalchemy.text()` または `.sql` ファイルに分離したSQLを使用する。
- 複雑なJOIN、集計、ウィンドウ関数、帳票用SQL、大量データ取得、性能要件が強い処理は、無理にORMだけで書かない。
- ORMで記述すると可読性や性能が悪くなる場合は、`sqlalchemy.text()` を使用してSQLを明示的に記述する。
- 長いSQL、再利用するSQL、DBごとに差があるSQLは `.sql` ファイルに分離する。
- `text()` を使用する場合も、ユーザー入力値をSQL文字列へ直接埋め込まない。
- `text()` では必ずバインドパラメータを使用する。
- RepositoryはDBアクセス結果をServiceが扱いやすい形で返す。
- レスポンス生成時に遅延ロードが発生しないよう、Repository層で必要なデータを取得しきる。
- トランザクション境界はService層またはRepository層で明確に管理し、成功時はcommit、失敗時はrollbackする。

### ORMを優先する例

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

### text() を使用する例

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

## Dependency Injection

- FastAPI の `Depends` を使用する。
- Settings、SQLAlchemy `Session`、DB接続、Repository、Service は依存関係として注入できる形にする。
- 認証・認可・DB接続・設定取得などの共通処理は依存関係として共通化する。
- テストで差し替えやすいように、依存関係は関数化する。
- グローバル変数に直接依存する実装を避ける。
- SQLAlchemy `Session` はリクエスト単位で生成・終了する。
- Repository生成時にSQLAlchemy `Session` を渡し、Repository内部でグローバルなSessionを直接参照しない。

## Error Handling

- 入力不正は `HTTPException` で適切なHTTPステータスコードを返す。
- リソースが存在しない場合は `404` を返す。
- 未認証は `401`、権限不足は `403` を返す。
- 内部例外の詳細をAPIレスポンスにそのまま返さない。
- 内部エラーは `logging` で記録する。
- クライアント向けレスポンスと内部ログを分離する。
- 例外を握りつぶさない。
- 必要に応じて独自例外をService層で発生させ、Router層でHTTPレスポンスへ変換する。

## Async / Sync

- `async def` と `def` は処理内容に応じて使い分ける。
- 同期DBドライバを使う場合は、無理に `async def` にしない。
- ブロッキングI/Oを `async def` の中で直接実行しない。
- 長時間処理はAPIリクエスト内で完結させず、WorkerやJob Queueへの分離を検討する。
- CSV出力待ち、ログ検索、重い集計、外部プログラム待ちなどはAPIから分離する。

## Testing

- FastAPI のAPIテストでは `TestClient` を使用する。
- DB、外部API、ファイルI/Oはmockまたはdependency overrideで差し替える。
- 正常系、異常系、バリデーションエラー、権限エラーをテストする。
- Integration Test は `@pytest.mark.integration` を付けて通常実行から分離する。
- テスト名は `test_<対象>_<条件>_<期待結果>` にする。
- dependency override を使用した場合は、テスト後に `app.dependency_overrides.clear()` を実行する。

## 作成・修正時の出力方針

FastAPI APIを作成・修正する場合は、必要に応じて以下をセットで検討する。

1. Router
2. Schema
3. Service
4. Repository
5. Dependency
6. Test
7. 関連するSQLファイル
8. 実行・確認コマンド

## Example

### Router

```python
from fastapi import APIRouter, Depends, HTTPException, status

from app.api.dependencies import get_job_service
from app.schemas.job import JobResponse
from app.services.job_service import JobService

router = APIRouter(prefix="/jobs", tags=["jobs"])


@router.get("/{job_id}", response_model=JobResponse)
def get_job(
    job_id: int,
    service: JobService = Depends(get_job_service),
) -> JobResponse:
    job = service.get_job(job_id)

    if job is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Job not found",
        )

    return JobResponse.model_validate(job)
```

### Schema

```python
from pydantic import BaseModel, ConfigDict


class JobResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    job_id: int
    status: str
```

### Dependency

```python
from collections.abc import Generator

from fastapi import Depends
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.repositories.job_repository import JobRepository
from app.services.job_service import JobService

engine = create_engine("mssql+pyodbc://...", pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


def get_db_session() -> Generator[Session, None, None]:
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


def get_job_repository(
    session: Session = Depends(get_db_session),
) -> JobRepository:
    return JobRepository(session=session)


def get_job_service(
    repository: JobRepository = Depends(get_job_repository),
) -> JobService:
    return JobService(repository=repository)
```

### Service

```python
from app.repositories.job_repository import JobRepository


class JobService:
    def __init__(self, repository: JobRepository) -> None:
        self._repository = repository

    def get_job(self, job_id: int) -> object | None:
        return self._repository.fetch_job(job_id)
```

### Test

```python
from fastapi.testclient import TestClient

from app.api.dependencies import get_job_service
from app.main import app


class FakeJobService:
    def get_job(self, job_id: int) -> dict[str, int | str]:
        return {"job_id": job_id, "status": "DONE"}


def test_get_job_valid_id_returns_job():
    app.dependency_overrides[get_job_service] = lambda: FakeJobService()

    try:
        client = TestClient(app)

        response = client.get("/jobs/1")

        assert response.status_code == 200
        assert response.json() == {"job_id": 1, "status": "DONE"}
    finally:
        app.dependency_overrides.clear()
```
