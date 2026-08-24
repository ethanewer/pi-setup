import os
import json
import time
import subprocess
import sys
from pathlib import Path

def test_output_exists():
    """Verify required files were created."""
    assert os.path.exists('/app/file_processor.py'), "Fixed script not found"
    assert os.path.exists('/app/debug_report.json'), "Debug report not found"
    
def test_debug_report_format():
    """Verify debug report has correct structure."""
    with open('/app/debug_report.json', 'r') as f:
        report = json.load(f)
    
    required_keys = {
        'original_execution_time', 'fixed_execution_time',
        'bottlenecks_found', 'fixes_applied',
        'thread_safe', 'output_matches_baseline'
    }
    assert required_keys.issubset(report.keys()), f"Missing keys in report: {required_keys - set(report.keys())}"
    
    assert isinstance(report['original_execution_time'], (int, float)), "original_execution_time must be numeric"
    assert isinstance(report['fixed_execution_time'], (int, float)), "fixed_execution_time must be numeric"
    assert isinstance(report['bottlenecks_found'], list), "bottlenecks_found must be a list"
    assert isinstance(report['fixes_applied'], list), "fixes_applied must be a list"
    assert isinstance(report['thread_safe'], bool), "thread_safe must be boolean"
    assert isinstance(report['output_matches_baseline'], bool), "output_matches_baseline must be boolean"

def test_performance_improvement():
    """Verify fixed script meets performance target."""
    with open('/app/debug_report.json', 'r') as f:
        report = json.load(f)
    
    # Check if fixed time is ≤ 10 seconds
    assert report['fixed_execution_time'] <= 10.0, f"Performance target not met: {report['fixed_execution_time']}s > 10s"
    
    # Check if there's significant improvement
    improvement_ratio = report['original_execution_time'] / report['fixed_execution_time']
    assert improvement_ratio >= 5.0, f"Insufficient improvement: {improvement_ratio:.1f}x (expected ≥5x)"

def test_correctness():
    """Verify output matches baseline."""
    # Import the fixed module
    sys.path.insert(0, '/app')
    import file_processor
    
    # Run the fixed processor
    result = file_processor.process_all_logs('/app/logs/')
    
    # Load baseline
    with open('/app/performance_baseline.json', 'r') as f:
        baseline = json.load(f)
    
    # Compare results
    assert result == baseline, "Output does not match baseline"
    
def test_script_executes():
    """Verify script runs without errors."""
    start_time = time.time()
    result = subprocess.run(
        [sys.executable, '/app/file_processor.py'],
        capture_output=True,
        text=True,
        timeout=15  # Should complete within 15 seconds
    )
    end_time = time.time()
    
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    assert end_time - start_time <= 15, "Script timed out (should complete within 15 seconds)"

def test_no_race_conditions():
    """Verify thread safety indicators in report."""
    with open('/app/debug_report.json', 'r') as f:
        report = json.load(f)
    
    assert report['thread_safe'] == True, "Report indicates thread safety issues"
    
    # Check that fixes mention thread safety
    fixes = ' '.join(report['fixes_applied']).lower()
    thread_keywords = ['lock', 'race', 'thread', 'concurrent', 'synchroniz', 'atomic', 'queue']
    has_thread_fix = any(keyword in fixes for keyword in thread_keywords)
    assert has_thread_fix, "No thread safety fixes mentioned"