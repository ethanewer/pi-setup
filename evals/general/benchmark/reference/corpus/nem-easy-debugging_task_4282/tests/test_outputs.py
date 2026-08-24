import os
import json

def test_output_exists():
    """Verify output file was created."""
    assert os.path.exists('/app/output.txt'), "Output file /app/output.txt does not exist."

def test_output_correct():
    """Verify output content is correct."""
    with open('/app/output.txt', 'r') as f:
        content = f.read().strip()
    expected = "Total: 60, Average: 20.0"
    assert content == expected, f"Output content incorrect. Expected: '{expected}', Got: '{content}'"