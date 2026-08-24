# test_initial_state.py
import os

def test_etl_directory_exists():
    path = "/home/user/etl"
    assert os.path.isdir(path), f"Directory {path} is missing."

def test_dataset_a_exists():
    path = "/home/user/etl/dataset_A.txt"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, 'r') as f:
        content = f.read()
    assert "hello world this is a test" in content, f"File {path} content is incorrect."

def test_dataset_b_exists():
    path = "/home/user/etl/dataset_B.txt"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, 'r') as f:
        content = f.read()
    assert "another day another pipeline" in content, f"File {path} content is incorrect."

def test_embedder_c_exists():
    path = "/home/user/etl/embedder.c"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, 'r') as f:
        content = f.read()
    assert "int main(int argc, char *argv[])" in content, f"File {path} content is incorrect."