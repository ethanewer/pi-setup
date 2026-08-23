import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from greet import greet  # noqa: E402

assert greet("Ada") == "Hello, Ada!"
assert greet("") == "Hello, !"
print("PASS: greet function ok")

out = subprocess.run([sys.executable, os.path.join(HERE, "greet.py")], capture_output=True, text=True)
assert out.returncode == 0, f"CLI failed: {out.stderr}"
assert "Hello, world!" in out.stdout, out.stdout
print("PASS: greet CLI ok")
