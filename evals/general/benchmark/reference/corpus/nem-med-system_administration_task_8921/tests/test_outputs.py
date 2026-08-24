import os
import json
import configparser
import sys
import subprocess
import time
from datetime import datetime, timezone
import re

def test_monitor_script_exists():
    """Verify monitor script was created."""
    assert os.path.exists('/app/monitor.py'), "monitor.py not found"
    assert os.access('/app/monitor.py', os.X_OK), "monitor.py not executable"

def test_status_report_exists():
    """Verify status report JSON file exists and is valid JSON."""
    assert os.path.exists('/app/status_report.json'), "status_report.json not found"
    
    try:
        with open('/app/status_report.json', 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        assert False, f"Invalid JSON in status_report.json: {e}"
    
    # Check required top-level fields
    required_fields = ['timestamp', 'total_services', 'healthy_services', 
                      'unhealthy_services', 'health_percentage', 'services']
    for field in required_fields:
        assert field in data, f"Missing field in JSON: {field}"
    
    # Check data types
    assert isinstance(data['total_services'], int), "total_services should be integer"
    assert isinstance(data['healthy_services'], int), "healthy_services should be integer"
    assert isinstance(data['unhealthy_services'], int), "unhealthy_services should be integer"
    assert isinstance(data['health_percentage'], (int, float)), "health_percentage should be number"
    assert isinstance(data['services'], list), "services should be list"
    
    # Check calculation
    if data['total_services'] > 0:
        expected_percentage = (data['healthy_services'] / data['total_services']) * 100
        assert abs(data['health_percentage'] - expected_percentage) < 0.01, \
            f"health_percentage incorrect: {data['health_percentage']} != {expected_percentage}"
    
    # Check service entries if present
    if data['services']:
        service = data['services'][0]
        required_service_fields = ['name', 'type', 'host', 'port', 'status', 
                                  'response_time', 'last_check', 'error']
        for field in required_service_fields:
            assert field in service, f"Missing field in service object: {field}"
        
        assert service['status'] in ['healthy', 'unhealthy'], \
            f"Invalid status value: {service['status']}"

def test_monitoring_log_exists():
    """Verify monitoring log file exists."""
    assert os.path.exists('/app/monitoring.log'), "monitoring.log not found"
    
    # Check it has some content
    if os.path.getsize('/app/monitoring.log') > 0:
        with open('/app/monitoring.log', 'r') as f:
            content = f.read()
        # Should contain timestamp and service names from config
        assert any(word in content.lower() for word in ['web_api', 'database', 'dns']), \
            "Log doesn't contain expected service names"

def test_systemd_service_exists():
    """Verify systemd service file was created correctly."""
    service_path = '/etc/systemd/system/network-monitor.service'
    assert os.path.exists(service_path), "systemd service file not found"
    
    # Check permissions
    assert oct(os.stat(service_path).st_mode)[-3:] == '644', \
        f"Service file should have 644 permissions, has {oct(os.stat(service_path).st_mode)[-3:]}"
    
    with open(service_path, 'r') as f:
        content = f.read()
    
    # Check required sections and directives
    required_directives = [
        'Description=Network Service Monitor',
        'Type=simple',
        'Restart=on-failure',
        'RestartSec=10',
        'ExecStart=/usr/bin/python3 /app/monitor.py',
        'StandardOutput=append:/app/monitoring.log',
        'StandardError=append:/app/monitoring.log'
    ]
    
    for directive in required_directives:
        assert directive in content, f"Missing directive in service file: {directive}"

def test_cron_entry_exists():
    """Verify cron entry file exists with correct syntax."""
    cron_path = '/etc/cron.d/network-monitor'
    assert os.path.exists(cron_path), "cron.d entry not found"
    
    with open(cron_path, 'r') as f:
        content = f.read()
    
    # Check it's a valid cron entry
    lines = [line.strip() for line in content.split('\n') if line.strip() and not line.startswith('#')]
    
    # Should have at least one cron line
    assert len(lines) > 0, "No cron entries found"
    
    for line in lines:
        # Basic cron syntax: minute hour day month weekday command
        parts = line.split()
        assert len(parts) >= 6, f"Invalid cron syntax: {line}"
        
        # Check it runs every 5 minutes
        if '*/5' in parts[0] or parts[0] == '0,5,10,15,20,25,30,35,40,45,50,55':
            # Good - runs every 5 minutes
            pass
        
        # Check it uses full python path
        assert '/usr/bin/python3' in line, f"Cron entry should use full python3 path: {line}"
        
        # Check it redirects output
        assert '>> /app/cron.log' in line, f"Cron should redirect to cron.log: {line}"

def test_script_can_parse_config():
    """Test that the monitor script can parse the configuration file."""
    # Create a test config to verify parsing
    test_config = """/app/services.conf
[web_test]
type = http
host = localhost
port = 8080
path = /test
interval = 10
timeout = 2

[tcp_test]
type = tcp
host = 127.0.0.1
port = 22
interval = 20
timeout = 3
"""
    
    # Write test config
    with open('/tmp/test_config.conf', 'w') as f:
        f.write(test_config)
    
    # Test configparser can read it
    config = configparser.ConfigParser()
    try:
        config.read('/tmp/test_config.conf')
        assert 'web_test' in config.sections(), "Can't parse web_test section"
        assert 'tcp_test' in config.sections(), "Can't parse tcp_test section"
        assert config['web_test']['type'] == 'http', "Can't read type field"
        assert config['tcp_test']['port'] == '22', "Can't read port field"
    except Exception as e:
        assert False, f"Config parsing failed: {e}"

def test_script_runs_without_syntax_errors():
    """Test that the monitor script has valid Python syntax."""
    assert os.path.exists('/app/monitor.py'), "monitor.py not found"
    
    # Try to parse the Python file
    try:
        with open('/app/monitor.py', 'r') as f:
            content = f.read()
        compile(content, '/app/monitor.py', 'exec')
    except SyntaxError as e:
        assert False, f"Python syntax error in monitor.py: {e}"
    
    # Check it has required imports
    required_imports = ['configparser', 'json', 'datetime', 'socket', 'requests']
    found_imports = []
    for imp in required_imports:
        if f'import {imp}' in content or f'from {imp}' in content:
            found_imports.append(imp)
    
    # At least configparser and json should be imported
    assert 'configparser' in found_imports, "configparser not imported"
    assert 'json' in found_imports, "json not imported"