# test_initial_state.py

import os
from pathlib import Path

def test_start_services_script_exists():
    script_path = Path("/app/start_services.sh")
    assert script_path.exists(), f"Missing startup script at {script_path}"
    assert script_path.is_file(), f"{script_path} is not a file"
    assert os.access(script_path, os.X_OK), f"Startup script {script_path} is not executable"

def test_service_edges_exists():
    script_path = Path("/app/service_edges.py")
    assert script_path.exists(), f"Missing upstream service script at {script_path}"
    assert script_path.is_file(), f"{script_path} is not a file"

def test_service_nodes_exists():
    script_path = Path("/app/service_nodes.py")
    assert script_path.exists(), f"Missing upstream service script at {script_path}"
    assert script_path.is_file(), f"{script_path} is not a file"