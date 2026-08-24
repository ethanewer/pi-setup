import os
import json
import time
import signal
import subprocess
import configparser
import psutil
import pytest
from pathlib import Path

@pytest.fixture(scope="module", autouse=True)
def setup_test_environment():
    """Create test files and start the orchestrator."""
    # Create config files
    services_conf = """[web_server]
command = python3 /app/mock_web_server.py
port = 8080
health_check = http://localhost:8080/health

[database]
command = python3 /app/mock_database.py
port = 5432
health_check = nc -z localhost 5432

[cache]
command = python3 /app/mock_cache.py
port = 6379
health_check = nc -z localhost 6379
"""
    
    monitoring_conf = """{
  "monitoring_interval": 2,
  "max_retries": 2,
  "health_check_timeout": 1,
  "log_level": "INFO"
}
"""
    
    # Write config files
    with open('/app/services.conf', 'w') as f:
        f.write(services_conf)
    
    with open('/app/monitoring.conf', 'w') as f:
        f.write(monitoring_conf)
    
    # Create mock services
    mock_web = '''#!/usr/bin/env python3
import socket
import time
import os
import sys

# Write PID file
with open(f'/tmp/mock_service_web_server.pid', 'w') as f:
    f.write(str(os.getpid()))

# Simple HTTP server that responds to /health
server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.bind(('localhost', 8080))
server.listen(5)

while True:
    conn, addr = server.accept()
    request = conn.recv(1024).decode()
    if 'GET /health' in request:
        conn.send(b'HTTP/1.1 200 OK\\r\\nContent-Type: text/plain\\r\\n\\r\\nALIVE')
    else:
        conn.send(b'HTTP/1.1 404 Not Found\\r\\n\\r\\n')
    conn.close()
'''
    
    mock_db = '''#!/usr/bin/env python3
import socket
import time
import os

# Write PID file
with open(f'/tmp/mock_service_database.pid', 'w') as f:
    f.write(str(os.getpid()))

# Simple socket server
server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.bind(('localhost', 5432))
server.listen(5)

while True:
    conn, addr = server.accept()
    conn.close()
    time.sleep(0.1)
'''
    
    mock_cache = '''#!/usr/bin/env python3
import socket
import time
import os

# Write PID file
with open(f'/tmp/mock_service_cache.pid', 'w') as f:
    f.write(str(os.getpid()))

# Simple socket server
server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.bind(('localhost', 6379))
server.listen(5)

while True:
    conn, addr = server.accept()
    conn.close()
    time.sleep(0.1)
'''
    
    with open('/app/mock_web_server.py', 'w') as f:
        f.write(mock_web)
    
    with open('/app/mock_database.py', 'w') as f:
        f.write(mock_db)
    
    with open('/app/mock_cache.py', 'w') as f:
        f.write(mock_cache)
    
    # Make them executable
    os.chmod('/app/mock_web_server.py', 0o755)
    os.chmod('/app/mock_database.py', 0o755)
    os.chmod('/app/mock_cache.py', 0o755)
    
    # Start the orchestrator
    orchestrator = subprocess.Popen(
        ['python3', '/app/service_orchestrator.py'],
        start_new_session=True
    )
    
    # Give it time to start services
    time.sleep(5)
    
    yield orchestrator
    
    # Cleanup
    os.killpg(os.getpgid(orchestrator.pid), signal.SIGTERM)
    time.sleep(2)
    
    # Clean up any remaining processes
    for proc in psutil.process_iter(['pid', 'name']):
        if 'python3' in proc.info['name'] and 'mock' in ' '.join(proc.cmdline()):
            try:
                proc.terminate()
            except:
                pass

def test_orchestrator_running(setup_test_environment):
    """Verify orchestrator process is running."""
    orchestrator = setup_test_environment
    assert orchestrator.poll() is None, "Orchestrator process died"

def test_services_started():
    """Verify all three services are running."""
    time.sleep(3)
    
    # Check PID files exist
    assert os.path.exists('/tmp/mock_service_web_server.pid')
    assert os.path.exists('/tmp/mock_service_database.pid')
    assert os.path.exists('/tmp/mock_service_cache.pid')
    
    # Verify services are listening on ports
    import socket
    for port in [8080, 5432, 6379]:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        result = sock.connect_ex(('localhost', port))
        sock.close()
        assert result == 0, f"Service not listening on port {port}"

def test_service_log_created():
    """Verify service log file is created and has content."""
    time.sleep(2)
    assert os.path.exists('/app/service_log.txt'), "Service log not created"
    
    with open('/app/service_log.txt', 'r') as f:
        content = f.read()
        assert len(content) > 0, "Service log is empty"
        assert 'INFO' in content or 'starting' in content.lower()

def test_health_report_generated():
    """Verify health reports are generated periodically."""
    # Wait for at least one report cycle (2 sec interval * 5 cycles = 10 sec)
    time.sleep(12)
    
    assert os.path.exists('/app/health_report.json'), "Health report not generated"
    
    with open('/app/health_report.json', 'r') as f:
        report = json.load(f)
        
        # Validate report structure
        assert 'timestamp' in report
        assert 'total_services' in report
        assert report['total_services'] == 3
        assert 'running_services' in report
        assert 'failed_services' in report
        assert 'service_details' in report
        assert 'system_load' in report
        
        # Check service details
        details = report['service_details']
        assert 'web_server' in details
        assert 'database' in details
        assert 'cache' in details
        
        for service in ['web_server', 'database', 'cache']:
            assert 'status' in details[service]
            assert details[service]['status'] in ['running', 'failed']
            if details[service]['status'] == 'running':
                assert 'pid' in details[service]
                assert 'uptime' in details[service]
            assert 'restart_count' in details[service]

def test_service_failure_recovery():
    """Verify failed services are restarted."""
    # Kill one service
    with open('/tmp/mock_service_database.pid', 'r') as f:
        db_pid = int(f.read().strip())
    
    os.kill(db_pid, signal.SIGTERM)
    time.sleep(1)
    
    # Wait for monitoring to detect and restart
    time.sleep(6)
    
    # Check new PID file exists
    assert os.path.exists('/tmp/mock_service_database.pid')
    
    with open('/tmp/mock_service_database.pid', 'r') as f:
        new_pid = int(f.read().strip())
    
    assert new_pid != db_pid, "Service was not restarted"
    
    # Verify service is listening again
    import socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    result = sock.connect_ex(('localhost', 5432))
    sock.close()
    assert result == 0, "Restarted service not listening"

def test_graceful_shutdown():
    """Verify graceful shutdown on SIGTERM."""
    # Send SIGTERM to orchestrator
    orchestrator = setup_test_environment
    os.killpg(os.getpgid(orchestrator.pid), signal.SIGTERM)
    
    # Wait for shutdown
    time.sleep(3)
    
    # Check shutdown report
    assert os.path.exists('/app/shutdown_report.json'), "Shutdown report not created"
    
    with open('/app/shutdown_report.json', 'r') as f:
        shutdown_report = json.load(f)
        assert 'shutdown_time' in shutdown_report
        assert 'final_status' in shutdown_report
        
        final_status = shutdown_report['final_status']
        assert 'services_stopped' in final_status
        assert final_status['services_stopped'] == 3
    
    # Verify no mock services are running
    time.sleep(1)
    for port in [8080, 5432, 6379]:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        result = sock.connect_ex(('localhost', port))
        sock.close()
        assert result != 0, f"Service still running on port {port} after shutdown"

def test_log_file_format():
    """Verify log file has proper format with timestamps."""
    if not os.path.exists('/app/service_log.txt'):
        pytest.skip("Log file not created")
    
    with open('/app/service_log.txt', 'r') as f:
        lines = f.readlines()
        
        # Check at least some lines have ISO timestamp format
        iso_timestamps = 0
        for line in lines[:10]:  # Check first 10 lines
            if len(line) > 20 and line[4] == '-' and line[7] == '-':  # Basic ISO check
                iso_timestamps += 1
        
        assert iso_timestamps > 0, "No ISO timestamps found in log"
        
        # Check for monitoring actions
        log_content = '\n'.join(lines)
        assert any(word in log_content.lower() for word in ['check', 'monitor', 'start', 'stop', 'restart'])

def test_configuration_parsing():
    """Verify configuration files are parsed correctly."""
    # This test runs the orchestrator's config parsing logic
    import sys
    sys.path.insert(0, '/app')
    
    try:
        # Try to import and test config parsing
        import configparser
        import json
        
        # Parse services config
        config = configparser.ConfigParser()
        config.read('/app/services.conf')
        
        assert 'web_server' in config
        assert 'database' in config
        assert 'cache' in config
        
        for section in config.sections():
            assert 'command' in config[section]
            assert 'port' in config[section]
            assert 'health_check' in config[section]
        
        # Parse monitoring config
        with open('/app/monitoring.conf', 'r') as f:
            monitor_config = json.load(f)
        
        assert 'monitoring_interval' in monitor_config
        assert 'max_retries' in monitor_config
        assert 'health_check_timeout' in monitor_config
        
    except ImportError:
        pytest.fail("Failed to import required modules")
    except Exception as e:
        pytest.fail(f"Config parsing failed: {e}")