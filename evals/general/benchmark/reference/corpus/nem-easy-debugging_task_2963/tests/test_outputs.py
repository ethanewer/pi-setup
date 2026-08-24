import os
import json
import pytest
import csv

def test_output_exists():
    """Verify output file was created."""
    assert os.path.exists('/app/output/validation_report.json'), "Output file not found"

def test_output_correct():
    """Verify output content is correct."""
    # Load output file
    with open('/app/output/validation_report.json', 'r') as f:
        report = json.load(f)
    
    # Check required keys exist
    required_keys = ['total_records', 'valid_records', 'invalid_records', 'errors']
    for key in required_keys:
        assert key in report, f"Missing key: {key}"
    
    # Check data types
    assert isinstance(report['total_records'], int), "total_records must be integer"
    assert isinstance(report['valid_records'], int), "valid_records must be integer"
    assert isinstance(report['invalid_records'], int), "invalid_records must be integer"
    assert isinstance(report['errors'], list), "errors must be a list"
    
    # Check mathematical consistency
    assert report['total_records'] == report['valid_records'] + report['invalid_records'], \
        "Total records must equal valid + invalid records"
    
    # Count rows in input file (excluding header)
    with open('/app/data/input.csv', 'r') as f:
        reader = csv.reader(f)
        input_rows = sum(1 for _ in reader) - 1  # Exclude header
    
    assert report['total_records'] == input_rows, \
        f"Report says {report['total_records']} records but input has {input_rows}"
    
    # Check error structure
    for error in report['errors']:
        assert 'line_number' in error, "Error missing line_number"
        assert 'field' in error, "Error missing field"
        assert 'error' in error, "Error missing error message"
        assert isinstance(error['line_number'], int), "line_number must be integer"
        assert isinstance(error['field'], str), "field must be string"
        assert isinstance(error['error'], str), "error must be string"
        assert error['line_number'] > 0, "line_number must be positive"
    
    # Verify script can be run without errors
    import subprocess
    result = subprocess.run(['python3', '/app/main.py'], 
                          capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"