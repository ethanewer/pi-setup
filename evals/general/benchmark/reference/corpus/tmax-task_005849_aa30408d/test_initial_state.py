# test_initial_state.py
import os

def test_src_dir_exists():
    assert os.path.isdir("/home/user/src"), "/home/user/src directory is missing"

def test_main_cpp_exists():
    assert os.path.isfile("/home/user/src/main.cpp"), "/home/user/src/main.cpp is missing"
    with open("/home/user/src/main.cpp", "r") as f:
        content = f.read()
        assert "strcpy(buffer, input.c_str());" in content, "main.cpp does not contain the expected vulnerable code"
        assert "SECRET_TOKEN:" in content, "main.cpp does not contain the SECRET_TOKEN string"

def test_processor_elf_exists():
    assert os.path.isfile("/home/user/processor.elf"), "/home/user/processor.elf is missing"

def test_raw_log_exists():
    assert os.path.isfile("/home/user/raw.log"), "/home/user/raw.log is missing"
    with open("/home/user/raw.log", "r") as f:
        content = f.read()
        assert "123-45-6789" in content, "raw.log does not contain expected SSN data"
        assert "4111222233334444" in content, "raw.log does not contain expected CC data"
        assert "LONG: This is a very long line" in content, "raw.log does not contain the long line for testing buffer overflow"