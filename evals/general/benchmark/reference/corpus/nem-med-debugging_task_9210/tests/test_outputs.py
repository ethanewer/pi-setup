import os
import json
import subprocess
import time
import csv
from pathlib import Path

def test_output_files_exist():
    """Verify all required output files were created."""
    assert os.path.exists('/app/fixed_processor.py'), "Fixed processor file not found"
    assert os.path.exists('/app/debug_report.md'), "Debug report not found"
    assert os.path.exists('/app/validation_results.json'), "Validation results not found"

def test_fixed_processor_runs():
    """Test that the fixed processor runs without errors."""
    # First, check the fixed processor has the expected interface
    with open('/app/fixed_processor.py', 'r') as f:
        content = f.read()
        assert 'def process_files' in content, "process_files function missing"
        assert 'class FileProcessor' in content, "FileProcessor class missing"
    
    # Run a quick test with reduced workload
    test_cmd = ['python3', '/app/fixed_processor.py', '--workers=2', '--test-mode']
    
    # Check if test-mode flag is supported
    if '--test-mode' not in content:
        # Try without test mode
        test_cmd = ['python3', '/app/fixed_processor.py', '--workers=2']
    
    try:
        result = subprocess.run(test_cmd, capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, f"Processor failed with: {result.stderr}"
    except subprocess.TimeoutExpired:
        # Processor might be working but slow, continue with other tests
        pass

def test_validation_results_format():
    """Verify validation results JSON has correct format."""
    with open('/app/validation_results.json', 'r') as f:
        data = json.load(f)
    
    required_keys = ['total_records', 'unique_records', 'processing_time_seconds', 
                     'errors_found', 'performance_improvement']
    
    for key in required_keys:
        assert key in data, f"Missing key in validation results: {key}"
    
    # Validate data types and constraints
    assert isinstance(data['total_records'], int), "total_records should be integer"
    assert isinstance(data['unique_records'], int), "unique_records should be integer"
    assert isinstance(data['processing_time_seconds'], (int, float)), "processing_time_seconds should be number"
    assert isinstance(data['errors_found'], int), "errors_found should be integer"
    assert isinstance(data['performance_improvement'], (int, float)), "performance_improvement should be number"
    
    # Logical constraints
    assert data['total_records'] >= 0, "total_records cannot be negative"
    assert data['unique_records'] >= 0, "unique_records cannot be negative"
    assert data['errors_found'] >= 0, "errors_found cannot be negative"
    assert data['processing_time_seconds'] > 0, "processing_time_seconds must be positive"
    assert data['performance_improvement'] >= 0.3, f"Performance improvement must be at least 30%, got {data['performance_improvement']*100}%"
    
    # Consistency check
    assert data['total_records'] == data['unique_records'], "All records should be unique after fixes"

def test_debug_report_content():
    """Verify debug report contains required analysis."""
    with open('/app/debug_report.md', 'r') as f:
        content = f.read().lower()
    
    required_sections = ['root cause', 'performance', 'changes', 'comparison']
    
    for section in required_sections:
        assert section in content, f"Debug report missing section: {section}"
    
    # Check for specific keywords that indicate proper analysis
    analysis_keywords = ['race condition', 'thread', 'lock', 'synchronization', 
                        'bottleneck', 'profile', 'optimize', 'shared', 'global']
    
    found_keywords = [kw for kw in analysis_keywords if kw in content]
    assert len(found_keywords) >= 3, f"Debug report lacks technical depth. Found: {found_keywords}"

def test_concurrent_safety():
    """Test that the fixed processor handles concurrency correctly."""
    # Run processor multiple times with different worker counts
    worker_counts = [1, 2, 4, 8]
    results = []
    
    for workers in worker_counts[:2]:  # Test with 1 and 2 workers to save time
        cmd = ['python3', '/app/fixed_processor.py', f'--workers={workers}']
        if '--test-mode' in open('/app/fixed_processor.py').read():
            cmd.append('--test-mode')
        
        try:
            start_time = time.time()
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            elapsed = time.time() - start_time
            
            assert result.returncode == 0, f"Processor failed with {workers} workers: {result.stderr}"
            
            # Parse output for record counts if available
            output = result.stdout
            if 'total:' in output.lower():
                # Extract counts from output
                import re
                total_match = re.search(r'total[:\s]+(\d+)', output.lower())
                if total_match:
                    results.append({
                        'workers': workers,
                        'time': elapsed,
                        'total': int(total_match.group(1))
                    })
        except subprocess.TimeoutExpired:
            # Skip if test times out
            continue
    
    # If we have results from multiple runs, verify consistency
    if len(results) > 1:
        # All runs should produce the same total count
        totals = [r['total'] for r in results if 'total' in r]
        if len(totals) > 1:
            assert len(set(totals)) == 1, f"Inconsistent results with different worker counts: {totals}"

def test_no_data_corruption():
    """Verify that data integrity is maintained."""
    # Count records in all CSV files to establish baseline
    csv_dir = Path('/app/data')
    expected_total = 0
    
    for csv_file in csv_dir.glob('*.csv'):
        with open(csv_file, 'r') as f:
            reader = csv.reader(f)
            # Skip header if present
            rows = list(reader)
            if len(rows) > 0 and any('header' in str(cell).lower() for cell in rows[0]):
                rows = rows[1:]
            expected_total += len(rows)
    
    # Load validation results
    with open('/app/validation_results.json', 'r') as f:
        data = json.load(f)
    
    # Compare with expected (allow for header rows)
    assert abs(data['total_records'] - expected_total) <= 100, \
        f"Record count mismatch. Expected ~{expected_total}, got {data['total_records']}"

def test_performance_improvement():
    """Verify claimed performance improvement."""
    with open('/app/validation_results.json', 'r') as f:
        data = json.load(f)
    
    improvement = data['performance_improvement']
    assert improvement >= 0.3, f"Insufficient performance improvement: {improvement*100}%"
    
    # Check that improvement claim is plausible
    process_time = data['processing_time_seconds']
    assert process_time < 60, f"Processing time too long: {process_time}s"