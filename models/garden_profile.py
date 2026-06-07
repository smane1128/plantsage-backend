from sqlalchemy import Column, Integer, String
from database.db import Base


class GardenProfile(Base):
    __tablename__ = "garden_profile"

    id = Column(Integer, primary_key=True, default=1)
    location = Column(String, nullable=True)
    garden_size = Column(String, nullable=True)   # Balcony/Pots | Small Yard | Medium Yard | Large Yard
    sunlight = Column(String, nullable=True)       # Full Sun | Mostly Sunny | Partial Shade | Full Shade
    soil_type = Column(String, nullable=True)      # Sandy | Clay | Loam | Unknown
    water_availability = Column(String, nullable=True)  # Always Available | Rainwater Mainly | Limited | Automatic Irrigation
