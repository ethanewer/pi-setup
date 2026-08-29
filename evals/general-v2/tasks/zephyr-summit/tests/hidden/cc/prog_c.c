#include <stdio.h>
int data[6];
int fill(int v){ int r = v*v; return r; }
int main(void){
  int s = 0; int i;
  for (i = 0; i < 6; i = i + 1){
    data[i] = fill(i);
    s = s + data[i];
  }
  printf("%d\n", s); return 0;
}