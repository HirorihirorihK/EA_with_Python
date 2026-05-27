"""MT5/bat互換のH1エントリー候補生成入口。"""

from __future__ import annotations

import sys
from pathlib import Path


def main() -> None:
    """src配下のH1エントリー候補生成パイプラインを起動する。"""
    src_path = Path(__file__).resolve().parent / "src"
    if str(src_path) not in sys.path:
        sys.path.insert(0, str(src_path))

    from ea_py.pipelines.entry_pipeline import main as run_main

    run_main()


if __name__ == "__main__":
    main()
