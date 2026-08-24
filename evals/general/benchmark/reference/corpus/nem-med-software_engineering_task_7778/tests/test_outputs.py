import os
import json
import yaml
import subprocess
import time
import sys
from pathlib import Path

def test_output_files_exist():
    """Verify all required output files were created."""
    required_files = [
        '/app/process_data.py',
        '/app/Makefile',
        '/app/output/aggregated_data.json',
        '/app/output/validation_report.md',
        '/app/output/process.log'
    ]
    
    missing = []
    for file_path in required_files:
        if not os.path.exists(file_path):
            missing.append(file_path)
    
    assert len(missing) == 0, f"Missing files: {missing}"

def test_makefile_targets():
    """Verify Makefile targets work correctly."""
    
    # First clean up
    subprocess.run(['make', 'clean'], cwd='/app', capture_output=True)
    
    # Test build target
    result = subprocess.run(['make', 'build'], cwd='/app', capture_output=True)
    assert result.returncode == 0, f"make build failed: {result.stderr.decode()}"
    
    # Verify build created outputs
    assert os.path.exists('/app/output/aggregated_data.json'), "aggregated_data.json not created"
    
    # Test validate target
    result = subprocess.run(['make', 'validate'], cwd='/app', capture_output=True)
    assert result.returncode == 0, f"make validate failed: {result.stderr.decode()}"
    
    # Test clean target
    result = subprocess.run(['make', 'clean'], cwd='/app', capture_output=True)
    assert result.returncode == 0, f"make clean failed: {result.stderr.decode()}"
    
    # Verify clean removed outputs but not scripts
    assert not os.path.exists('/app/output/aggregated_data.json'), "clean didn't remove aggregated_data.json"
    assert os.path.exists('/app/process_data.py'), "clean removed process_data.py (shouldn't)"

def test_json_output_valid():
    """Verify JSON output is valid and has required structure."""
    if not os.path.exists('/app/output/aggregated_data.json'):
        # Re-run build if needed
        subprocess.run(['make', 'build'], cwd='/app', capture_output=True)
    
    with open('/app/output/aggregated_data.json', 'r') as f:
        data = json.load(f)
    
    # Check required top-level keys
    required_keys = ['metadata', 'sensors', 'aggregations', 'errors']
    for key in required_keys:
        assert key in data, f"Missing key in JSON output: {key}"
    
    # Check metadata structure
    assert 'processed_count' in data['metadata'], "Missing processed_count in metadata"
    assert 'success_count' in data['metadata'], "Missing success_count in metadata"
    assert 'error_count' in data['metadata'], "Missing error_count in metadata"
    
    # Validate success rate
    success_rate = data['metadata']['success_count'] / max(1, data['metadata']['processed_count'])
    assert success_rate >= 0.95, f"Success rate too low: {success_rate:.2%}"

def test_build_yaml_fixed():
    """Verify build.yaml has been fixed with correct paths."""
    with open('/app/build.yaml', 'r') as f:
        config = yaml.safe_load(f)
    
    # Check for absolute paths
    for step in config.get('steps', []):
        if 'input' in step:
            input_path = step['input']
            assert input_path.startswith('/app/'), f"Relative path found: {input_path}"
        
        if 'output' in step:
            output_path = step['output']
            assert output_path.startswith('/app/'), f"Relative path found: {output_path}"
    
    # Check dependencies are declared
    assert 'dependencies' in config, "No dependencies section in build.yaml"
    assert len(config['dependencies']) > 0, "Empty dependencies in build.yaml"
    
    # Check execution order
    steps = config.get('steps', [])
    assert len(steps) >= 3, f"Too few steps: {len(steps)}"
    
    # Check environment variables
    assert 'environment' in config, "No environment section in build.yaml"

def test_process_data_script():
    """Verify the processing script handles errors properly."""
    # Create a test with bad data to see error handling
    script_path = '/app/process_data.py'
    
    # First check script exists and is executable
    assert os.path.exists(script_path), "process_data.py not found"
    
    # Check it has proper imports and structure
    with open(script_path, 'r') as f:
        content = f.read()
    
    # Check for required functionality
    assert 'import json' in content, "Missing json import"
    assert 'import csv' in content or 'import pandas' in content, "Missing CSV handling"
    assert 'def validate' in content or 'validation' in content.lower(), "Missing validation function"
    assert 'try:' in content and 'except:' in content, "Missing error handling"
    
    # Test script runs
    result = subprocess.run([sys.executable, script_path, '--test'], 
                          cwd='/app', capture_output=True)
    # Accept any return code for test mode, but should not crash
    if result.returncode != 0:
        # If not in test mode, run normally
        result = subprocess.run([sys.executable, script_path], 
                              cwd='/app', capture_output=True, timeout=30)
        assert result.returncode == 0, f"Script failed: {result.stderr.decode()}"

def test_validation_report():
    """Verify validation report has required content."""
    if not os.path.exists('/app/output/validation_report.md'):
        # Re-run validate if needed
        subprocess.run(['make', 'validate'], cwd='/app', capture_output=True)
    
    with open('/app/output/validation_report.md', 'r') as f:
        content = f.read()
    
    # Check for required sections
    required_sections = [
        'Summary Statistics',
        'Schema Compliance',
        'Validation Errors',
        'Processing Time'
    ]
    
    for section in required_sections:
        assert section in content, f"Missing section: {section}"
    
    # Check for metrics
    metrics = ['row count', 'column count', 'error count', 'percentage']
    found_metrics = sum(1 for metric in metrics if metric in content.lower())
    assert found_metrics >= 2, f"Missing metrics in report, found {found_metrics}"

def test_log_file():
    """Verify log file exists and has content."""
    log_path = '/app/output/process.log'
    
    if not os.path.exists(log_path):
        # Run build to generate log
        subprocess.run(['make', 'build'], cwd='/app', capture_output=True)
    
    assert os.path.exists(log_path), "Log file not created"
    
    # Check log has content (may be empty if no errors, but should exist)
    if os.path.getsize(log_path) > 0:
        with open(log_path, 'r') as f:
            content = f.read()
        # If there's content, check it looks like a log
        assert any(level in content.lower() for level in ['info', 'error', 'warning', 'debug']), \
            "Log doesn't contain standard log levels"