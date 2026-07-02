import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import List, Optional

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, ConfigDict, EmailStr
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import FRONTEND_ORIGINS
from app.database import Base, engine, get_session
from app.models import Profile

origins = [o.strip() for o in FRONTEND_ORIGINS.split(",") if o.strip()]
if not origins:
    raise RuntimeError("FRONTEND_ORIGINS must contain at least one origin")


@asynccontextmanager
async def lifespan(app: FastAPI):
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield


app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class ProfileBase(BaseModel):
    fullName: str
    email: EmailStr
    phoneNumber: Optional[str] = None
    country: Optional[str] = None
    isActive: bool = True


class ProfileCreate(ProfileBase):
    pass


class ProfileUpdate(BaseModel):
    fullName: Optional[str] = None
    email: Optional[EmailStr] = None
    phoneNumber: Optional[str] = None
    country: Optional[str] = None
    isActive: Optional[bool] = None


class ProfileOut(ProfileBase):
    id: str
    createdAt: datetime
    updatedAt: datetime

    model_config = ConfigDict(from_attributes=True)


FIELD_MAP = {
    "fullName": "full_name",
    "email": "email",
    "phoneNumber": "phone_number",
    "country": "country",
    "isActive": "is_active",
}


def to_out(profile: Profile) -> ProfileOut:
    return ProfileOut(
        id=str(profile.id),
        fullName=profile.full_name,
        email=profile.email,
        phoneNumber=profile.phone_number,
        country=profile.country,
        isActive=profile.is_active,
        createdAt=profile.created_at,
        updatedAt=profile.updated_at,
    )


@app.get("/")
async def root():
    return "Application is running"


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/api/profiles", response_model=ProfileOut, status_code=status.HTTP_201_CREATED)
async def create_profile(payload: ProfileCreate, session: AsyncSession = Depends(get_session)):
    now = datetime.now(timezone.utc)
    profile = Profile(
        id=str(uuid.uuid4()),
        full_name=payload.fullName,
        email=payload.email,
        phone_number=payload.phoneNumber,
        country=payload.country,
        is_active=payload.isActive,
        created_at=now,
        updated_at=now,
    )
    session.add(profile)
    await session.commit()
    await session.refresh(profile)
    return to_out(profile)


@app.get("/api/profiles", response_model=List[ProfileOut])
async def list_profiles(session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(Profile).order_by(Profile.created_at.desc()))
    return [to_out(p) for p in result.scalars().all()]


@app.get("/api/profiles/{profile_id}", response_model=ProfileOut)
async def get_profile(profile_id: str, session: AsyncSession = Depends(get_session)):
    profile = await session.get(Profile, profile_id)
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    return to_out(profile)


@app.patch("/api/profiles/{profile_id}", response_model=ProfileOut)
async def update_profile(
    profile_id: str, payload: ProfileUpdate, session: AsyncSession = Depends(get_session)
):
    profile = await session.get(Profile, profile_id)
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    data = payload.model_dump(exclude_unset=True)
    changed = False
    for key, value in data.items():
        column = FIELD_MAP[key]
        if key in ("fullName", "email") and value is None:
            continue
        if getattr(profile, column) != value:
            setattr(profile, column, value)
            changed = True
    if changed:
        profile.updated_at = datetime.now(timezone.utc)
    await session.commit()
    await session.refresh(profile)
    return to_out(profile)


@app.delete("/api/profiles/{profile_id}")
async def delete_profile(profile_id: str, session: AsyncSession = Depends(get_session)):
    profile = await session.get(Profile, profile_id)
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    await session.delete(profile)
    await session.commit()
    return {"message": "Profile deleted successfully"}
