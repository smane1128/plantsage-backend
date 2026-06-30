from sqlalchemy import Column, Integer, String, Text, DateTime, ForeignKey
from datetime import datetime, UTC
from database.db import Base


class CareTaskHistory(Base):
    __tablename__ = "care_task_history"

    id        = Column(Integer, primary_key=True, autoincrement=True)
    task_id   = Column(Integer, ForeignKey("care_tasks.id", ondelete="SET NULL"), nullable=True)
    plant_id  = Column(Integer, ForeignKey("my_garden.id", ondelete="CASCADE"), nullable=False)
    task_type = Column(String, nullable=False)   # fertilize | prune | pest_check
    done_at   = Column(DateTime, default=lambda: datetime.now(UTC), nullable=False)
    notes     = Column(Text, nullable=True)
