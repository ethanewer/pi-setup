import os
from lane_helpers import label
H=os.path.dirname(os.path.abspath(__file__)); G=os.path.join(H,"generated")
if not os.path.isdir(G): os.makedirs(G)
open(os.path.join(G,"stage1.txt"),"w").write(label("depot")+"\n")
print("STAGE1")
