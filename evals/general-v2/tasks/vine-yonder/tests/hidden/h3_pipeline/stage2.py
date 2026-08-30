import os
from lane_helpers import shuffle
H=os.path.dirname(os.path.abspath(__file__)); G=os.path.join(H,"generated")
if not os.path.isdir(G): os.makedirs(G)
t=open(os.path.join(G,"stage1.txt")).read()
open(os.path.join(G,"stage2.txt"),"w").write(shuffle(t)+"\n")
print("STAGE2")
