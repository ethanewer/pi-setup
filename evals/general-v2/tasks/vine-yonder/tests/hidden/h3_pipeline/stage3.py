import os
from lane_helpers import seal
H=os.path.dirname(os.path.abspath(__file__)); G=os.path.join(H,"generated")
if not os.path.isdir(G): os.makedirs(G)
a=open(os.path.join(G,"stage1.txt")).read().strip()
b=open(os.path.join(G,"stage2.txt")).read().strip()
open(os.path.join(G,"stage3.txt"),"w").write(seal(a,b)+"\n")
print("STAGE3")
