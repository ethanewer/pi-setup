# test_initial_state.py

import os
import csv
import pytest

def test_raw_data_exists():
    """Test that the raw_data.csv file exists."""
    file_path = "/home/user/raw_data.csv"
    assert os.path.exists(file_path), f"Missing required file: {file_path}"
    assert os.path.isfile(file_path), f"Expected a file, but found a directory: {file_path}"

def test_raw_data_format():
    """Test that the raw_data.csv file has the correct header and row count."""
    file_path = "/home/user/raw_data.csv"
    with open(file_path, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["id", "f1", "f2", "f3"], f"Incorrect header in {file_path}: {header}"

        rows = list(reader)
        assert len(rows) == 1000, f"Expected 1000 data rows in {file_path}, found {len(rows)}"

        # Check first row format
        first_row = rows[0]
        assert len(first_row) == 4, f"Expected 4 columns in {file_path}, found {len(first_row)}"
        try:
            int(first_row[0])
            float(first_row[1])
            float(first_row[2])
            float(first_row[3])
        except ValueError as e:
            pytest.fail(f"Data format error in {file_path}: {e}")