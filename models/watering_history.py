from sqlalchemy import Column, Integer, ForeignKey, DateTime
from datetime import datetime, UTC
from database.db import Base


class WateringHistory(Base):
    __tablename__ = "watering_history"

    id         = Column(Integer, primary_key=True, autoincrement=True)
    plant_id   = Column(Integer, ForeignKey("my_garden.id", ondelete="CASCADE"), nullable=False)
    watered_at = Column(DateTime, default=lambda: datetime.now(UTC), nullable=False)
