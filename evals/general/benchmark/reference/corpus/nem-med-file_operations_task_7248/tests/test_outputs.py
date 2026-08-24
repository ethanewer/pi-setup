import os
import json
import shutil
import tempfile
import pytest
from datetime import datetime
from pathlib import Path

def setup_test_files():
    """Create test log files with various formats and edge cases."""
    test_dir = Path("/app/logs")
    test_dir.mkdir(parents=True, exist_ok=True)
    
    # Clean up existing files
    for item in test_dir.rglob("*"):
        if item.is_file():
            item.unlink()
        elif item.is_dir():
            shutil.rmtree(item)
    
    # Create various log files
    logs = [
        {
            "path": "system/app.log",
            "content": """2024-01-15 10:30:00 INFO Application started
2024-01-15 10:31:00 ERROR Database connection failed
2024-01-15 10:32:00 WARN High memory usage
2024-01-15 10:33:00 INFO Connection restored
2024-01-15 10:34:00 ERROR Authentication failure
2024-01-15 10:35:00 ERROR File not found
"""
        },
        {
            "path": "network/firewall.txt",
            "content": """01/15/2024 09:00:00 INFO Firewall rule applied
01/15/2024 09:01:00 WARN Unusual traffic pattern
01/15/2024 09:02:00 INFO Traffic normalized
"""
        },
        {
            "path": "database/errors.log",
            "content": """15-Jan-2024 08:00:00 ERROR Deadlock detected
15-Jan-2024 08:01:00 ERROR Query timeout
15-Jan-2024 08:02:00 WARN Slow query execution
15-Jan-2024 08:03:00 ERROR Constraint violation
15-Jan-2024 08:04:00 ERROR Connection pool exhausted
"""
        },
        {
            "path": "system/clean.log",
            "content": """2024-01-15 11:00:00 INFO Cleanup started
2024-01-15 11:01:00 INFO Temp files removed
2024-01-15 11:02:00 INFO Cleanup completed
"""
        },
        {
            "path": "corrupted/binary.bin",
            "content": b"\x00\x01\x02\x03\x04\x05"  # Binary data
        }
    ]
    
    for log in logs:
        file_path = test_dir / log["path"]
        file_path.parent.mkdir(parents=True, exist_ok=True)
        
        if isinstance(log["content"], bytes):
            with open(file_path, "wb") as f:
                f.write(log["content"])
        else:
            with open(file_path, "w", encoding="utf-8") as f:
                f.write(log["content"])

@pytest.fixture(autouse=True)
def setup_and_teardown():
    """Set up test files before each test and clean up after."""
    # Clean up archive directory
    archive_dir = Path("/app/archive")
    if archive_dir.exists():
        shutil.rmtree(archive_dir)
    
    # Setup test log files
    setup_test_files()
    
    yield
    
    # Cleanup after tests
    if archive_dir.exists():
        shutil.rmtree(archive_dir)

def test_archive_structure_exists():
    """Verify archive directory structure was created."""
    assert os.path.exists("/app/archive"), "Archive directory not created"
    assert os.path.exists("/app/archive/processed_logs"), "Processed logs directory not created"
    assert os.path.exists("/app/archive/processed_logs/high_priority"), "High priority directory not created"
    assert os.path.exists("/app/archive/processed_logs/medium_priority"), "Medium priority directory not created"
    assert os.path.exists("/app/archive/processed_logs/low_priority"), "Low priority directory not created"
    assert os.path.exists("/app/archive/summary"), "Summary directory not created"

def test_analysis_json_exists():
    """Verify analysis.json was created and is valid JSON."""
    assert os.path.exists("/app/archive/summary/analysis.json"), "analysis.json not found"
    
    with open("/app/archive/summary/analysis.json", "r") as f:
        data = json.load(f)
    
    # Check required structure
    assert "analysis_timestamp" in data, "Missing analysis_timestamp"
    assert "summary" in data, "Missing summary section"
    assert "top_error_files" in data, "Missing top_error_files"
    assert "file_statistics" in data, "Missing file_statistics"
    
    summary = data["summary"]
    required_summary_fields = [
        "total_files_processed",
        "total_error_count", 
        "total_warning_count",
        "average_file_size_bytes",
        "most_recent_log_timestamp",
        "processing_duration_seconds"
    ]
    
    for field in required_summary_fields:
        assert field in summary, f"Missing summary field: {field}"

def test_file_categorization():
    """Verify log files are correctly categorized by error count."""
    # Check files are copied to correct priority directories
    high_priority = Path("/app/archive/processed_logs/high_priority")
    medium_priority = Path("/app/archive/processed_logs/medium_priority")
    low_priority = Path("/app/archive/processed_logs/low_priority")
    
    # database/errors.log has 4 errors → high priority
    assert (high_priority / "database/errors.log").exists(), "High error file not in high_priority"
    
    # system/app.log has 3 errors → medium priority (1-10 errors)
    assert (medium_priority / "system/app.log").exists(), "Medium error file not in medium_priority"
    
    # network/firewall.txt has 0 errors, 1 warning → low priority
    assert (low_priority / "network/firewall.txt").exists(), "Low error file not in low_priority"
    
    # system/clean.log has 0 errors → low priority
    assert (low_priority / "system/clean.log").exists(), "Clean log not in low_priority"

def test_directory_structure_preserved():
    """Verify directory structure is preserved in archive."""
    # Check that subdirectories exist in each priority folder
    high_priority = Path("/app/archive/processed_logs/high_priority")
    assert (high_priority / "database").exists(), "Subdirectory not preserved in high_priority"
    
    medium_priority = Path("/app/archive/processed_logs/medium_priority")
    assert (medium_priority / "system").exists(), "Subdirectory not preserved in medium_priority"
    
    low_priority = Path("/app/archive/processed_logs/low_priority")
    assert (low_priority / "network").exists(), "Subdirectory not preserved in low_priority"
    assert (low_priority / "system").exists(), "Subdirectory not preserved in low_priority"

def test_failed_files_recorded():
    """Verify corrupted/unreadable files are recorded."""
    failed_file = Path("/app/archive/failed_files.txt")
    if failed_file.exists():
        with open(failed_file, "r") as f:
            content = f.read()
        # The binary file should be recorded as failed
        assert "corrupted/binary.bin" in content, "Binary file not recorded in failed_files.txt"

def test_analysis_correctness():
    """Verify analysis results are mathematically correct."""
    with open("/app/archive/summary/analysis.json", "r") as f:
        data = json.load(f)
    
    summary = data["summary"]
    
    # Check totals match expected values from test data
    assert summary["total_files_processed"] == 4, f"Expected 4 processed files, got {summary['total_files_processed']}"
    assert summary["total_error_count"] == 7, f"Expected 7 total errors, got {summary['total_error_count']}"
    assert summary["total_warning_count"] == 2, f"Expected 2 total warnings, got {summary['total_warning_count']}"
    
    # Check top error files
    top_files = data["top_error_files"]
    assert len(top_files) == 3, f"Expected 3 top error files, got {len(top_files)}"
    
    # First file should have highest error count
    assert top_files[0]["error_count"] >= top_files[1]["error_count"], "Top error files not sorted correctly"
    assert top_files[1]["error_count"] >= top_files[2]["error_count"], "Top error files not sorted correctly"
    
    # Check file statistics
    stats = data["file_statistics"]
    assert len(stats) == 4, f"Expected 4 file statistics entries, got {len(stats)}"
    
    # Verify each file has correct metadata
    for stat in stats:
        assert "file_path" in stat
        assert "size_bytes" in stat and stat["size_bytes"] > 0
        assert "line_count" in stat and stat["line_count"] > 0
        assert "error_count" in stat
        assert "warning_count" in stat
        assert "last_timestamp" in stat

def test_file_copy_not_move():
    """Verify original files are not moved (copied only)."""
    # Original files should still exist
    assert os.path.exists("/app/logs/system/app.log"), "Original file was moved instead of copied"
    assert os.path.exists("/app/logs/database/errors.log"), "Original file was moved instead of copied"
    assert os.path.exists("/app/logs/network/firewall.txt"), "Original file was moved instead of copied"
    assert os.path.exists("/app/logs/system/clean.log"), "Original file was moved instead of copied"

def test_timestamp_extraction():
    """Verify timestamps are correctly extracted and formatted."""
    with open("/app/archive/summary/analysis.json", "r") as f:
        data = json.load(f)
    
    summary = data["summary"]
    # Most recent timestamp should be from the last log entry
    # In test data, last timestamp is from system/clean.log: "2024-01-15 11:02:00"
    assert "2024-01-15 11:02:00" in summary["most_recent_log_timestamp"], \
        f"Most recent timestamp incorrect: {summary['most_recent_log_timestamp']}"
    
    # Check file statistics have timestamps
    for stat in data["file_statistics"]:
        assert "last_timestamp" in stat and stat["last_timestamp"], \
            f"Missing last_timestamp for {stat['file_path']}"