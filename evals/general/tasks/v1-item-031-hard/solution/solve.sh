#!/bin/bash
# Oracle solution for item-031-hard.
# 1) reverse the quantized binary layout (Q8V1 magic, f32 scale, 4 u32 lens,
#    int8 payload in PyTorch (out,in) row-major order)
# 2) write a compact self-contained C predictor under the 1536-byte budget
# 3) compile and validate against the reference on all 60 images.
set -euo pipefail

cd /app

cat > /app/predict.c <<'CEOF'
#include<stdio.h>
#define H 32
float h[32],y[10];signed char w1[25088],b1[32],w2[320],b2[10];unsigned char x[784];
unsigned int L[4];float sc;char mg[4];
int main(int n,char**a){FILE*f=fopen("/app/weights_q8.bin","rb");
fread(mg,1,4,f);fread(&sc,4,1,f);fread(L,4,4,f);
fread(w1,1,L[0],f);fread(b1,1,L[1],f);fread(w2,1,L[2],f);fread(b2,1,L[3],f);fclose(f);
FILE*g=fopen(a[1],"rb");fread(x,1,784,g);fclose(g);
int i,j,k;
for(i=0;i<32;i++){float s=(float)b1[i]*sc;for(k=0;k<784;k++)s+=x[k]/255.0f*(float)w1[i*784+k]*sc;h[i]=s>0?s:0;}
for(j=0;j<10;j++){float s=(float)b2[j]*sc;for(i=0;i<32;i++)s+=h[i]*(float)w2[j*32+i]*sc;y[j]=s;}
int m=0;for(j=1;j<10;j++)if(y[j]>y[m])m=j;
printf("%d\n",m);return 0;}
CEOF

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