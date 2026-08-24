# test_initial_state.py

import os
import socket
import pytest

def test_deploy_system_directory_does_not_exist():
    """Ensure the deploy_system directory does not exist before starting."""
    dir_path = "/home/user/deploy_system"
    assert not os.path.exists(dir_path), f"Directory {dir_path} should not exist before the task."

def test_port_9443_is_free():
    """Ensure port 9443 is free before starting the task."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        # If connect_ex returns 0, the port is open (in use)
        result = s.connect_ex(('localhost', 9443))
        assert result != 0, "Port 9443 is already in use. It must be free before starting the task."