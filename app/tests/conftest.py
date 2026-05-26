"""Pytest fixtures backed by a real MariaDB (provided as a CI service container).

Locally, set DB_HOST/DB_PORT/DB_USER/DB_PASSWORD/DB_NAME before invoking pytest,
or run via the GitHub Actions workflow.
"""

import os
import sys
from pathlib import Path

import pymysql
import pytest

# Ensure `import main` / `import migrate` works from within app/tests/.
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from main import create_app  # noqa: E402
from migrate import SCHEMA  # noqa: E402


def _db_kwargs():
    return dict(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "3306")),
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        database=os.environ["DB_NAME"],
        autocommit=True,
    )


@pytest.fixture(scope="session", autouse=True)
def _prepare_schema():
    """Create the tasks table once for the whole test session."""
    conn = pymysql.connect(**_db_kwargs())
    with conn, conn.cursor() as cur:
        cur.execute(SCHEMA)
    yield


@pytest.fixture
def client():
    """Fresh test client with an empty `tasks` table."""
    conn = pymysql.connect(**_db_kwargs())
    with conn, conn.cursor() as cur:
        cur.execute("TRUNCATE TABLE tasks")

    app = create_app()
    app.testing = True
    with app.test_client() as c:
        yield c
