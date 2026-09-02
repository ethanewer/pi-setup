import os, sys
from pipeline_helpers import header
HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "generated")
if not os.path.isdir(GEN):
    os.makedirs(GEN)
line = header("grove")
with open(os.path.join(GEN, "stage1.txt"), "w") as f:
    f.write(line + "\n")
print("STAGE1")
