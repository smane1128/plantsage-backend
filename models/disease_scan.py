from sqlalchemy import Column, Integer, String, Text, DateTime, ForeignKey
from datetime import datetime, UTC
from database.db import Base


class DiseaseScan(Base):
    __tablename__ = "disease_scans"

    id              = Column(Integer, primary_key=True, autoincrement=True)
    plant_name      = Column(String, nullable=True)
    scientific_name = Column(String, nullable=True)
    plant_id        = Column(Integer, ForeignKey("my_garden.id", ondelete="SET NULL"), nullable=True)
    disease_name    = Column(String, nullable=True)
    severity        = Column(String, nullable=True)
    description     = Column(Text, nullable=True)
    treatment       = Column(Text, nullable=True)   # stored as JSON string
    image_path      = Column(String, nullable=True)
    scan_date       = Column(DateTime, default=lambda: datetime.now(UTC), nullable=False)
    updated_date    = Column(DateTime, default=lambda: datetime.now(UTC), onupdate=lambda: datetime.now(UTC), nullable=True)
    status          = Column(String, default='active', nullable=False)  # active | recovering | resolved
    follow_up_notes = Column(Text, nullable=True)
    resolved_at     = Column(DateTime, nullable=True)
