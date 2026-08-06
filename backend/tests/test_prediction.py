from datetime import date, timedelta

import pytest

from app.services import prediction
from app.services.checkin import QUESTION_POOL, _fallback_analysis, questions_for

TODAY = date(2026, 8, 6)


def series(start_kg: float, per_week: float, weeks: int, every_days: int = 3) -> list[tuple[date, float]]:
    """Synthetic weigh-ins on a clean linear trend."""
    points = []
    total_days = weeks * 7
    for offset in range(0, total_days + 1, every_days):
        day = TODAY - timedelta(days=total_days - offset)
        points.append((day, start_kg + per_week * (offset / 7)))
    return points


class TestInsufficientData:
    def test_no_entries_returns_reason(self):
        result = prediction.predict([], goal_kg=70, today=TODAY)
        assert result.has_enough_data is False
        assert result.reason
        assert result.goal_date is None

    def test_too_few_entries(self):
        entries = [(TODAY - timedelta(days=i * 3), 80.0) for i in range(2)]
        result = prediction.predict(entries, goal_kg=70, today=TODAY)
        assert result.has_enough_data is False
        assert "more weigh-in" in result.reason

    def test_entries_over_too_short_a_span(self):
        entries = [(TODAY - timedelta(days=i), 80.0 - i * 0.1) for i in range(5)]
        result = prediction.predict(entries, goal_kg=70, today=TODAY)
        assert result.has_enough_data is False


class TestTrendFitting:
    def test_detects_steady_loss(self):
        result = prediction.predict(series(85, -0.5, weeks=8), goal_kg=75, today=TODAY)
        assert result.has_enough_data
        assert result.trend_kg_per_week == pytest.approx(-0.5, abs=0.05)
        assert result.confidence == "high"
        assert result.r_squared > 0.95

    def test_detects_plateau(self):
        result = prediction.predict(series(85, 0.0, weeks=8), goal_kg=75, today=TODAY)
        assert result.plateau_detected is True
        assert any("plateau" in note.lower() for note in result.notes)

    def test_detects_gain(self):
        result = prediction.predict(series(80, 0.3, weeks=8), goal_kg=75, today=TODAY)
        assert result.trend_kg_per_week > 0
        assert result.goal_reachable is False

    def test_noisy_data_lowers_confidence(self):
        entries = series(85, -0.5, weeks=6)
        jittered = [
            (day, weight + (2.5 if index % 2 else -2.5)) for index, (day, weight) in enumerate(entries)
        ]
        clean = prediction.predict(entries, goal_kg=75, today=TODAY)
        noisy = prediction.predict(jittered, goal_kg=75, today=TODAY)
        assert noisy.r_squared < clean.r_squared


class TestGoalDate:
    def test_projects_a_reachable_goal(self):
        result = prediction.predict(series(85, -0.5, weeks=8), goal_kg=80, today=TODAY)
        assert result.goal_reachable
        assert result.goal_date > TODAY
        assert result.weeks_to_goal == pytest.approx(4, abs=3)

    def test_already_at_goal(self):
        result = prediction.predict(series(70, -0.2, weeks=8), goal_kg=75, today=TODAY)
        assert result.goal_reachable
        assert result.weeks_to_goal == 0

    def test_goal_beyond_horizon_is_flagged_unreachable(self):
        result = prediction.predict(series(120, -0.02, weeks=10), goal_kg=70, today=TODAY)
        assert result.goal_reachable is False
        assert result.goal_date is None

    def test_flat_trend_falls_back_to_planned_pace(self):
        result = prediction.predict(
            series(85, 0.0, weeks=8), goal_kg=80, weekly_goal_kg=0.5, today=TODAY
        )
        # Date is offered, but explicitly labelled as a plan rather than a measurement.
        assert result.goal_reachable is False
        assert result.goal_date is not None
        assert any("chosen pace" in note for note in result.notes)


class TestSafetyCaps:
    def test_projection_rate_is_capped_at_the_clinical_ceiling(self):
        """A 2 kg/week crash trend must not be projected forward at that rate."""
        result = prediction.predict(series(110, -2.0, weeks=6), goal_kg=80, today=TODAY)
        assert result.trend_kg_per_week < -1.0  # the measured trend is reported honestly
        assert any("faster than 1 kg" in note for note in result.notes)

        first, second = result.weekly_projection[0], result.weekly_projection[1]
        weekly_drop = first.weight_kg - second.weight_kg
        assert weekly_drop <= 1.01  # but the projection uses the capped rate

    def test_projection_never_goes_below_healthy_bmi(self):
        # 170 cm -> BMI 18.5 floor is about 53.5 kg
        result = prediction.predict(
            series(60, -1.0, weeks=10), goal_kg=45, height_cm=170, today=TODAY
        )
        floor = 18.5 * 1.7 * 1.7
        assert all(point.weight_kg >= floor - 0.01 for point in result.monthly_projection)

    def test_goal_below_healthy_bmi_is_flagged(self):
        result = prediction.predict(
            series(60, -0.4, weeks=8), goal_kg=45, height_cm=170, today=TODAY
        )
        assert any("BMI" in note for note in result.notes)

    def test_projection_never_returns_negative_weight(self):
        result = prediction.predict(series(55, -1.0, weeks=12), goal_kg=40, today=TODAY)
        assert all(point.weight_kg > 30 for point in result.weekly_projection)


class TestProjectionShape:
    def test_weekly_and_monthly_horizons(self):
        result = prediction.predict(series(90, -0.4, weeks=10), goal_kg=70, today=TODAY)
        assert len(result.weekly_projection) <= 12
        assert len(result.monthly_projection) <= 6
        assert result.weekly_projection[0].day == TODAY + timedelta(days=7)
        assert result.monthly_projection[0].day == TODAY + timedelta(days=30)

    def test_remaining_and_lost_are_derived_from_the_anchor(self):
        entries = series(90, -0.5, weeks=8)
        result = prediction.predict(entries, goal_kg=75, start_kg=95, today=TODAY)
        assert result.start_kg == 95
        assert result.lost_kg == pytest.approx(95 - entries[-1][1], abs=0.1)
        assert result.remaining_kg == pytest.approx(entries[-1][1] - 75, abs=0.1)

    def test_as_dict_is_json_safe(self):
        result = prediction.predict(series(90, -0.5, weeks=8), goal_kg=75, today=TODAY)
        payload = result.as_dict()
        assert isinstance(payload["goal_date"], str)
        assert isinstance(payload["weekly_projection"][0]["date"], str)
        assert isinstance(payload["notes"], list)


class TestSmoothing:
    def test_ewma_resists_a_single_spike(self):
        steady = [80.0] * 10
        spiked = steady[:-1] + [84.0]
        assert prediction._ewma(spiked) < 81.5

    def test_ewma_of_empty_is_zero(self):
        assert prediction._ewma([]) == 0.0


class TestCheckInQuestions:
    def test_always_includes_the_three_scales(self):
        ids = {q["id"] for q in questions_for(TODAY)}
        assert {"mood", "energy", "adherence"} <= ids

    def test_returns_five_questions(self):
        assert len(questions_for(TODAY)) == 5

    def test_rotates_across_days(self):
        seen = set()
        for offset in range(len(QUESTION_POOL)):
            day = TODAY + timedelta(days=offset)
            seen.update(q["id"] for q in questions_for(day))
        # rotation should surface more than just the three fixed questions
        assert len(seen) > 3

    def test_every_question_is_well_formed(self):
        for question in QUESTION_POOL:
            assert question["id"] and question["text"]
            assert question["type"] in {"scale", "number", "choice", "text"}
            if question["type"] == "choice":
                assert question["options"]
            if question["type"] == "scale":
                assert question["min"] < question["max"]


class TestCheckInFallback:
    def _metrics(self, **overrides):
        base = {
            "current_weight_kg": 82.0,
            "trend_kg_per_week": -0.4,
            "days_logged_last_7": 5,
            "steps_avg_7d": 9000,
            "step_target": 10000,
            "water_ml_today": 2000,
            "water_target_ml": 2500,
            "plateau_detected": False,
        }
        base.update(overrides)
        return base

    def test_always_produces_a_recommendation(self):
        result = _fallback_analysis(self._metrics())
        assert result["summary"]
        assert 1 <= len(result["recommendations"]) <= 3

    def test_flags_thin_logging(self):
        result = _fallback_analysis(self._metrics(days_logged_last_7=1))
        assert any("Log your meals" in r for r in result["recommendations"])

    def test_handles_no_weight_data(self):
        result = _fallback_analysis(self._metrics(current_weight_kg=None))
        assert "no trend" in result["summary"].lower()

    def test_never_recommends_a_calorie_number(self):
        """The offline path must not invent targets that could bypass the clinical floors."""
        for overrides in [{}, {"days_logged_last_7": 0}, {"plateau_detected": True}, {"steps_avg_7d": 2000}]:
            result = _fallback_analysis(self._metrics(**overrides))
            text = result["summary"] + " ".join(result["recommendations"])
            assert "kcal" not in text.lower()
            assert "calorie" not in text.lower()


class TestRiskDetection:
    """The detector gates every AI path, so its coverage is a safety property."""

    @pytest.mark.parametrize("text", [
        "I made myself throw up after dinner again",
        "threw up my lunch",
        "I've been throwing up most nights",
        "took laxatives last night",
        "I have been skipping meals to speed things up",
        "I havent eaten in two days",
        "haven't eaten since Tuesday",
        "I hate my body",
        "i hate myself so much",
        "thinking I would be better off dead",
        "I want to kill myself",
        "cutting myself again",
        "I think my eating disorder is back",
        "chew and spit is the only way I cope",
    ])
    def test_flags_risk_language(self, text):
        from app.services.coach import has_risk_language
        assert has_risk_language(text) is True

    @pytest.mark.parametrize("text", [
        "I walked after dinner and felt good",
        "Had a big lunch, felt full afterwards",
        "My weight is stuck this week, any ideas?",
        "I want to lose 5 kg before the wedding",
        "Struggled with portion sizes at the restaurant",
        "Feeling tired but pushing through the gym sessions",
    ])
    def test_leaves_ordinary_language_alone(self, text):
        from app.services.coach import has_risk_language
        assert has_risk_language(text) is False
