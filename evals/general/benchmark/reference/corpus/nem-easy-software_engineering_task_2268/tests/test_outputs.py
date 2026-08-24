import os
import json
import csv
import subprocess
import tempfile
import shutil
from datetime import datetime

def test_files_exist():
    """Verify all required files exist."""
    required_files = [
        '/app/Makefile',
        '/app/scripts/convert.py',
        '/app/scripts/validate.py'
    ]
    
    for file_path in required_files:
        assert os.path.exists(file_path), f"Missing required file: {file_path}"

def test_makefile_structure():
    """Verify Makefile has required targets."""
    with open('/app/Makefile', 'r') as f:
        content = f.read().lower()
    
    required_targets = ['convert:', 'validate:', 'clean:', 'all:']
    for target in required_targets:
        assert target in content, f"Makefile missing target: {target}"

def test_conversion_script():
    """Test that conversion script works correctly."""
    # Create a test directory to avoid interfering with main task
    test_dir = tempfile.mkdtemp()
    test_input = os.path.join(test_dir, 'input.json')
    test_output = os.path.join(test_dir, 'output.csv')
    
    # Copy the conversion script
    shutil.copy('/app/scripts/convert.py', test_dir)
    
    # Create test data
    test_data = [
        {"id": 1, "name": "Test User", "score": 100, "category": "Test"}
    ]
    
    with open(test_input, 'w') as f:
        json.dump(test_data, f)
    
    # Run the conversion script
    script_path = os.path.join(test_dir, 'convert.py')
    result = subprocess.run(
        ['python3', script_path, test_input, test_output],
        capture_output=True,
        text=True
    )
    
    assert result.returncode == 0, f"Script failed: {result.stderr}"
    assert os.path.exists(test_output), "Output file not created"
    
    # Verify CSV content
    with open(test_output, 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)
        
    assert len(rows) == 2, f"Expected 2 rows (header + data), got {len(rows)}"
    assert rows[0] == ['id', 'name', 'score', 'category'], f"Invalid headers: {rows[0]}"
    assert rows[1] == ['1', 'Test User', '100', 'Test'], f"Invalid data row: {rows[1]}"
    
    # Cleanup
    shutil.rmtree(test_dir)

def test_validation_script():
    """Test that validation script works correctly."""
    test_dir = tempfile.mkdtemp()
    test_csv = os.path.join(test_dir, 'test.csv')
    test_report = os.path.join(test_dir, 'report.txt')
    
    # Copy the validation script
    shutil.copy('/app/scripts/validate.py', test_dir)
    
    # Create valid CSV
    with open(test_csv, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['id', 'name', 'score', 'category'])
        writer.writerow(['1', 'Test', '100', 'A'])
    
    # Run validation script
    script_path = os.path.join(test_dir, 'validate.py')
    result = subprocess.run(
        ['python3', script_path, test_csv, test_report],
        capture_output=True,
        text=True
    )
    
    assert result.returncode == 0, f"Validation failed: {result.stderr}"
    assert os.path.exists(test_report), "Report file not created"
    
    with open(test_report, 'r') as f:
        report_lines = f.read().strip().split('\n')
    
    assert len(report_lines) >= 3, f"Report too short: {report_lines}"
    assert report_lines[0] == 'VALIDATION REPORT', f"Invalid report header: {report_lines[0]}"
    assert 'Status: PASS' in report_lines[1], f"Validation should pass: {report_lines[1]}"
    
    # Cleanup
    shutil.rmtree(test_dir)

def test_make_all():
    """Test running make all produces correct outputs."""
    # First clean any existing outputs
    if os.path.exists('/app/output'):
        shutil.rmtree('/app/output')
    
    # Create fresh output directory
    os.makedirs('/app/output', exist_ok=True)
    
    # Run make all
    result = subprocess.run(
        ['make', 'all'],
        cwd='/app',
        capture_output=True,
        text=True
    )
    
    assert result.returncode == 0, f"make all failed: {result.stderr}"
    
    # Check outputs
    assert os.path.exists('/app/output/results.csv'), "CSV file not created"
    assert os.path.exists('/app/output/validation_report.txt'), "Report file not created"
    
    # Verify CSV structure
    with open('/app/output/results.csv', 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)
    
    assert len(rows) == 4, f"Expected 4 rows (3 data + header), got {len(rows)}"
    assert rows[0] == ['id', 'name', 'score', 'category'], "Invalid headers"
    
    # Verify report
    with open('/app/output/validation_report.txt', 'r') as f:
        report = f.read()
    
    assert 'VALIDATION REPORT' in report, "Missing report header"
    assert 'Status: PASS' in report, "Validation should pass"

def test_make_clean():
    """Test that make clean removes generated files."""
    # First ensure files exist
    test_make_all()
    
    # Run make clean
    result = subprocess.run(
        ['make', 'clean'],
        cwd='/app',
        capture_output=True,
        text=True
    )
    
    assert result.returncode == 0, f"make clean failed: {result.stderr}"
    
    # Check files are removed
    assert not os.path.exists('/app/output/results.csv'), "CSV file not cleaned"
    assert not os.path.exists('/app/output/validation_report.txt'), "Report file not cleaned"
    
    # Output directory might still exist, that's OK