# test_initial_state.py
import os

def test_citations_csv_exists():
    assert os.path.isfile("/home/user/citations.csv"), "The citations.csv file is missing in /home/user."

def test_citations_csv_content():
    expected_content = """1,2
2,3
1,4
4,3
3,5
6,2
7,8
8,9
7,9
"""
    with open("/home/user/citations.csv", "r") as f:
        content = f.read()
    assert content == expected_content, "The content of citations.csv does not match the expected initial state."