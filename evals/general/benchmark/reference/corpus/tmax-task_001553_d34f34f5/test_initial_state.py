# test_initial_state.py

import os
import sqlite3
import subprocess

def test_legacy_db_exists():
    """Verify that the legacy SQLite database exists at the expected path."""
    db_path = "/home/user/legacy.db"
    assert os.path.isfile(db_path), f"Database file {db_path} does not exist."

def test_legacy_db_tables():
    """Verify that the legacy database contains the correct undocumented tables."""
    db_path = "/home/user/legacy.db"
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = {row[0] for row in cursor.fetchall()}

    expected_tables = {'t_alpha', 't_beta', 't_gamma'}
    assert expected_tables.issubset(tables), f"Database is missing expected tables. Expected {expected_tables}, found: {tables}"

    conn.close()

def test_gcc_installed():
    """Verify that gcc is installed for compiling the C program."""
    result = subprocess.run(["which", "gcc"], capture_output=True, text=True)
    assert result.returncode == 0, "gcc is not installed or not in PATH."

def test_sqlite3_dev_installed():
    """Verify that libsqlite3-dev is installed."""
    result = subprocess.run(["dpkg", "-l", "libsqlite3-dev"], capture_output=True, text=True)
    assert result.returncode == 0, "libsqlite3-dev package is not installed."

def test_sqlite3_cli_installed():
    """Verify that sqlite3 CLI is installed."""
    result = subprocess.run(["which", "sqlite3"], capture_output=True, text=True)
    assert result.returncode == 0, "sqlite3 CLI is not installed or not in PATH."