import os

REQUIRED_ENV_VARS = ("DATABASE_URL", "FRONTEND_ORIGINS")

_missing = [name for name in REQUIRED_ENV_VARS if not os.getenv(name)]
if _missing:
    raise RuntimeError(
        f"Missing required environment variable(s): {', '.join(_missing)}"
    )

DATABASE_URL = os.getenv("DATABASE_URL")
FRONTEND_ORIGINS = os.getenv("FRONTEND_ORIGINS")
