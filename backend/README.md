# Backend

FastAPI REST API for user profiles, backed by PostgreSQL via SQLAlchemy 2.x async (asyncpg). Part of the `plinth` monorepo — see the root [README.md](../README.md) for full-stack setup.

## Quick start

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

export DATABASE_URL="postgresql+asyncpg://appuser:change-me@localhost:5432/appdb"
export FRONTEND_ORIGINS="http://localhost:3000"

uvicorn app.main:app --reload --host 0.0.0.0 --port 8080
```

Or use Docker Compose from the repo root (recommended).

## API endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/` | Returns `"Application is running"` |
| GET | `/health` | Returns `{"status": "ok"}` — never touches the database |
| POST | `/api/profiles` | Create a profile |
| GET | `/api/profiles` | List all profiles |
| GET | `/api/profiles/{id}` | Get a profile |
| PATCH | `/api/profiles/{id}` | Update a profile |
| DELETE | `/api/profiles/{id}` | Delete a profile |

## Environment variables

- `DATABASE_URL` — PostgreSQL connection string (required)
- `FRONTEND_ORIGINS` — comma-separated allowed CORS origins (required)

Both are validated at import time. The app raises a `RuntimeError` listing every missing variable if either is unset.

## Tests

```bash
pip install -r requirements-dev.txt
pytest -v
```

Tests use an in-memory SQLite override — no PostgreSQL needed.

## Docker

```bash
docker build -t backend .
docker run -p 8080:8080 --env-file .env backend
```

Or use Docker Compose from the repo root — see [README.md](../README.md).
