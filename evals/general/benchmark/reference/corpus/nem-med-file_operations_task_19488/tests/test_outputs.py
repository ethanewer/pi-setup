import os
import json
import zipfile
import tempfile
import hashlib
from datetime import datetime
import pytest

def test_output_files_exist():
    """Verify all required output files were created."""
    required_files = [
        '/app/output/validation_report.txt',
        '/app/output/reconciled_data.json', 
        '/app/output/archive.zip',
        '/app/output/summary.txt'
    ]
    
    for file_path in required_files:
        assert os.path.exists(file_path), f"Missing output file: {file_path}"

def test_validation_report_format():
    """Verify validation report contains required sections."""
    with open('/app/output/validation_report.txt', 'r') as f:
        content = f.read()
    
    # Check for required sections
    required_terms = ['Total rows', 'valid rows', 'invalid rows', 'examples']
    for term in required_terms:
        assert term.lower() in content.lower(), f"Validation report missing '{term}' section"

def test_reconciled_json_valid():
    """Verify JSON output is valid and has correct structure."""
    with open('/app/output/reconciled_data.json', 'r') as f:
        data = json.load(f)
    
    # Check structure
    assert 'statistics' in data
    assert 'transactions' in data
    assert isinstance(data['statistics'], dict)
    assert isinstance(data['transactions'], list)
    
    # Check required statistics fields
    required_stats = ['total_transactions', 'verified', 'mismatches', 'unique_source_a', 'unique_source_b']
    for stat in required_stats:
        assert stat in data['statistics']
        assert isinstance(data['statistics'][stat], int)

def test_archive_integrity():
    """Verify ZIP archive can be extracted and contains correct files."""
    archive_path = '/app/output/archive.zip'
    
    # Check archive exists and is valid ZIP
    assert os.path.exists(archive_path)
    assert zipfile.is_zipfile(archive_path)
    
    # Count files in archive
    with zipfile.ZipFile(archive_path, 'r') as zf:
        file_list = zf.namelist()
        
        # Should have at least 5 files (3 input + 2 output)
        assert len(file_list) >= 5, f"Archive should contain at least 5 files, found {len(file_list)}"
        
        # Check for expected file types
        has_csv = any(f.endswith('.csv') for f in file_list)
        has_json = any(f.endswith('.json') for f in file_list)
        has_txt = any(f.endswith('.txt') for f in file_list)
        
        assert has_csv, "Archive missing CSV files"
        assert has_json, "Archive missing JSON files"
        assert has_txt, "Archive missing text files"

def test_backup_directory_cleaned():
    """Verify backup directory was removed after archive creation."""
    # Check for any timestamped backup directories
    backup_base = '/app/output/backup'
    if os.path.exists(backup_base):
        # Should be empty or only contain timestamped dirs (which should be removed)
        items = os.listdir(backup_base)
        # If there are timestamp dirs, they should be empty
        for item in items:
            item_path = os.path.join(backup_base, item)
            if os.path.isdir(item_path):
                assert len(os.listdir(item_path)) == 0, f"Backup directory {item} should be empty"

def test_summary_completeness():
    """Verify summary file contains all required metrics."""
    with open('/app/output/summary.txt', 'r') as f:
        content = f.read()
    
    required_info = [
        'Timestamp',
        'processing time',
        'Archive size',
        'MD5',
        'files contained'
    ]
    
    for info in required_info:
        assert info.lower() in content.lower(), f"Summary missing '{info}' information"

def test_json_transaction_structure():
    """Verify individual transaction records have correct structure."""
    with open('/app/output/reconciled_data.json', 'r') as f:
        data = json.load(f)
    
    if len(data['transactions']) > 0:
        transaction = data['transactions'][0]
        required_fields = ['id', 'type', 'status', 'amount_a', 'amount_b', 'date']
        
        for field in required_fields:
            assert field in transaction, f"Transaction missing field: {field}"
        
        # Check status values
        valid_statuses = ['VERIFIED', 'MISMATCH', 'UNIQUE_SOURCE_A', 'UNIQUE_SOURCE_B']
        assert transaction['status'] in valid_statuses, f"Invalid status: {transaction['status']}"

def test_archive_extraction():
    """Verify archive can be extracted and files are accessible."""
    with tempfile.TemporaryDirectory() as tmpdir:
        archive_path = '/app/output/archive.zip'
        
        with zipfile.ZipFile(archive_path, 'r') as zf:
            zf.extractall(tmpdir)
            
            # Check extracted files are readable
            for file_info in zf.infolist():
                extracted_path = os.path.join(tmpdir, file_info.filename)
                if not file_info.is_dir():
                    assert os.path.exists(extracted_path)
                    # Try to read first few bytes
                    with open(extracted_path, 'rb') as f:
                        f.read(10)  # Should not raise error