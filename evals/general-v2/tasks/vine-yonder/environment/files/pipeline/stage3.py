import os, sys
from pipeline_helpers import finalize
HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "generated")
if not os.path.isdir(GEN):
    os.makedirs(GEN)
a = open(os.path.join(GEN, "stage1.txt")).read().strip()
b = open(os.path.join(GEN, "stage2.txt")).read().strip()
out = finalize(a, b)
with open(os.path.join(GEN, "stage3.txt"), "w") as f:
    f.write(out + "\n")
print("STAGE3")
