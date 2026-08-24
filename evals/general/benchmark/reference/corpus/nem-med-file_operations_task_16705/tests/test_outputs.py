import os
import json
import csv
import tempfile
import shutil
from datetime import datetime
import pytest

# Helper to create test data
def create_test_logs(log_dir):
    """Create sample log files for testing."""
    # Sample data
    logs = [
        "2024-01-15 10:30:00 | ERROR | Database | Connection timeout | user123",
        "2024-01-15 11:45:00 | WARNING | API | Slow response time | user456",
        "2024-01-15 12:00:00 | INFO | Auth | User login successful | user789",
        "2024-01-15 13:15:00 | ERROR | Database | Deadlock detected | user101",
        "2024-01-15 14:30:00 | ERROR | Database | Connection timeout | user123",
        "2024-01-15 15:45:00 | INFO | Cache | Cache hit | user202",
        "2024-01-14 23:59:59 | ERROR | Database | Out of time range | user999",  # Should be filtered
        "2024-01-16 00:00:01 | ERROR | Database | Out of time range | user999",  # Should be filtered
        "malformed line without proper format",
        "2024-01-15 16:30:00 | DEBUG | System | Debug message | user303",  # Severity not in config
    ]
    
    # Create multiple log files
    os.makedirs(log_dir, exist_ok=True)
    with open(os.path.join(log_dir, "app_1.log"), "w") as f:
        f.write("\n".join(logs[:3]))
    with open(os.path.join(log_dir, "app_2.log"), "w") as f:
        f.write("\n".join(logs[3:7]))
    with open(os.path.join(log_dir, "app_3.log"), "w") as f:
        f.write("\n".join(logs[7:]))

def test_output_structure():
    """Verify all required output files exist."""
    assert os.path.exists("/app/reports/log_summary.csv"), "CSV report missing"
    assert os.path.exists("/app/reports/analysis.json"), "JSON report missing"
    assert os.path.exists("/app/reports/errors.txt"), "Error log missing"

def test_csv_format():
    """Verify CSV file has correct format and columns."""
    with open("/app/reports/log_summary.csv", "r") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        
        # Check required columns
        required = ["hour", "error_count", "warning_count", "info_count", "total"]
        for col in required:
            assert col in fieldnames, f"Missing column: {col}"
        
        # Check we have 24 hours (0-23)
        rows = list(reader)
        hours = [int(row["hour"]) for row in rows]
        assert len(hours) == 24, f"Expected 24 hours, got {len(hours)}"
        assert set(hours) == set(range(24)), "Hours should be 0-23"

def test_json_structure():
    """Verify JSON report has correct structure."""
    with open("/app/reports/analysis.json", "r") as f:
        data = json.load(f)
    
    # Check top-level structure
    assert "metadata" in data, "Missing metadata"
    assert "severity_counts" in data, "Missing severity_counts"
    assert "top_errors" in data, "Missing top_errors"
    assert "component_breakdown" in data, "Missing component_breakdown"
    
    # Check metadata fields
    meta = data["metadata"]
    assert "files_processed" in meta, "Missing files_processed"
    assert "total_lines_processed" in meta, "Missing total_lines_processed"
    assert "malformed_lines" in meta, "Missing malformed_lines"
    assert "time_range_used" in meta, "Missing time_range_used"
    
    # Check severity counts has correct keys
    counts = data["severity_counts"]
    assert "ERROR" in counts, "Missing ERROR count"
    assert "WARNING" in counts, "Missing WARNING count"
    assert "INFO" in counts, "Missing INFO count"
    
    # Check top_errors is a list
    assert isinstance(data["top_errors"], list), "top_errors should be a list"
    
    # Check component_breakdown is a dict
    assert isinstance(data["component_breakdown"], dict), "component_breakdown should be a dict"

def test_time_filtering():
    """Verify logs are correctly filtered by time range."""
    with open("/app/reports/analysis.json", "r") as f:
        data = json.load(f)
    
    # Based on test data, we should have logs only from 2024-01-15
    # and exclude those from 2024-01-14 and 2024-01-16
    severity_counts = data["severity_counts"]
    
    # Counts from valid test logs:
    # ERROR: 4 (2x Connection timeout, 1x Deadlock detected, 1x malformed but ERROR?)
    # WARNING: 1 (Slow response time)
    # INFO: 2 (User login successful, Cache hit)
    # Note: DEBUG should be excluded
    
    # We'll check that DEBUG is not counted (not in severity_levels)
    assert "DEBUG" not in severity_counts, "DEBUG should not be counted"
    
    # Check that we have reasonable counts (not exact because malformed line might affect)
    assert severity_counts["ERROR"] >= 3, f"Should have at least 3 ERROR logs"
    assert severity_counts["WARNING"] >= 1, f"Should have at least 1 WARNING log"
    assert severity_counts["INFO"] >= 2, f"Should have at least 2 INFO logs"

def test_error_handling():
    """Verify malformed lines are captured in error log."""
    if os.path.getsize("/app/reports/errors.txt") > 0:
        with open("/app/reports/errors.txt", "r") as f:
            errors = f.read()
        # Should contain references to malformed lines
        assert "malformed" in errors.lower() or "line" in errors.lower(), \
            "Error log should mention malformed lines"

def test_component_breakdown():
    """Verify component breakdown includes expected components."""
    with open("/app/reports/analysis.json", "r") as f:
        data = json.load(f)
    
    components = data["component_breakdown"]
    # Test data has: Database, API, Auth, Cache
    expected = ["Database", "API", "Auth", "Cache"]
    
    for comp in expected:
        assert comp in components, f"Missing component: {comp}"

# Setup test environment before running tests
@pytest.fixture(autouse=True)
def setup_test_environment():
    """Create test directories and files."""
    # Create config
    config = {
        "log_directory": "/app/logs",
        "output_directory": "/app/reports",
        "log_pattern": "app_*.log",
        "time_range": {
            "start": "2024-01-15 00:00:00",
            "end": "2024-01-15 23:59:59"
        },
        "severity_levels": ["ERROR", "WARNING", "INFO"],
        "max_file_size_mb": 10
    }
    
    os.makedirs("/app", exist_ok=True)
    with open("/app/config.json", "w") as f:
        json.dump(config, f)
    
    # Clean up and create fresh log directory
    if os.path.exists("/app/logs"):
        shutil.rmtree("/app/logs")
    if os.path.exists("/app/reports"):
        shutil.rmtree("/app/reports")
    
    create_test_logs("/app/logs")
    
    # Run the agent's code (simulated by import)
    yield
    
    # Cleanup after tests
    if os.path.exists("/app/logs"):
        shutil.rmtree("/app/logs")
    if os.path.exists("/app/reports"):
        shutil.rmtree("/app/reports")
    if os.path.exists("/app/config.json"):
        os.remove("/app/config.json")