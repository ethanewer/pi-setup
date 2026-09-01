#!/bin/bash
set -euo pipefail
python3 - <<'EOF'
import json, math
chains=[[6,8,10,12],[8,10,12,14]]
m=len(chains); n=len(chains[0])
means=[sum(c)/len(c) for c in chains]
theta_bar=sum(means)/m
B=n/(m-1)*sum((th-theta_bar)**2 for th in means)
W=sum(sum((x-th)**2 for x in c)/(n-1) for c,th in zip(chains,means))/m
var_hat=(n-1)/n*W + B/n
rhat=math.sqrt(var_hat/W)
json.dump({"rhat":rhat}, open('/app/answer.json','w'))
print(rhat)
EOF