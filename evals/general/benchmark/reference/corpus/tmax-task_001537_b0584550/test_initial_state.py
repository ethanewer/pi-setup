# test_initial_state.py

import os
import stat
import pytest

def test_audit_target_directory_exists():
    path = "/home/user/audit_target"
    assert os.path.isdir(path), f"Directory {path} does not exist"

def test_app_py_exists():
    path = "/home/user/audit_target/app.py"
    assert os.path.isfile(path), f"File {path} does not exist"

    # Check if it contains the expected vulnerable code
    with open(path, 'r') as f:
        content = f.read()
    assert "SELECT * FROM users WHERE id = {user_id}" in content, "SQLi vulnerability missing in app.py"
    assert "return f\"<html><body><h1>Hello, {name}!</h1></body></html>\"" in content, "XSS vulnerability missing in app.py"
    assert "app.run(host='0.0.0.0', port=8443)" in content, "Service port configuration missing in app.py"

def test_config_ini_exists():
    path = "/home/user/audit_target/config.ini"
    assert os.path.isfile(path), f"File {path} does not exist"

def test_users_db_exists_and_is_world_writable():
    path = "/home/user/audit_target/users.db"
    assert os.path.isfile(path), f"File {path} does not exist"

    st = os.stat(path)
    # Check if others have write permission
    assert bool(st.st_mode & stat.S_IWOTH), f"File {path} is not world-writable"

def test_app_py_is_not_world_writable():
    path = "/home/user/audit_target/app.py"
    st = os.stat(path)
    assert not bool(st.st_mode & stat.S_IWOTH), f"File {path} should not be world-writable"

def test_config_ini_is_not_world_writable():
    path = "/home/user/audit_target/config.ini"
    st = os.stat(path)
    assert not bool(st.st_mode & stat.S_IWOTH), f"File {path} should not be world-writable"