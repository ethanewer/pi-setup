# test_initial_state.py

import os
import sqlite3
import pytest

DB_PATH = "/home/user/company.db"

def test_db_exists():
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"
    assert os.path.isfile(DB_PATH), f"{DB_PATH} is not a file"

def test_employees_table_schema():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='employees';")
    table = cursor.fetchone()
    assert table is not None, "Table 'employees' does not exist in the database."

    cursor.execute("PRAGMA table_info(employees);")
    columns = {row[1]: row[2] for row in cursor.fetchall()}

    expected_columns = {
        "id": "INTEGER",
        "name": "TEXT",
        "manager_id": "INTEGER",
        "department_id": "INTEGER",
        "individual_sales": "INTEGER"
    }

    for col_name, col_type in expected_columns.items():
        assert col_name in columns, f"Column '{col_name}' missing in 'employees' table."
        assert columns[col_name].upper() == col_type, f"Column '{col_name}' has incorrect type {columns[col_name]}, expected {col_type}."

    conn.close()

def test_employees_initial_data():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT id, name, manager_id, department_id, individual_sales FROM employees ORDER BY id;")
    rows = cursor.fetchall()

    expected_rows = [
        (1, 'Alice', None, 1, 10),
        (2, 'Bob', 1, 2, 20),
        (3, 'Charlie', 1, 3, 30),
        (4, 'Dave', 2, 2, 100),
        (5, 'Eve', 2, 2, 150),
        (6, 'Frank', 3, 3, 200)
    ]

    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, found {len(rows)}."

    for i, (row, expected) in enumerate(zip(rows, expected_rows)):
        assert row == expected, f"Row {i+1} mismatch: expected {expected}, got {row}."

    conn.close()