from sqlalchemy import create_engine, text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from dotenv import load_dotenv
import os

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./myplants.db")
# Railway/Heroku give "postgres://", which SQLAlchemy no longer accepts.
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False} if "sqlite" in DATABASE_URL else {},
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def repair_care_tasks(db_engine):
    """Keep the newest schedule per plant/type and preserve completion history."""
    with db_engine.begin() as conn:
        conn.execute(text("""
            DELETE FROM care_task_history
            WHERE plant_id NOT IN (SELECT id FROM my_garden)
        """))
        conn.execute(text("""
            DELETE FROM care_tasks
            WHERE plant_id NOT IN (SELECT id FROM my_garden)
        """))
        conn.execute(text("""
            UPDATE care_task_history
            SET task_id = (
                SELECT MAX(t.id) FROM care_tasks t
                WHERE t.plant_id = care_task_history.plant_id
                  AND t.task_type = care_task_history.task_type
            )
            WHERE task_id IN (SELECT id FROM care_tasks)
        """))
        conn.execute(text("""
            DELETE FROM care_tasks
            WHERE id NOT IN (
                SELECT MAX(id) FROM care_tasks GROUP BY plant_id, task_type
            )
        """))
        conn.execute(text("""
            CREATE UNIQUE INDEX IF NOT EXISTS uq_care_tasks_plant_type
            ON care_tasks(plant_id, task_type)
        """))


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
