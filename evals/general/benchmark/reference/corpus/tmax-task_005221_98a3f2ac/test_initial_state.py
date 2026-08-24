# test_initial_state.py

import os
import pytest

def test_video_feed_exists():
    """Test that the video feed file exists at the correct location."""
    video_path = "/app/feed.mp4"
    assert os.path.exists(video_path), f"Video feed file is missing: {video_path}"
    assert os.path.isfile(video_path), f"Video feed path is not a file: {video_path}"
    assert os.path.getsize(video_path) > 0, f"Video feed file is empty: {video_path}"

def test_home_directory_exists():
    """Test that the user's home directory exists."""
    home_path = "/home/user"
    assert os.path.exists(home_path), f"Home directory is missing: {home_path}"
    assert os.path.isdir(home_path), f"Home path is not a directory: {home_path}"