# test_initial_state.py

import os
import pytest

def test_libs_csv_exists_and_correct():
    csv_path = "/home/user/libs.csv"
    assert os.path.isfile(csv_path), f"File {csv_path} does not exist."

    expected_content = """core,50
math,30
net,25
ui,80
db,120
crypto,45
"""
    with open(csv_path, "r") as f:
        content = f.read()

    assert content.strip() == expected_content.strip(), f"Content of {csv_path} does not match the expected setup."

def test_solver_sh_does_not_exist():
    solver_path = "/home/user/solver.sh"
    assert not os.path.exists(solver_path), f"File {solver_path} should not exist before the student creates it."