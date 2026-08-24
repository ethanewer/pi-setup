# test_initial_state.py

import os
import pytest

def test_raw_data_directory_exists():
    assert os.path.isdir('/home/user/raw_data'), "Directory /home/user/raw_data does not exist"

def test_raw_data_files_exist():
    file1 = '/home/user/raw_data/file1.csv'
    file2 = '/home/user/raw_data/file2.csv'

    assert os.path.isfile(file1), f"File {file1} does not exist"
    assert os.path.isfile(file2), f"File {file2} does not exist"

def test_raw_data_file1_content():
    file1 = '/home/user/raw_data/file1.csv'
    with open(file1, 'r') as f:
        content = f.read()
    assert "timestamp,sensor_id,metric,value" in content, "file1.csv missing header"
    assert "2023-01-01 09:05:00,S1,temp,20.0" in content, "file1.csv missing expected data line"
    assert "[DEBUG] Calibrating S1..." in content, "file1.csv missing debug log line"

def test_raw_data_file2_content():
    file2 = '/home/user/raw_data/file2.csv'
    with open(file2, 'r') as f:
        content = f.read()
    assert "2023-01-01 10:30:00,S2,humidity,40.0" in content, "file2.csv missing expected data line"
    assert "[INFO] Restarting sensor S3" in content, "file2.csv missing info log line"