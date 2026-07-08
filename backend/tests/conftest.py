import os
import tempfile

# Isolate the test DB before the app module is imported.
os.environ["CAREER_AI_DB"] = os.path.join(tempfile.gettempdir(), "career_ai_test.db")
os.environ["CAREER_AI_ENV"] = "development"
os.environ["CAREER_AI_ADMIN_TOKEN"] = "test-admin-token"
os.environ["CAREER_AI_OPEN_TALENTS"] = "0"  # tests validate the gated path explicitly

import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def client():
    # fresh DB per test
    if os.path.exists(os.environ["CAREER_AI_DB"]):
        os.remove(os.environ["CAREER_AI_DB"])
    # reset the in-memory rate limiter so tests don't trip it across cases
    from app import security
    security._hits.clear()
    from app.main import app
    with TestClient(app) as c:
        yield c


def register(client, email, role="seeker", consent=True, name="T", pw="password123"):
    return client.post("/auth/register", json={
        "email": email, "password": pw, "name": name, "role": role, "consent": consent})
