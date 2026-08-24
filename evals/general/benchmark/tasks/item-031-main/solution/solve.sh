#!/bin/bash
# Oracle solution for item-031-main.
# 1) convert model.json -> /app/weights.bin (4 float32 arrays, row-major LE)
# 2) write a compact self-contained C predictor under the byte budget
# 3) compile, then validate against the reference on all 60 images.
set -euo pipefail

cd /app

# -- 1. JSON -> binary weights ----------------------------------------------
python3 - <<'EOF'
import json, struct
m = json.load(open("/app/model.json"))
with open("/app/weights.bin", "wb") as f:
    for arr in (m["w1"], m["b1"], m["w2"], m["b2"]):
        for row in arr:
            if isinstance(row, list):
                for v in row:
                    f.write(struct.pack("<f", v))
            else:
                f.write(struct.pack("<f", row))
EOF

# -- 2. compact C predictor ---------------------------------------------------
cat > /app/predict.c <<'CEOF'
#include<stdio.h>
#define H 32
float w1[25088],b1[32],w2[320],b2[10],h[32],y[10];unsigned char x[784];
int main(int n,char**a){FILE*f=fopen("/app/weights.bin","rb");
fread(w1,4,25088,f);fread(b1,4,32,f);fread(w2,4,320,f);fread(b2,4,10,f);fclose(f);
FILE*g=fopen(a[1],"rb");fread(x,1,784,g);fclose(g);
int i,j,k;
for(i=0;i<32;i++){float s=b1[i];for(k=0;k<784;k++)s+=x[k]/255.0f*w1[k*32+i];h[i]=s>0?s:0;}
for(j=0;j<10;j++){float s=b2[j];for(i=0;i<32;i++)s+=h[i]*w2[i*10+j];y[j]=s;}
int m=0;for(j=1;j<10;j++)if(y[j]>y[m])m=j;
printf("%d\n",m);return 0;}
CEOF

# -- 3. compile and validate ---------------------------------------------------
gcc -O2 -o /app/predict /app/predict.c

echo "predict.c size: $(wc -c < /app/predict.c) bytes"
bad=0
for img in /app/data/*.raw; do
  got=$(/app/predict "$img")
  exp=$(python3 /app/reference.py "$img")
  if [ "$got" != "$exp" ]; then
    echo "MISMATCH on $img: got=$got exp=$exp"
    bad=$((bad+1))
  fi
done
echo "validation: $((60-bad))/60 match"
[ "$bad" -eq 0 ] || exit 1
echo DONE