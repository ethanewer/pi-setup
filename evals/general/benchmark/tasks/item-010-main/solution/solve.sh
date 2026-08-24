#!/bin/bash
set -euo pipefail

cat > /app/netlist.c <<'SRC'
/* netlist.c -- compute integer square root and Fibonacci via a constructed
 * logic-gate netlist, honoring a strict topology (each gate references only
 * earlier indices). Build with:  gcc -O2 -o netlist netlist.c
 *
 * Implement the two AGENT front-ends below so the selftest and CLI are correct:
 *   ul net_isqrt(ul n)   floor(sqrt(n))
 *   ul net_fib(int k)    F(k)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef unsigned long ul;
#define MAX_GATES 200000

typedef enum { OP_INPUT, OP_CONST, OP_ADD, OP_SUB, OP_MUL, OP_AND, OP_OR,
               OP_XOR, OP_LE, OP_SEL } Op;

typedef struct { Op op; int a,b,c; ul val; } Gate;

static Gate   g[MAX_GATES];
static int    ng = 0;
static ul     val[MAX_GATES];
static ul     input_value = 0;

void net_reset(void){ ng=0; for(int i=0;i<MAX_GATES;i++) val[i]=0; }
int  wire_count(void){ return ng; }

int mk_input(void){ g[ng]=(Gate){OP_INPUT,-1,-1,-1,0}; return ng++; }
int mk_const(ul v){ g[ng]=(Gate){OP_CONST,-1,-1,-1,v}; return ng++; }

static void topo(int a,int b){
    if(a>=ng||b>=ng){ fprintf(stderr,"NET TOPOLOGY VIOLATION: operand not yet emitted\n"); exit(2); }
}
int op_add(int a,int b){ topo(a,b); g[ng]=(Gate){OP_ADD,a,b,-1,0}; return ng++; }
int op_sub(int a,int b){ topo(a,b); g[ng]=(Gate){OP_SUB,a,b,-1,0}; return ng++; }
int op_mul(int a,int b){ topo(a,b); g[ng]=(Gate){OP_MUL,a,b,-1,0}; return ng++; }
int op_and(int a,int b){ topo(a,b); g[ng]=(Gate){OP_AND,a,b,-1,0}; return ng++; }
int op_or (int a,int b){ topo(a,b); g[ng]=(Gate){OP_OR ,a,b,-1,0}; return ng++; }
int op_xor(int a,int b){ topo(a,b); g[ng]=(Gate){OP_XOR,a,b,-1,0}; return ng++; }
int op_le (int a,int b){ topo(a,b); g[ng]=(Gate){OP_LE ,a,b,-1,0}; return ng++; }
int op_sel(int cond,int a,int b){ topo(cond,cond); topo(a,b); g[ng]=(Gate){OP_SEL,cond,a,b,0}; return ng++; }
void set_input(ul v){ input_value=v; }
ul  wire_value(int w){ return val[w]; }

void net_eval(void){
    for(int i=0;i<ng;i++){
        ul x=0;
        switch(g[i].op){
          case OP_INPUT: x=input_value; break;
          case OP_CONST: x=g[i].val; break;
          case OP_ADD:   x=val[g[i].a]+val[g[i].b]; break;
          case OP_SUB:   x=val[g[i].a]-val[g[i].b]; break;
          case OP_MUL:   x=val[g[i].a]*val[g[i].b]; break;
          case OP_AND:   x=val[g[i].a]&val[g[i].b]; break;
          case OP_OR:    x=val[g[i].a]|val[g[i].b]; break;
          case OP_XOR:   x=val[g[i].a]^val[g[i].b]; break;
          case OP_LE:    x=(val[g[i].a]<=val[g[i].b])?1:0; break;
          case OP_SEL:   x= val[g[i].a]?val[g[i].b]:val[g[i].c]; break;
        }
        val[i]=x;
    }
}

/* ==================================================================== *
 *  AGENT FRONT-ENDS  (make these correct)                               *
 * ==================================================================== */
ul net_isqrt(ul n){
    /* floor sqrt via bit-serial isqrt netlist */
    net_reset();
    int in = mk_input();
    int r  = mk_const(0);
    for(int b=31;b>=0;b--){
        int one  = mk_const(1UL<<b);
        int cand = op_or(r, one);
        int sq   = op_mul(cand, cand);
        int keep = op_le(sq, in);
        r        = op_sel(keep, cand, r);
    }
    set_input(n);
    net_eval();
    return wire_value(r);
}

ul net_fib(int k){
    if(k==0) return 0;
    net_reset();
    int f0=mk_const(0), f1=mk_const(1);
    for(int i=2;i<=k;i++){ int nxt=op_add(f1,f0); f0=f1; f1=nxt; }
    net_eval();
    return wire_value(f1);
}

/* ===================================================================== *
 *  Provided harness: CLI + selftest                                     *
 * ===================================================================== */
static ul ref_isqrt(ul n){ ul r=0; while((r+1)*(r+1)<=n) r++; return r; }
static ul ref_fib(int k){ ul a=0,b=1; if(k==0)return 0; for(int i=2;i<=k;i++){ul t=a+b;a=b;b=t;} return b; }

int main(int argc, char** argv){
    if(argc==3 && strcmp(argv[1],"isqrt")==0){
        printf("%lu\n", net_isqrt(strtoul(argv[2],NULL,10)));
        return 0;
    }
    if(argc==3 && strcmp(argv[1],"fib")==0){
        printf("%lu\n", net_fib(atoi(argv[2])));
        return 0;
    }
    /* selftest */
    unsigned long sq_vals[] = {0,1,2,3,8,9,10,15,16,24,99,100,255,256,
                               1000,4096,10000,65535,123456,1000000};
    int fails=0;
    for(size_t i=0;i<sizeof(sq_vals)/sizeof(sq_vals[0]); i++){
        ul n=sq_vals[i]; ul got=net_isqrt(n); ul exp=ref_isqrt(n);
        if(got!=exp){ fails++; fprintf(stderr,"isqrt FAIL n=%lu got=%lu exp=%lu\n",n,got,exp); }
    }
    for(int k=0;k<=30;k++){
        ul got=net_fib(k); ul exp=ref_fib(k);
        if(got!=exp){ fails++; fprintf(stderr,"fib FAIL k=%d got=%lu exp=%lu\n",k,got,exp); }
    }
    if(fails==0){ printf("SELFTEST_PASS\n"); return 0; }
    printf("SELFTEST_FAIL (fails=%d)\n",fails); return 1;
}
SRC

gcc -O2 -o /app/netlist /app/netlist.c
