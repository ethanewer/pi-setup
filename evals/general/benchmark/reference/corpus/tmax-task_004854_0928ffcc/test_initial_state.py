# test_initial_state.py

import os
import shutil

def test_initial_state():
    """
    Validates the initial state of the OS/filesystem before the student performs the action.
    """
    # Check if the image file containing the rules exists
    image_path = "/app/pipeline_rules.png"
    assert os.path.isfile(image_path), f"The image file {image_path} is missing."

    # Check if the oracle binary exists and is executable
    ref_parser_path = "/app/ref_parser"
    assert os.path.isfile(ref_parser_path), f"The reference parser binary {ref_parser_path} is missing."
    assert os.access(ref_parser_path, os.X_OK), f"The reference parser binary {ref_parser_path} is not executable."

    # Check if tesseract is installed
    assert shutil.which("tesseract") is not None, "tesseract-ocr is not installed or not found in PATH."