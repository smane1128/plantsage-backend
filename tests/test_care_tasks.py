"""Regression tests for care schedule cleanup, deletion and uniqueness."""
import unittest
from datetime import datetime

from sqlalchemy import create_engine
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from database.db import Base, repair_care_tasks
from models.care_task import CareTask
from models.care_task_history import CareTaskHistory
from models.my_garden import MyGarden
from models.watering_history import WateringHistory
from models.disease_scan import DiseaseScan
from routes.my_garden import remove_from_my_garden
from routes.care_tasks import delete_care_task


class CareTaskTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine("sqlite:///:memory:")
        Base.metadata.create_all(self.engine)
        self.db = Session(self.engine)
        self.db.add(MyGarden(id=1, plant_name="Ixora"))
        self.db.commit()

    def tearDown(self):
        self.db.close()
        self.engine.dispose()

    def add_task(self, task_id, task_type="fertilize", plant_id=1, interval=30):
        self.db.add(CareTask(
            id=task_id, plant_id=plant_id, task_type=task_type,
            interval_days=interval,
        ))
        self.db.commit()

    def test_repair_keeps_latest_set_preserves_history_and_is_idempotent(self):
        for group in range(3):
            for offset, kind in enumerate(("fertilize", "prune", "pest_check"), 1):
                self.add_task(group * 3 + offset, kind, interval=14 + group)
        self.db.add(CareTaskHistory(
            plant_id=1, task_id=1, task_type="fertilize",
            done_at=datetime(2026, 10, 30), notes="Completed",
        ))
        self.db.commit()

        repair_care_tasks(self.engine)
        repair_care_tasks(self.engine)
        self.db.expire_all()
        tasks = self.db.query(CareTask).order_by(CareTask.id).all()
        self.assertEqual([t.id for t in tasks], [7, 8, 9])
        self.assertEqual([t.interval_days for t in tasks], [16, 16, 16])
        history = self.db.query(CareTaskHistory).one()
        self.assertEqual(history.task_id, 7)
        self.assertEqual(history.notes, "Completed")
        with self.assertRaises(IntegrityError):
            self.add_task(10)
        self.db.rollback()
        self.db.add(MyGarden(id=2, plant_name="Rose"))
        self.db.commit()
        self.add_task(10, plant_id=2)

    def test_repair_removes_orphan_tasks_and_history(self):
        self.add_task(1, plant_id=99)
        self.db.add(CareTaskHistory(
            plant_id=99, task_id=1, task_type="fertilize",
        ))
        self.db.commit()
        repair_care_tasks(self.engine)
        self.assertEqual(self.db.query(CareTask).count(), 0)
        self.assertEqual(self.db.query(CareTaskHistory).count(), 0)

    def test_delete_plant_removes_dependents_before_id_is_reused(self):
        self.add_task(1)
        self.db.add(CareTaskHistory(plant_id=1, task_id=1, task_type="fertilize"))
        self.db.add(WateringHistory(plant_id=1))
        self.db.add(DiseaseScan(plant_id=1, disease_name="Leaf spot"))
        self.db.commit()
        remove_from_my_garden(1, self.db)
        self.assertEqual(self.db.query(CareTask).count(), 0)
        self.assertEqual(self.db.query(CareTaskHistory).count(), 0)
        self.assertEqual(self.db.query(WateringHistory).count(), 0)
        self.assertIsNone(self.db.query(DiseaseScan).one().plant_id)
        self.db.add(MyGarden(id=1, plant_name="New Ixora"))
        self.db.commit()
        self.add_task(2)
        self.assertEqual(self.db.query(CareTask).count(), 1)

    def test_delete_schedule_retains_history_without_dangling_task(self):
        self.add_task(1)
        self.db.add(CareTaskHistory(
            plant_id=1, task_id=1, task_type="fertilize", notes="Completed",
        ))
        self.db.commit()
        delete_care_task(1, self.db)
        history = self.db.query(CareTaskHistory).one()
        self.assertIsNone(history.task_id)
        self.assertEqual(history.notes, "Completed")


if __name__ == "__main__":
    unittest.main()
