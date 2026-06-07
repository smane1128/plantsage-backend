from sqlalchemy import Column, Integer, String, Text, DateTime
from datetime import datetime, UTC
from database.db import Base


class MyGarden(Base):
    __tablename__ = "my_garden"

    id = Column(Integer, primary_key=True, autoincrement=True)
    plant_name = Column(String, nullable=False)
    scientific_name = Column(String, nullable=True)
    plant_type = Column(String, nullable=True)
    recommendation = Column(String, nullable=True)
    suitability_score = Column(Integer, nullable=True)
    notes = Column(Text, nullable=True)
    image_path = Column(String, nullable=True)
    date_added = Column(DateTime, default=lambda: datetime.now(UTC))
    watering_interval_days = Column(Integer, nullable=True)   # e.g. 3 = water every 3 days
    last_watered_at        = Column(DateTime, nullable=True)
    health_status          = Column(String, nullable=True)    # 'healthy' | 'sick' | 'recovering'
    garden_name            = Column(String, nullable=True)    # user label e.g. "Red Rose", "Pot #1"
    location               = Column(String, nullable=True)    # e.g. "Front Yard", "Balcony"
    purchase_date          = Column(DateTime, nullable=True)  # when user bought/acquired the plant
