# test_initial_state.py

import os
import sqlite3
import pytest

def test_dataset_db_exists():
    db_path = "/app/dataset.db"
    assert os.path.isfile(db_path), f"Database file missing at {db_path}"

def test_dataset_db_schema():
    db_path = "/app/dataset.db"
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='nodes';")
    assert cursor.fetchone() is not None, "Table 'nodes' is missing in dataset.db"

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='edges';")
    assert cursor.fetchone() is not None, "Table 'edges' is missing in dataset.db"

    conn.close()

def test_schema_rule_image_exists():
    img_path = "/app/schema_rule.png"
    assert os.path.isfile(img_path), f"Image file missing at {img_path}"