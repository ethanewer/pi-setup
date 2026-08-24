# test_initial_state.py

import os
import pytest

def test_analytics_directory_exists():
    """Test that the analytics directory exists."""
    dir_path = "/home/user/analytics"
    assert os.path.isdir(dir_path), f"Directory {dir_path} does not exist."

def test_network_csv_exists_and_content():
    """Test that the network.csv file exists and has the correct content."""
    file_path = "/home/user/analytics/network.csv"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    expected_content = """A,B,5
A,C,6
B,C,2
D,A,15
D,B,1
E,F,5
G,H,12
H,A,10
H,B,10"""

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == expected_content.strip(), f"Content of {file_path} does not match the expected network data."