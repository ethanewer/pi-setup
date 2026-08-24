import os
import re

def test_output_exists():
    """Verify output file was created."""
    assert os.path.exists('/app/fixed/CMakeLists.txt'), "Fixed CMakeLists.txt not found"

def test_output_correct():
    """Verify output content is correct."""
    with open('/app/fixed/CMakeLists.txt', 'r') as f:
        content = f.read()
    
    # Normalize whitespace for matching
    content_single_line = ' '.join(content.split())
    
    # Test 1: Correct project name
    assert 'project(SimpleProject)' in content, "Project name must be 'SimpleProject'"
    
    # Test 2: Both source files included
    # Check for presence of both source files (case-insensitive, allowing for different formatting)
    assert ('src/main.c' in content or 'src/main.c' in content_single_line), "Must include src/main.c"
    assert ('src/utils.c' in content or 'src/utils.c' in content_single_line), "Must include src/utils.c"
    
    # Test 3: Correct executable name
    # Look for add_executable with simple_app (allowing spaces or parentheses variations)
    add_executable_pattern = r'add_executable\s*\(\s*simple_app'
    assert re.search(add_executable_pattern, content, re.IGNORECASE), "Executable must be named 'simple_app'"
    
    # Test 4: Include directory specified
    # Check for include directory reference (allowing various CMake patterns)
    include_patterns = [
        r'target_include_directories.*include',
        r'include_directories.*include',
        r'I.*include'
    ]
    has_include = any(re.search(pattern, content, re.IGNORECASE) for pattern in include_patterns)
    assert has_include, "Must add 'include' directory to include path"
    
    # Test 5: C11 standard specified
    # Check for C11 standard setting
    c11_patterns = [
        r'set\s*\(\s*CMAKE_C_STANDARD\s+11\s*\)',
        r'target_compile_features.*c_std_11',
        r'CMAKE_C_STANDARD.*11'
    ]
    has_c11 = any(re.search(pattern, content, re.IGNORECASE) for pattern in c11_patterns)
    assert has_c11, "Must set C standard to C11"
    
    # Additional: Should not contain the incorrect project name from broken file
    assert 'WrongProject' not in content, "Should not contain incorrect project name 'WrongProject'"