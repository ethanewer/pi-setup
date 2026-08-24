import os
import json
import tempfile
import shutil
from pathlib import Path

def test_output_exists():
    """Verify output file was created."""
    assert os.path.exists('/app/validation_report.txt'), "Output file not found at /app/validation_report.txt"

def test_output_correct():
    """Verify output content is correct."""
    # Read the config to know what to expect
    with open('/app/config.json', 'r') as f:
        config = json.load(f)
    
    # Read the output
    with open('/app/validation_report.txt', 'r') as f:
        output = f.read()
    
    # Split into sections
    sections = output.strip().split('\n\n')
    assert len(sections) == 3, f"Expected 3 sections separated by blank lines, got {len(sections)}"
    
    # Parse sections
    files_section = sections[0].strip()
    dirs_section = sections[1].strip()
    exts_section = sections[2].strip()
    
    # Check files section
    assert files_section.startswith('FILES:'), "First section should start with 'FILES:'"
    file_lines = files_section.split('\n')[1:]  # Skip header
    
    # Verify all files from config are listed
    file_paths = [line.split('] ')[1] for line in file_lines if line]
    assert set(file_paths) == set(config['files']), "Files in report don't match config files"
    
    # Check each file's status is correct
    for line in file_lines:
        if line:  # Skip empty lines
            status_part, path = line.split('] ')
            status = status_part[1:]  # Remove leading '['
            path = path.strip()
            
            expected_status = 'EXISTS' if os.path.exists(path) and os.path.isfile(path) else 'MISSING'
            assert status == expected_status, f"Wrong status for {path}: expected {expected_status}, got {status}"
    
    # Check directories section
    assert dirs_section.startswith('DIRECTORIES:'), "Second section should start with 'DIRECTORIES:'"
    dir_lines = dirs_section.split('\n')[1:]  # Skip header
    
    # Verify all directories from config are listed
    dir_paths = [line.split('] ')[1] for line in dir_lines if line]
    assert set(dir_paths) == set(config['directories']), "Directories in report don't match config directories"
    
    # Check each directory's status is correct
    for line in dir_lines:
        if line:  # Skip empty lines
            status_part, path = line.split('] ')
            status = status_part[1:]  # Remove leading '['
            path = path.strip()
            
            expected_status = 'EXISTS' if os.path.exists(path) and os.path.isdir(path) else 'MISSING'
            assert status == expected_status, f"Wrong status for {path}: expected {expected_status}, got {status}"
    
    # Check extensions section
    assert exts_section.startswith('EXTENSIONS:'), "Third section should start with 'EXTENSIONS:'"
    ext_lines = exts_section.split('\n')[1:]  # Skip header
    
    # Count actual files with each extension in /app
    ext_counts = {}
    for ext in config['extensions']:
        count = 0
        for item in os.listdir('/app'):
            item_path = os.path.join('/app', item)
            if os.path.isfile(item_path):
                # Case-insensitive comparison
                file_ext = os.path.splitext(item)[1].lower()
                if file_ext == ext.lower():
                    count += 1
        ext_counts[ext] = count
    
    # Verify all extensions from config are listed with correct counts
    for line in ext_lines:
        if line:  # Skip empty lines
            count_part, ext = line.split('] ')
            count = int(count_part[1:])  # Remove leading '['
            ext = ext.strip()
            
            assert ext in config['extensions'], f"Extension {ext} not in config"
            assert count == ext_counts[ext], f"Wrong count for {ext}: expected {ext_counts[ext]}, got {count}"
    
    # Verify all extensions are accounted for
    reported_exts = [line.split('] ')[1].strip() for line in ext_lines if line]
    assert set(reported_exts) == set(config['extensions']), "Not all extensions reported"

def test_format_compliance():
    """Verify the exact output format is followed."""
    with open('/app/validation_report.txt', 'r') as f:
        output = f.read()
    
    # Check section headers
    assert 'FILES:\n' in output, "Missing 'FILES:' section header"
    assert '\n\nDIRECTORIES:\n' in output, "Missing 'DIRECTORIES:' section header or incorrect spacing"
    assert '\n\nEXTENSIONS:\n' in output, "Missing 'EXTENSIONS:' section header or incorrect spacing"
    
    # Check line formatting
    lines = output.strip().split('\n')
    for line in lines:
        if line and not line.endswith(':'):  # Skip empty lines and section headers
            assert line.startswith('['), f"Line doesn't start with '[': {line}"
            assert '] ' in line, f"Line missing '] ': {line}"
            
            # Extract parts
            parts = line.split('] ', 1)
            assert len(parts) == 2, f"Line doesn't have exactly one '] ': {line}"
            
            status_part = parts[0]
            path_part = parts[1]
            
            # Status part should be [SOMETHING]
            assert status_part.startswith('['), f"Status part doesn't start with '[': {status_part}"
            status = status_part[1:]  # Remove '['
            
            # Check if it's a count (number) or status (EXISTS/MISSING)
            if line.startswith('FILES:') or line.startswith('DIRECTORIES:'):
                assert status in ['EXISTS', 'MISSING'], f"Invalid status: {status}"
            elif line.startswith('EXTENSIONS:'):
                assert status.isdigit(), f"Count should be a number: {status}"