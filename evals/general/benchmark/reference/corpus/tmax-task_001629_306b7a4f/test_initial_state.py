# test_initial_state.py

import os
import pytest

def test_telemetry_stack_exists():
    base_dir = "/home/user/app/telemetry_stack"
    assert os.path.isdir(base_dir), f"Directory {base_dir} is missing."

    expected_files = [
        "nginx.conf",
        ".env",
        "start.sh"
    ]

    for f in expected_files:
        file_path = os.path.join(base_dir, f)
        assert os.path.isfile(file_path), f"Expected file {file_path} is missing."

def test_test_corpora_exist():
    evil_corpus = "/home/user/tests/evil_corpus"
    clean_corpus = "/home/user/tests/clean_corpus"

    assert os.path.isdir(evil_corpus), f"Evil corpus directory {evil_corpus} is missing."
    assert os.path.isdir(clean_corpus), f"Clean corpus directory {clean_corpus} is missing."

    # Check that they contain some files
    evil_files = os.listdir(evil_corpus)
    clean_files = os.listdir(clean_corpus)

    assert len(evil_files) > 0, f"Evil corpus directory {evil_corpus} is empty."
    assert len(clean_files) > 0, f"Clean corpus directory {clean_corpus} is empty."

def test_production_logs_dir_exists():
    prod_logs = "/home/user/production_logs"
    assert os.path.isdir(prod_logs), f"Production logs directory {prod_logs} is missing."