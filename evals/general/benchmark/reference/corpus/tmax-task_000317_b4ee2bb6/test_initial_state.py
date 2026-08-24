# test_initial_state.py

import os

def test_raw_metrics_log_exists():
    log_path = '/home/user/raw_metrics.log'
    assert os.path.exists(log_path), f"File {log_path} is missing."
    assert os.path.isfile(log_path), f"{log_path} is not a file."
    assert os.path.getsize(log_path) > 0, f"{log_path} is empty."

def test_expected_aggregated_csv_exists():
    truth_path = '/home/user/expected_aggregated.csv'
    assert os.path.exists(truth_path), f"File {truth_path} is missing."
    assert os.path.isfile(truth_path), f"{truth_path} is not a file."
    assert os.path.getsize(truth_path) > 0, f"{truth_path} is empty."