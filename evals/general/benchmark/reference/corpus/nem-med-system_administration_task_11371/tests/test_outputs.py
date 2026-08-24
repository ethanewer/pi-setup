import os
import json
import time
import signal
import subprocess
import psutil
from datetime import datetime, timezone
import re

def test_script_exists():
    """Verify the monitoring script was created."""
    assert os.path.exists('/app/service-monitor.sh'), "Script not found"
    assert os.access('/app/service-monitor.sh', os.X_OK), "Script not executable"
    
    # Check shebang
    with open('/app/service-monitor.sh', 'r') as f:
        first_line = f.readline().strip()
        assert first_line.startswith('#!/'), "Missing shebang"
        assert 'bash' in first_line or 'sh' in first_line, "Not a bash script"

def test_config_parsing():
    """Test configuration file parsing."""
    # Create test config
    test_config = """# Test service configuration
SERVICE_NAME=test-app
SERVICE_CMD="python3 -m http.server 8080"
CHECK_PORT=8080
CHECK_INTERVAL=2
MAX_RESTARTS=3
LOG_FILE=/app/monitor.log
"""
    
    with open('/app/test-service.conf', 'w') as f:
        f.write(test_config)
    
    # Make script executable if not already
    os.chmod('/app/service-monitor.sh', 0o755)
    
    # Test parsing by running script with --test-parse flag if it exists
    # or by checking it can start without errors
    try:
        # Start script in background
        proc = subprocess.Popen(
            ['/app/service-monitor.sh', '/app/test-service.conf'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True
        )
        
        # Give it time to parse config and start
        time.sleep(1)
        
        # Check if status file was created
        assert os.path.exists('/app/monitor-status.json'), "Status file not created"
        
        # Clean up
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        proc.wait(timeout=2)
        
    except subprocess.TimeoutExpired:
        proc.kill()
        raise AssertionError("Script didn't respond to SIGTERM")
    finally:
        # Clean up test files
        if os.path.exists('/app/test-service.conf'):
            os.remove('/app/test-service.conf')
        for f in ['/app/monitor-status.json', '/app/monitor.log', '/app/restart-summary.txt']:
            if os.path.exists(f):
                os.remove(f)

def test_service_monitoring():
    """Test full monitoring cycle with simulated failures."""
    # Create a simple test service that we can control
    test_service_script = '''#!/bin/bash
echo "Test service started on port $1" > /app/service.log
# Create a marker file to show we started
touch /app/service-started.txt
# Simulate a service that listens on a port
exec nc -l -k -p $1 -e echo "HTTP/1.1 200 OK\\n\\nOK"
'''
    
    with open('/app/test-service.sh', 'w') as f:
        f.write(test_service_script)
    os.chmod('/app/test-service.sh', 0o755)
    
    # Create test config
    test_config = f"""SERVICE_NAME=test-monitor
SERVICE_CMD="/app/test-service.sh 9090"
CHECK_PORT=9090
CHECK_INTERVAL=1
MAX_RESTARTS=2
LOG_FILE=/app/test-monitor.log
"""
    
    with open('/app/monitor-test.conf', 'w') as f:
        f.write(test_config)
    
    # Start monitoring
    monitor_proc = subprocess.Popen(
        ['/app/service-monitor.sh', '/app/monitor-test.conf'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True
    )
    
    try:
        # Wait for service to start
        for _ in range(10):
            if os.path.exists('/app/service-started.txt'):
                break
            time.sleep(0.5)
        
        assert os.path.exists('/app/service-started.txt'), "Service didn't start"
        
        # Verify status file
        assert os.path.exists('/app/monitor-status.json'), "Status file missing"
        with open('/app/monitor-status.json', 'r') as f:
            status = json.load(f)
        assert status['service_name'] == 'test-monitor'
        assert status['status'] == 'running'
        assert 'pid' in status
        
        # Kill the service process
        service_pid = status['pid']
        if psutil.pid_exists(service_pid):
            psutil.Process(service_pid).terminate()
            time.sleep(0.5)
        
        # Wait for restart
        time.sleep(3)
        
        # Check logs for restart
        assert os.path.exists('/app/test-monitor.log'), "Log file not created"
        with open('/app/test-monitor.log', 'r') as f:
            logs = f.read()
        
        # Should contain restart information
        assert 'restart' in logs.lower() or 'Restart' in logs
        
        # Check updated status
        with open('/app/monitor-status.json', 'r') as f:
            status = json.load(f)
        assert status['restart_count'] > 0, "Restart count not incremented"
        
        # Test clean shutdown
        os.killpg(os.getpgid(monitor_proc.pid), signal.SIGTERM)
        monitor_proc.wait(timeout=5)
        
        # Verify summary file created
        assert os.path.exists('/app/restart-summary.txt'), "Summary file not created"
        with open('/app/restart-summary.txt', 'r') as f:
            summary = f.read()
        assert 'restart' in summary.lower()
        
    finally:
        # Cleanup
        try:
            os.killpg(os.getpgid(monitor_proc.pid), signal.SIGKILL)
        except:
            pass
        
        for f in ['/app/test-service.sh', '/app/monitor-test.conf', 
                 '/app/service-started.txt', '/app/monitor-status.json',
                 '/app/test-monitor.log', '/app/restart-summary.txt',
                 '/app/service.log']:
            if os.path.exists(f):
                os.remove(f)

def test_json_output_format():
    """Verify JSON output has correct schema."""
    # Create minimal config to test output format
    test_config = """SERVICE_NAME=json-test
SERVICE_CMD="sleep 3600"
CHECK_PORT=0
CHECK_INTERVAL=5
MAX_RESTARTS=1
LOG_FILE=/app/json-test.log
"""
    
    with open('/app/json-test.conf', 'w') as f:
        f.write(test_config)
    
    # Start and quickly stop to get status file
    proc = subprocess.Popen(
        ['/app/service-monitor.sh', '/app/json-test.conf'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True
    )
    
    time.sleep(1)
    os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    proc.wait(timeout=2)
    
    # Verify JSON format
    assert os.path.exists('/app/monitor-status.json')
    with open('/app/monitor-status.json', 'r') as f:
        data = json.load(f)
    
    required_keys = ['service_name', 'pid', 'status', 'restart_count', 'last_check', 'uptime_seconds']
    for key in required_keys:
        assert key in data, f"Missing key: {key}"
    
    assert isinstance(data['service_name'], str)
    assert isinstance(data['pid'], int) or data['pid'] is None
    assert data['status'] in ['running', 'restarting', 'failed', 'stopped']
    assert isinstance(data['restart_count'], int)
    assert isinstance(data['uptime_seconds'], (int, float))
    
    # Verify timestamp format (ISO 8601)
    try:
        datetime.fromisoformat(data['last_check'].replace('Z', '+00:00'))
    except ValueError:
        assert False, f"Invalid timestamp format: {data['last_check']}"
    
    # Cleanup
    for f in ['/app/json-test.conf', '/app/monitor-status.json', 
             '/app/json-test.log', '/app/restart-summary.txt']:
        if os.path.exists(f):
            os.remove(f)

def test_error_handling():
    """Test handling of invalid configurations."""
    # Test missing config file
    result = subprocess.run(
        ['/app/service-monitor.sh', '/app/nonexistent.conf'],
        capture_output=True,
        text=True
    )
    
    # Script should handle missing config gracefully
    assert result.returncode != 0 or 'error' in result.stderr.lower() or 'Error' in result.stdout
    
    # Test invalid port
    bad_config = """SERVICE_NAME=bad-port
SERVICE_CMD="echo test"
CHECK_PORT=99999  # Invalid port
CHECK_INTERVAL=5
MAX_RESTARTS=1
LOG_FILE=/app/bad.log
"""
    
    with open('/app/bad.conf', 'w') as f:
        f.write(bad_config)
    
    result = subprocess.run(
        ['/app/service-monitor.sh', '/app/bad.conf'],
        capture_output=True,
        text=True,
        timeout=2
    )
    
    # Should handle validation error
    assert result.returncode != 0 or 'invalid' in result.stderr.lower() or 'Invalid' in result.stdout
    
    # Cleanup
    if os.path.exists('/app/bad.conf'):
        os.remove('/app/bad.conf')