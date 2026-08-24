# test_initial_state.py

import os
import pytest

def test_logs_directory_exists():
    assert os.path.isdir('/home/user/logs'), "The directory /home/user/logs does not exist."

@pytest.mark.parametrize("node", [1, 2, 3, 4, 5])
def test_node_log_files_exist(node):
    log_file = f'/home/user/logs/node_{node}.log'
    assert os.path.isfile(log_file), f"Log file {log_file} is missing."

def test_aggregate_script_exists_and_executable():
    script_path = '/home/user/aggregate.sh'
    assert os.path.isfile(script_path), f"The script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."

def test_node_4_contains_comma_format():
    log_file = '/home/user/logs/node_4.log'
    with open(log_file, 'r') as f:
        lines = f.readlines()

    assert len(lines) == 100, f"Expected 100 lines in {log_file}, got {len(lines)}."

    # Check epoch 51 for comma formatting
    epoch_51_line = lines[50]
    assert "Epoch: 51" in epoch_51_line, "Line 51 does not correspond to Epoch 51."
    assert "," in epoch_51_line, "Epoch 51 in node 4 does not contain the expected comma decimal separator."
    assert "e" in epoch_51_line.lower(), "Epoch 51 in node 4 does not contain the expected scientific notation."