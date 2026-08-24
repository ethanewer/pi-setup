#!/bin/bash
set -euo pipefail
mkdir -p /home/user/.setup_tmp
export PYTHONPATH=/home/user/.local/lib/python3/dist-packages:${PYTHONPATH:-}
    apt-get update && apt-get install -y python3 python3-pip curl sqlite3 build-essential
    # Install Rust globally
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    ln -s /opt/rust/bin/* /usr/local/bin/ || true
    # Create user and home directory
    mkdir -p /home/user
    # Create database
    sqlite3 /home/user/company.db <<EOF
CREATE TABLE employees (
    id INTEGER PRIMARY KEY,
    name TEXT,
    manager_id INTEGER,
    department_id INTEGER,
    individual_sales INTEGER
);

INSERT INTO employees (id, name, manager_id, department_id, individual_sales) VALUES
(1, 'Alice', NULL, 1, 10),
(2, 'Bob', 1, 2, 20),
(3, 'Charlie', 1, 3, 30),
(4, 'Dave', 2, 2, 100),
(5, 'Eve', 2, 2, 150),
(6, 'Frank', 3, 3, 200);
EOF
rm -rf /home/user/.setup_tmp
