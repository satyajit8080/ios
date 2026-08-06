"""Shared test fixtures.

The models use PostgreSQL-specific column types (JSONB, native UUID), so the
integration tests need a real PostgreSQL instance rather than SQLite. CI provides
one as a service container; locally these tests skip cleanly if it isn't there.
Pure unit tests in this suite have no such dependency and always run.
"""

import os
import uuid

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

TEST_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL",
    os.environ.get("DATABASE_URL", "postgresql+psycopg://awlc:awlc@localhost:5432/awlc_test"),
)


def _postgres_available() -> bool:
    if not TEST_DATABASE_URL.startswith("postgresql"):
        return False
    try:
        engine = create_engine(TEST_DATABASE_URL, pool_pre_ping=True)
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        engine.dispose()
        return True
    except Exception:
        return False


POSTGRES = _postgres_available()

requires_db = pytest.mark.skipif(
    not POSTGRES,
    reason="Integration tests need PostgreSQL (models use JSONB and native UUID columns).",
)


@pytest.fixture(scope="session")
def engine():
    if not POSTGRES:
        pytest.skip("PostgreSQL unavailable")

    os.environ["DATABASE_URL"] = TEST_DATABASE_URL
    from app.models import Base

    engine = create_engine(TEST_DATABASE_URL)
    with engine.connect() as conn:
        conn.execute(text("CREATE EXTENSION IF NOT EXISTS pgcrypto"))
        conn.commit()
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    yield engine
    Base.metadata.drop_all(engine)
    engine.dispose()


@pytest.fixture
def db_session(engine):
    Session = sessionmaker(bind=engine, expire_on_commit=False)
    session = Session()
    yield session
    session.close()


@pytest.fixture
def client(engine):
    """TestClient wired to the test database."""
    from app.db.session import get_db
    from app.main import app

    Session = sessionmaker(bind=engine, expire_on_commit=False)

    def override_get_db():
        session = Session()
        try:
            yield session
        finally:
            session.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture
def auth_headers(client):
    """Registers a fresh user per test and returns its bearer header."""
    email = f"test-{uuid.uuid4().hex[:12]}@example.com"
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": "correct-horse-battery", "full_name": "Test Person"},
    )
    assert response.status_code in (200, 201), response.text
    token = response.json()["tokens"]["access_token"]

    headers = {"Authorization": f"Bearer {token}"}
    # Give the user the profile fields the metrics and prediction code expect.
    client.patch(
        "/api/v1/users/me",
        headers=headers,
        json={
            "gender": "female",
            "birth_date": "1992-04-11",
            "height_cm": 168,
            "activity_level": "moderate",
            "start_weight_kg": 90,
            "goal_weight_kg": 75,
            "weekly_goal_kg": 0.5,
            "onboarded": True,
        },
    )
    return headers
