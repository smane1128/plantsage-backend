from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from typing import Optional
from database.db import get_db
from models.garden_profile import GardenProfile

router = APIRouter(prefix="/garden-profile", tags=["garden"])


class GardenProfileSchema(BaseModel):
    location: Optional[str] = None
    garden_size: Optional[str] = None
    sunlight: Optional[str] = None
    soil_type: Optional[str] = None
    water_availability: Optional[str] = None


@router.get("")
def get_garden_profile(db: Session = Depends(get_db)):
    profile = db.query(GardenProfile).filter(GardenProfile.id == 1).first()
    if not profile:
        raise HTTPException(status_code=404, detail="No garden profile set")
    return {
        "location": profile.location,
        "garden_size": profile.garden_size,
        "sunlight": profile.sunlight,
        "soil_type": profile.soil_type,
        "water_availability": profile.water_availability,
    }


@router.post("")
def save_garden_profile(data: GardenProfileSchema, db: Session = Depends(get_db)):
    profile = db.query(GardenProfile).filter(GardenProfile.id == 1).first()
    if profile:
        profile.location = data.location
        profile.garden_size = data.garden_size
        profile.sunlight = data.sunlight
        profile.soil_type = data.soil_type
        profile.water_availability = data.water_availability
    else:
        profile = GardenProfile(
            id=1,
            location=data.location,
            garden_size=data.garden_size,
            sunlight=data.sunlight,
            soil_type=data.soil_type,
            water_availability=data.water_availability,
        )
        db.add(profile)
    db.commit()
    return {"message": "Garden profile saved"}
