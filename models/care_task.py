from sqlalchemy import Column, Integer, String, Text, DateTime, ForeignKey
from datetime import datetime, UTC
from database.db import Base


class CareTask(Base):
    __tablename__ = "care_tasks"

    id              = Column(Integer, primary_key=True, autoincrement=True)
    plant_id        = Column(Integer, ForeignKey("my_garden.id", ondelete="CASCADE"), nullable=False)
    task_type       = Column(String, nullable=False)   # fertilize|prune|repot|pest_check
    interval_days   = Column(Integer, nullable=False)
    last_done_at    = Column(DateTime, nullable=True)
    notes           = Column(Text, nullable=True)
    schedule_source = Column(String(20), nullable=True)  # species_specific|ai_estimated|plant_type_rule
