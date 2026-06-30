from sqlalchemy import Column, Integer, String, Text, DateTime
from datetime import datetime, UTC
from database.db import Base


class Wishlist(Base):
    __tablename__ = "wishlist"

    id = Column(Integer, primary_key=True, autoincrement=True)
    plant_name = Column(String, nullable=False)
    scientific_name = Column(String, nullable=True)
    plant_type = Column(String, nullable=True)
    recommendation = Column(String, nullable=True)
    suitability_score = Column(Integer, nullable=True)
    image_path = Column(String, nullable=True)
    notes = Column(Text, nullable=True)
    date_added = Column(DateTime, default=lambda: datetime.now(UTC))
