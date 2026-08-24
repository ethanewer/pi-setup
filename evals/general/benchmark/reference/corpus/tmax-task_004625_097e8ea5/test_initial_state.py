# test_initial_state.py

import os
import shutil
import pytest

def test_video_fixture_exists():
    """Test that the video artifact exists at the expected location."""
    video_path = "/app/tutorial.mp4"
    assert os.path.isfile(video_path), f"Video fixture is missing at {video_path}"

def test_ffmpeg_installed():
    """Test that ffmpeg is installed and available in the system PATH."""
    assert shutil.which("ffmpeg") is not None, "ffmpeg is not installed or not in PATH"

def test_tesseract_installed():
    """Test that tesseract is installed and available in the system PATH."""
    assert shutil.which("tesseract") is not None, "tesseract is not installed or not in PATH"