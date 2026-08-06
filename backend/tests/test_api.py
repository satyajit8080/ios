import os
from datetime import date

if not os.environ.get("DATABASE_URL"):
    os.environ["DATABASE_URL"] = "sqlite+pysqlite:///./test.db"

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services.metrics import bmi, bmi_category, calorie_target, level_for_xp
from app.services.streaks import streaks
from tests.conftest import requires_db

client = TestClient(app)


def test_health_endpoint_shape():
    resp = client.get("/health")
    assert resp.status_code in (200, 503)
    assert set(resp.json()) == {"api", "database", "redis"}


def test_bmi_and_category():
    assert bmi(80, 180) == 24.7
    assert bmi_category(24.7) == "Healthy"
    assert bmi_category(31) == "Obese"
    assert bmi(None, 180) is None


def test_calorie_target_never_below_floor():
    low = calorie_target(50, 155, 25, "female", "sedentary", 1.0)
    assert low >= 1200
    male = calorie_target(60, 170, 30, "male", "sedentary", 1.0)
    assert male >= 1500


def test_calorie_target_caps_weekly_loss():
    aggressive = calorie_target(90, 180, 30, "male", "moderate", 3.0)
    capped = calorie_target(90, 180, 30, "male", "moderate", 1.0)
    assert aggressive == capped


def test_streaks_current_and_longest():
    today = date(2025, 3, 10)
    days = [date(2025, 3, 8), date(2025, 3, 9), date(2025, 3, 10), date(2025, 2, 1)]
    current, longest = streaks(days, today)
    assert current == 3
    assert longest == 3


def test_streaks_empty():
    assert streaks([], date(2025, 3, 10)) == (0, 0)


def test_levels_increase_with_xp():
    assert level_for_xp(0)[0] == 1
    assert level_for_xp(100)[0] == 2
    assert level_for_xp(5000)[0] > level_for_xp(1000)[0]


def test_protected_route_requires_token():
    assert client.get("/api/v1/dashboard").status_code == 403


@pytest.mark.parametrize("path", ["/api/v1/weight", "/api/v1/steps/stats", "/api/v1/coach/history"])
def test_endpoints_registered(path):
    assert client.get(path).status_code in (401, 403)


# --- Prediction and check-in endpoints ---------------------------------------


@requires_db
def test_prediction_endpoint_reports_insufficient_data(client, auth_headers):
    response = client.get("/api/v1/weight/prediction", headers=auth_headers)
    assert response.status_code == 200
    body = response.json()
    assert body["has_enough_data"] is False
    assert body["reason"]
    assert body["goal_date"] is None


@requires_db
def test_prediction_endpoint_projects_after_enough_weigh_ins(client, auth_headers):
    from datetime import date, timedelta

    today = date.today()
    for index in range(12):
        day = today - timedelta(days=(11 - index) * 3)
        client.post(
            "/api/v1/weight",
            headers=auth_headers,
            json={"weight_kg": 90 - index * 0.25, "recorded_on": day.isoformat()},
        )

    client.patch("/api/v1/users/me", headers=auth_headers, json={"goal_weight_kg": 80})

    response = client.get("/api/v1/weight/prediction", headers=auth_headers)
    assert response.status_code == 200
    body = response.json()
    assert body["has_enough_data"] is True
    assert body["trend_kg_per_week"] < 0
    assert body["weekly_projection"]
    # projection must never dip below the goal it is heading toward
    assert all(point["weight_kg"] >= body["goal_kg"] - 0.1 for point in body["weekly_projection"])


@requires_db
def test_checkin_today_returns_questions(client, auth_headers):
    response = client.get("/api/v1/checkin/today", headers=auth_headers)
    assert response.status_code == 200
    body = response.json()
    assert body["completed"] is False
    assert len(body["questions"]) == 5
    assert {"mood", "energy", "adherence"} <= {q["id"] for q in body["questions"]}
    assert "calorie_target" in body["metrics"]


@requires_db
def test_checkin_submit_and_history(client, auth_headers):
    payload = {"answers": {"mood": 4, "energy": 3, "adherence": 5, "win": "Walked after dinner"}}
    response = client.post("/api/v1/checkin", headers=auth_headers, json=payload)
    assert response.status_code == 200
    body = response.json()
    assert body["summary"]
    assert body["recommendations"]
    assert body["mood"] == 4

    today = client.get("/api/v1/checkin/today", headers=auth_headers).json()
    assert today["completed"] is True
    assert today["streak"] >= 1

    history = client.get("/api/v1/checkin", headers=auth_headers).json()
    assert history["streak"] >= 1
    assert len(history["entries"]) == 1


@requires_db
def test_checkin_resubmission_overwrites_same_day(client, auth_headers):
    client.post("/api/v1/checkin", headers=auth_headers, json={"answers": {"mood": 2, "energy": 2, "adherence": 2}})
    client.post("/api/v1/checkin", headers=auth_headers, json={"answers": {"mood": 5, "energy": 5, "adherence": 5}})

    history = client.get("/api/v1/checkin", headers=auth_headers).json()
    assert len(history["entries"]) == 1
    assert history["entries"][0]["mood"] == 5


@requires_db
def test_checkin_rejects_future_date(client, auth_headers):
    from datetime import date, timedelta

    future = (date.today() + timedelta(days=3)).isoformat()
    response = client.post(
        "/api/v1/checkin",
        headers=auth_headers,
        json={"answers": {"mood": 3, "energy": 3, "adherence": 3}, "recorded_on": future},
    )
    assert response.status_code == 400


@requires_db
def test_checkin_risk_language_routes_to_support(client, auth_headers):
    """Disordered-eating language must bypass the AI and return support, never targets."""
    response = client.post(
        "/api/v1/checkin",
        headers=auth_headers,
        json={
            "answers": {
                "mood": 1,
                "energy": 1,
                "adherence": 1,
                "biggest_hurdle": "I made myself throw up after dinner again",
            }
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["provider"] == "safety"
    assert "988" in body["summary"]
    for text in [body["summary"]] + body["recommendations"]:
        assert "kcal" not in text.lower()
