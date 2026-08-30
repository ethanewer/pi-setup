import os, sys
from pipeline_helpers import transform
HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "generated")
if not os.path.isdir(GEN):
    os.makedirs(GEN)
t = open(os.path.join(GEN, "stage1.txt")).read().strip()
out = transform(t)
with open(os.path.join(GEN, "stage2.txt"), "w") as f:
    f.write(out + "\n")
print("STAGE2")
