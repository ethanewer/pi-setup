# test_initial_state.py

import os
import importlib.util

def test_workspace_dir_exists():
    assert os.path.isdir("/home/user/workspace"), "/home/user/workspace directory is missing"

def test_src_dir_exists():
    assert os.path.isdir("/home/user/workspace/src"), "/home/user/workspace/src directory is missing"

def test_c_files_exist():
    c_files = ["modA.c", "modB.c", "modC.c", "modD.c"]
    for f in c_files:
        path = f"/home/user/workspace/src/{f}"
        assert os.path.isfile(path), f"{path} is missing"

def test_ws_server_exists():
    path = "/home/user/workspace/ws_server.py"
    assert os.path.isfile(path), f"{path} is missing"

def test_websockets_installed():
    assert importlib.util.find_spec("websockets") is not None, "websockets package is not installed"