# test_initial_state.py

import os
import shutil
import pytest

def test_rust_installed():
    """Check if Rust (cargo) is installed."""
    assert shutil.which("cargo") is not None, "cargo is not installed or not in PATH"

def test_rust_project_directory_exists():
    """Check if the Rust project directory exists."""
    project_dir = "/home/user/log_pipeline"
    assert os.path.isdir(project_dir), f"Rust project directory {project_dir} does not exist"

def test_input_dataset_exists():
    """Check if the input dataset exists and has the correct content."""
    dataset_path = "/home/user/data/logs.csv"
    assert os.path.isfile(dataset_path), f"Input dataset {dataset_path} does not exist"

    expected_content = """id,group_id,content
1,100,XxYyZz
2,,XyzXyzXyz
3,200,hello world
4,,zzZZzz
5,105,xYxYxYxY
"""
    with open(dataset_path, "r") as f:
        actual_content = f.read()

    assert actual_content == expected_content, f"Content of {dataset_path} does not match expected content"