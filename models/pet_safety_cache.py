from sqlalchemy import Column, Integer, String, Text, DateTime
from sqlalchemy.sql import func
from database.db import Base


class PetSafetyCache(Base):
    """Cached AI-researched pet safety results.

    Populated when the verified database has no entry for a plant and the
    AI research fallback is invoked. Subsequent lookups for the same plant
    use this cache instead of calling the AI again.
    """
    __tablename__ = "pet_safety_cache"

    id              = Column(Integer, primary_key=True, autoincrement=True)
    scientific_name = Column(String, nullable=True, index=True)
    genus           = Column(String, nullable=True, index=True)
    common_name     = Column(String, nullable=True)
    safety_status   = Column(String, nullable=False)          # safe|caution|toxic|unknown
    confidence      = Column(Integer, nullable=False)          # 0–100
    source          = Column(String, nullable=False, default="AI_RESEARCH")
    reasoning       = Column(Text, nullable=True)
    affected_animals = Column(String, nullable=True, default="")
    symptoms        = Column(Text, nullable=True, default="")
    toxicity_level  = Column(String, nullable=True, default="")
    created_at      = Column(DateTime(timezone=True), server_default=func.now())
