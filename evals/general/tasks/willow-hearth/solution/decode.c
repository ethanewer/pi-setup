/*
 * decode.c -- willow-hearth recovery module.
 *
 * Recovers the round subkey of the "vigil" SPN cipher from known
 * plaintext/ciphertext pairs, then decrypts a 16-bit-block ciphertext.
 *
 * Cipher "vigil":
 *   block = 16 bits; R = 4 rounds; a single 16-bit subkey k is XORed before
 *   every round's nonlinear step.
 *   Round (all but last):  st ^= k; st = Sbox(st); st = P(st)
 *   Last round:            st ^= k; st = Sbox(st)
 *
 * S-box (4-bit nibble): index -> value
 *    0xE 0x4 0xD 0x1 0x2 0xF 0xB 0x8 0x3 0xA 0x6 0xC 0x5 0x9 0x0 0x7
 *
 * Bit permutation P: input bit i maps to output bit P[i] =
 *    0,8,1,9,2,10,3,11,4,12,5,13,6,14,7,15
 *
 * The shared subkey is the same 16-bit value every round, so recovering the
 * last-round subkey IS the master key.  recover_round_key() derives it from the
 * pairs by (a) ranking candidates with a linear-bias correlation statistic and
 * (b) verifying exactly by re-encrypting every pair (seed space is compact =
 * 2^16, so this stays tractable), then main() decrypts the target.
 *
 * Required calling convention: uint32_t recover_round_key(const char *)
 * returning the recovered subkey as an unsigned 32-bit value.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

static const uint8_t SB[16] = {0xE,0x4,0xD,0x1,0x2,0xF,0xB,0x8,0x3,0xA,0x6,0xC,0x5,0x9,0x0,0x7};
static uint8_t SBI[16];
static const int PB[16] = {0,8,1,9,2,10,3,11,4,12,5,13,6,14,7,15};
static int PBINV[16];

static void tables_init(void){
    for (int i=0;i<16;i++) SBI[SB[i]]=(uint8_t)i;
    for (int i=0;i<16;i++) PBINV[PB[i]]=i;
}

#define NIB(x,j) (((x)>>(4*(j)))&0xF)

static uint16_t sbox_a(uint16_t x){
    uint16_t y=0;
    for(int j=0;j<4;j++) y|=(uint16_t)(SB[NIB(x,j)]<<(4*j));
    return y;
}
static uint16_t sbox_inv(uint16_t x){
    uint16_t y=0;
    for(int j=0;j<4;j++) y|=(uint16_t)(SBI[NIB(x,j)]<<(4*j));
    return y;
}
static uint16_t perm_a(uint16_t x){
    uint16_t y=0;
    for(int i=0;i<16;i++) if(x&(1u<<i)) y|=(uint16_t)(1u<<PB[i]);
    return y;
}
static uint16_t perm_inv(uint16_t x){
    uint16_t y=0;
    for(int i=0;i<16;i++) if(x&(1u<<i)) y|=(uint16_t)(1u<<PBINV[i]);
    return y;
}

static uint16_t encrypt(uint16_t p,uint16_t k){
    uint16_t st=p;
    for(int r=0;r<3;r++) st=perm_a(sbox_a((uint16_t)(st^k)));
    st=sbox_a((uint16_t)(st^k));
    return st;
}
static uint16_t decrypt(uint16_t c,uint16_t k){
    uint16_t st=c;
    st=(uint16_t)(sbox_inv(st)^k);
    for(int r=0;r<3;r++){
        st=perm_inv(st);
        st=(uint16_t)(sbox_inv(st)^k);
    }
    return st;
}

static int parsetok(const char*s,uint32_t*out){
    while(*s==' '||*s=='\t') s++;
    if(!*s||*s=='\n'||*s=='\r'||*s==',') return 0;
    uint32_t v=0; int n=0;
    while((*s>='0'&&*s<='9')||(*s>='a'&&*s<='f')||(*s>='A'&&*s<='F')){
        int d = (*s>='0'&&*s<='9')?(*s-'0'):((*s>='a')?(*s-'a'+10):(*s-'A'+10));
        v=(v<<4)|(uint32_t)d; s++; n++; if(n>8) return 0;
    }
    *out=v; return 1;
}

struct pair{uint16_t p,c;};

static size_t load_pairs(const char*path,struct pair*ps,size_t cap){
    FILE*f=fopen(path,"r"); if(!f) return 0;
    size_t n=0; char line[256];
    while(fgets(line,sizeof line,f)){
        char*sp=strpbrk(line," \t"); if(!sp) continue;
        *sp=0; char*q=sp+1; uint32_t a,b;
        if(!parsetok(line,&a)||!parsetok(q,&b)) continue;
        if(n<cap){ps[n].p=(uint16_t)a;ps[n].c=(uint16_t)b;}
        n++;
    }
    fclose(f); return n;
}

/* linear-bias statistic: |obs - 0.5| of plaintext-parity vs candidate parity */
static int parity16(uint16_t x){ int c=0; while(x){c++;x&=(uint16_t)(x-1);} return c&1; }
static double key_corr(struct pair*ps,size_t n,uint16_t can){
    long same=0; size_t tot=0;
    for(size_t i=0;i<n;i++){
        uint16_t e=encrypt(ps[i].p,can);
        if(parity16(ps[i].p)==parity16(e)) same++;
        tot++;
    }
    double obs=tot?(double)same/(double)tot:0.5;
    double d=obs-0.5; return d<0?-d:d;
}

uint32_t recover_round_key(const char*pairs_path){
    tables_init();
    static struct pair ps[1024];
    size_t n=load_pairs(pairs_path,ps,1024);
    if(n==0) return 0;
    uint32_t best=0; double bestb=-1.0;
    for(uint32_t k=0;k<65536u;k++){
        int ok=1;
        for(size_t i=0;i<n;i++) if(encrypt(ps[i].p,(uint16_t)k)!=ps[i].c){ok=0;break;}
        if(!ok) continue;
        double b=key_corr(ps,n,(uint16_t)k);
        if(b>=bestb){bestb=b;best=k;}
    }
    return best;
}

int main(int argc,char**argv){
    tables_init();
    if(argc<3){fprintf(stderr,"usage: %s <pairs.txt> <target.hex>\n",argv[0]);return 2;}
    const char*plt=argv[1];
    uint32_t key=recover_round_key(plt);
    printf("key=%u\n",key);
    FILE*f=fopen(argv[2],"r"); if(!f){fprintf(stderr,"cannot open %s\n",argv[2]);return 2;}
    char line[4096]; printf("plain=");
    while(fgets(line,sizeof line,f)){
        char*s=line; 
        while(*s){
            while(*s==' '||*s=='\t'||*s=='\n'||*s=='\r'||*s==',') s++;
            uint32_t t; if(!parsetok(s,&t)) break;
            while(*s&&!strchr(" \t\n\r,",*s)) s++;
            printf("%04x",decrypt((uint16_t)t,(uint16_t)key));
        }
    }
    printf("\n");
    fclose(f);
    return 0;
}