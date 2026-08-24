#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static unsigned char KEY[16];
static unsigned char FLAG[30];
static volatile unsigned char SALT1 = 0x5A;
static volatile unsigned char SALT2 = 0xA5;
static int hexval(char c){
    if(c>='0'&&c<='9') return c-'0';
    if(c>='a'&&c<='f') return c-'a'+10;
    if(c>='A'&&c<='K') return c-'A'+10;
    return -1;
}
static void init(void){
    unsigned char k[16] = {0x75, 0xc0, 0x61, 0x2e, 0x9a, 0x04, 0xd7, 0x48, 0xac, 0xfe, 0x21, 0x66, 0xc4, 0x27, 0x55, 0x7b};
    unsigned char f[30] = {0xc6, 0xd5, 0xc4, 0x88, 0xca, 0xd7, 0xc4, 0xc6, 0xc9, 0xc0, 0x88, 0xc6, 0xcd, 0xca, 0xd6, 0xc0, 0xcb, 0x88, 0xd5, 0xc9, 0xc4, 0xcc, 0xcb, 0xd1, 0xc0, 0xdd, 0xd1, 0x88, 0xca, 0xce};
    for(int i=0;i<16;i++) KEY[i] = (unsigned char)(k[i] ^ SALT1);
    for(int i=0;i<30;i++) FLAG[i] = (unsigned char)(f[i] ^ SALT2);
}
static void tohex(const unsigned char *b, int n, char *out){
    static const char hx[]="0123456789abcdef";
    for(int i=0;i<n;i++){ out[i*2]=hx[b[i]>>4]; out[i*2+1]=hx[b[i]&15]; }
    out[n*2]=0;
}
int main(int argc, char **argv){
    if(argc<2){ fprintf(stderr,"usage: oracle enc <hex-plaintext> | oracle flag\n"); return 1; }
    init();
    if(strcmp(argv[1],"flag")==0){
        unsigned char ct[30];
        for(int i=0;i<30;i++) ct[i]=FLAG[i]^KEY[i%16];
        char out[70]; tohex(ct,30,out); printf("%s\n", out); return 0;
    }
    if(strcmp(argv[1],"enc")==0 && argc>=3){
        char *hex=argv[2];
        int n=(int)strlen(hex)/2;
        unsigned char pt[512];
        for(int i=0;i<n;i++) pt[i]=(unsigned char)((hexval(hex[i*2])<<4)|hexval(hex[i*2+1]));
        for(int i=0;i<n;i++) pt[i]^=KEY[i%16];
        char out[1030]; tohex(pt,n,out); printf("%s\n", out); return 0;
    }
    fprintf(stderr,"bad arguments\n"); return 1;
}
