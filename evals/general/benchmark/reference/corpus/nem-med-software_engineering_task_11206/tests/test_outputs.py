import os
import json
import pytest
import platform
import sys
import subprocess

def test_output_files_exist():
    """Verify both output files were created."""
    assert os.path.exists('/app/output/build_commands.json'), "build_commands.json missing"
    assert os.path.exists('/app/output/feature_summary.txt'), "feature_summary.txt missing"

def test_build_commands_structure():
    """Verify JSON structure is correct."""
    with open('/app/output/build_commands.json', 'r') as f:
        data = json.load(f)
    
    required_keys = [
        'platform', 'compiler', 'cpp_standard', 'active_features',
        'source_files', 'include_dirs', 'defines', 'lib_dirs',
        'linker_flags', 'compilation_commands'
    ]
    
    for key in required_keys:
        assert key in data, f"Missing key: {key}"
    
    assert isinstance(data['active_features'], list)
    assert isinstance(data['compilation_commands'], list)
    
    # Check platform detection
    current_platform = platform.system().lower()
    if current_platform == 'darwin':
        current_platform = 'macos'
    assert data['platform'] == current_platform, f"Platform mismatch: {data['platform']} != {current_platform}"

def test_feature_resolution():
    """Verify feature dependencies and conflicts are resolved correctly."""
    with open('/app/output/build_commands.json', 'r') as f:
        data = json.load(f)
    
    active_features = set(data['active_features'])
    
    # core should always be active (default and dependency)
    assert 'core' in active_features, "Core feature missing"
    
    # advanced and legacy should not co-exist
    if 'advanced' in active_features:
        assert 'legacy' not in active_features, "Conflicting features both active"
    
    # Check dependencies are satisfied
    feature_deps = {
        'logging': {'core'},
        'advanced': {'core'},
        'gpu': {'core'}
    }
    
    for feature, deps in feature_deps.items():
        if feature in active_features:
            for dep in deps:
                assert dep in active_features, f"Missing dependency: {feature} requires {dep}"

def test_compilation_commands_valid():
    """Verify compilation commands are properly formatted."""
    with open('/app/output/build_commands.json', 'r') as f:
        data = json.load(f)
    
    for cmd in data['compilation_commands']:
        assert 'file' in cmd
        assert 'command' in cmd
        assert os.path.basename(cmd['file']) in cmd['command']
        
        # Check for appropriate flags
        if data['platform'] == 'linux':
            assert 'g++' in cmd['command']
        elif data['platform'] == 'macos':
            assert 'clang++' in cmd['command']
        
        assert f"-std={data['cpp_standard']}" in cmd['command']
        
        # Check defines are included
        for define in data['defines']:
            assert f"-D{define}" in cmd['command']

def test_feature_summary_content():
    """Verify feature summary contains required information."""
    with open('/app/output/feature_summary.txt', 'r') as f:
        content = f.read()
    
    required_sections = [
        "Build Configuration Summary",
        "Active Features",
        "Excluded Features",
        "Dependency Resolution"
    ]
    
    for section in required_sections:
        assert section in content, f"Missing section: {section}"
    
    # Check platform is mentioned
    current_platform = platform.system().lower()
    if current_platform == 'darwin':
        current_platform = 'macos'
    assert current_platform in content.lower()

def test_error_handling_scenario():
    """Test that the script handles invalid input gracefully."""
    # Run the script with conflicting features
    test_args = [
        sys.executable, '/app/build_manager.py',
        '--enable', 'advanced,legacy',
        '--disable', 'logging'
    ]
    
    result = subprocess.run(
        test_args,
        capture_output=True,
        text=True
    )
    
    # Should either exit with error or handle conflict in output
    # (implementation specific - we accept either approach)
    if result.returncode == 0:
        # If it succeeds, check conflict is handled in output
        with open('/app/output/build_commands.json', 'r') as f:
            data = json.load(f)
        active = set(data['active_features'])
        assert not ('advanced' in active and 'legacy' in active), "Conflicting features both active"
    else:
        # If it fails, error message should be informative
        assert "conflict" in result.stderr.lower() or "error" in result.stderr.lower()

def test_platform_specific_features():
    """Verify platform-specific features are handled correctly."""
    with open('/app/output/build_commands.json', 'r') as f:
        data = json.load(f)
    
    # Check GPU feature if present
    if 'gpu' in data['active_features']:
        # Should have platform-specific libraries
        assert len(data['linker_flags']) > 0
        
        # Check for appropriate library based on platform
        if data['platform'] == 'linux':
            assert any('OpenCL' in flag for flag in data['linker_flags'])
        elif data['platform'] == 'macos':
            assert any('framework' in flag.lower() for flag in data['linker_flags'])