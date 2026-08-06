# AI Weight Loss Coach

A production-shaped weight-loss app: SwiftUI client on iOS 18, FastAPI + PostgreSQL + Redis backend, AI coaching with OpenAI primary and Anthropic fallback, StoreKit 2 subscriptions, HealthKit sync, and a self-contained admin panel.

```
awlc/
├── backend/                 FastAPI service, Alembic migrations, worker, seed data, tests
│   ├── app/
│   │   ├── api/v1/          80 routes across auth, tracking, nutrition, coach, check-in, billing, admin
│   │   ├── core/            settings, security, redis, dependencies
│   │   ├── db/              engine, session, declarative base
│   │   ├── models/          24 SQLAlchemy tables
│   │   ├── schemas/         Pydantic request/response contracts
│   │   ├── services/        metrics, prediction, check-in, AI gateway, coach memory, meal planner,
│   │   │                    gamification, push, billing
│   │   ├── worker/          APScheduler reminder engine
│   │   └── static/admin.html
│   ├── alembic/
│   └── tests/
├── ios/                     XcodeGen project + SwiftUI app
│   └── AIWeightLossCoach/
│       ├── App/             entry point, root routing, tab shell
│       ├── Core/            API client, session, HealthKit, StoreKit, push, theme, components
│       ├── Models/          Codable mirrors of every backend schema
│       ├── Features/        Auth, Dashboard, Weight, Prediction, Steps, Water, Coach, CheckIn,
│       │                    Nutrition, Habits, Challenges, Analytics, Premium, Settings
│       └── Resources/       Info.plist, entitlements, StoreKit config, assets
├── deploy/                  Caddyfile, deploy.sh, backup.sh
├── docker-compose.yml       local stack (db, redis, api, worker)
├── docker-compose.prod.yml  production stack behind Caddy with TLS
└── .github/workflows/       CI (lint, migrate, pytest, docker, xcodebuild) and deploy
```

## Running the backend locally

```bash
cd backend
cp .env.example .env          # fill in SECRET_KEY, OPENAI_API_KEY, ANTHROPIC_API_KEY
cd ..
docker compose up --build
```

That brings up PostgreSQL, Redis, the API on `http://localhost:8000`, and the reminder worker. Migrations and seed data run automatically on start.

- API docs: `http://localhost:8000/docs`
- Health check: `http://localhost:8000/health`
- Admin panel: `http://localhost:8000/admin` (sign in with the seeded admin account from `.env`)

Without Docker:

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
alembic upgrade head
python -m app.seed
uvicorn app.main:app --reload
python -m app.worker.scheduler        # separate shell, optional locally
```

Tests:

```bash
cd backend && pytest -q      # 39 tests
ruff check app/              # lint
```

66 tests. The DB-backed integration tests need PostgreSQL and skip cleanly without it;
the rest (prediction maths, safety gating, metrics) run anywhere. To run everything
locally, point `TEST_DATABASE_URL` at a scratch database:

```bash
TEST_DATABASE_URL=postgresql+psycopg://awlc:awlc@localhost:5432/awlc_test pytest -q
```

## Required environment variables

| Variable | Purpose |
| --- | --- |
| `SECRET_KEY` | JWT signing. Generate with `openssl rand -hex 32`. |
| `DATABASE_URL` | PostgreSQL DSN. |
| `REDIS_URL` | Cache, rate limits, dashboard cache. |
| `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` | Coach, meal planner, food vision. Set `AI_PRIMARY` to `openai` or `anthropic`. |
| `APPLE_BUNDLE_ID`, `APPLE_TEAM_ID` | Sign in with Apple and App Store notification verification. |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | FCM v1 push credentials. |
| `SMTP_*` | Password reset email delivery. |
| `ADMIN_EMAIL`, `ADMIN_PASSWORD` | Seeded admin account. |

## Running the iOS app

```bash
brew install xcodegen
cd ios
xcodegen generate
open AIWeightLossCoach.xcodeproj
```

Before the first run:

1. Replace `Resources/GoogleService-Info.plist` with the real file from your Firebase project.
2. Set your signing team, and enable HealthKit, Push Notifications, Sign in with Apple, and In-App Purchase capabilities.
3. Point `API_BASE_URL` in `Resources/Info.plist` at your backend (`http://localhost:8000/api/v1` for the simulator).
4. For purchase testing, select `Resources/Products.storekit` in the scheme's StoreKit Configuration.

The app requires a physical device for step data; the simulator has no HealthKit step samples.

## Deployment

CI runs on every push: ruff, Alembic migration check, pytest against live Postgres and Redis, a Docker build pushed to GHCR, and an iOS build on `macos-15`. On a green run against `main`, the deploy workflow rsyncs the compose files to the host and runs `deploy/deploy.sh`, which pulls the new image, restarts the stack, polls `/health` for 150 seconds, and rolls back to the previous tag if the check fails.

Production expects `deploy/Caddyfile` to hold your domain; Caddy handles TLS automatically. `deploy/backup.sh` belongs in a nightly cron and keeps 14 days of `pg_dump` archives.

## Weight projection

`GET /weight/prediction` fits a trend over the recent 90-day window and projects
forward. It is deliberately conservative:

- Refuses to project at all below 4 weigh-ins spanning 10 days, returning a reason
  instead. A projection built on three readings mostly measures water weight.
- Anchors on an exponentially weighted mean rather than the latest reading, so one
  heavy morning does not move the goal date.
- Reports the measured trend honestly but **projects** at no more than 1 kg/week,
  the same clinical ceiling the calorie targets use.
- Never projects below a BMI of 18.5, and flags goals set beneath it.
- Grades its own confidence from entry count, span and r², and says so in the UI.

## The prediction engine

`GET /weight/prediction` projects a trajectory toward the goal weight. It deliberately
refuses to extrapolate from thin data: fewer than four weigh-ins, or a span under ten
days, returns `has_enough_data: false` with a reason instead of a number. A projection
built on three readings mostly measures water weight.

Mechanics: exponentially weighted mean for the anchor (so one bad morning doesn't move
the whole line), ordinary least squares over a 90-day window for the slope, and r²
plus entry count feeding a low/moderate/high confidence tier. The measured trend is
reported honestly even when it's alarming, but the *projection* is capped at 1 kg per
week and floored at a BMI of 18.5, so the app can never draw a line toward a dangerous
weight.

## The daily check-in

`GET /checkin/today` returns five questions — three fixed scales plus two that rotate
by day so it doesn't become the same form every morning — alongside the metrics the
analysis will reason over. `POST /checkin` submits answers and returns a summary,
two or three concrete recommendations, and a focus phrase.

The AI writes the analysis under a constrained prompt (no sub-floor calorie advice, no
moralising about food, no reading fat gain into day-to-day noise). Two guards sit around
it: risk language in free-text answers routes to a fixed support response instead of the
model, and if the AI is unreachable the endpoint falls back to a deterministic analysis
computed straight from the numbers rather than failing. Re-submitting on the same day
overwrites rather than duplicating, so streaks stay honest.

## Safety behaviour worth knowing about

These are enforced server-side, not by prompt alone, so they cannot be argued away by the model or the client:

- Calorie targets are floored at 1200 kcal for women and 1500 kcal for men, and never fall below 75% of estimated TDEE.
- Weekly loss is capped at 1.0 kg regardless of what pace the user selects.
- Messages containing disordered-eating or self-harm language bypass the AI entirely and return a fixed supportive response with crisis resources and no numeric targets.
- Photo-based calorie estimates are labelled as estimates in the UI, because they are,
  and every field is editable before anything is written to the diary.
- The risk-language detector gates the daily check-in as well as the coach chat. It
  matches broadly on purging, restriction, and self-harm phrasing: a false positive
  costs one supportive reply, a false negative sends coaching numbers to someone in
  crisis. Test coverage for it is treated as a safety property, not a nicety.
- The offline check-in fallback is asserted never to emit a calorie figure, so an AI
  outage cannot route around the clinical floors.

## Feature map

Auth (email, Apple, reset, JWT refresh rotation) · Dashboard · Weight tracking ·
Weight projection engine · Step tracking with HealthKit background sync · AI coach with
durable memory · Daily AI check-in with streaks · Meal planner and grocery lists ·
Editable food photo recognition · Calorie and macro logging · Water tracking · Habits
with XP, levels and badges · Challenges with per-day streak tracking · Premium
subscriptions with feature gating · Push and reminder engine · Admin panel · Analytics
and trends · Full dark mode.
