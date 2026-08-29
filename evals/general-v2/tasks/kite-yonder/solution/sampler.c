/* SkyMark "sozos" miniature generation model -- plain C sampler.
 *
 * Fully-integer deterministic forward pass (see instruction.md):
 *   history = last `window` of tokens; last = newest token
 *   q[d]     = sum_e emb[last][e] * keymat[e][d]
 *   for each ctx token p: kp[d] = sum_e emb[p][e]*keymat[e][d]
 *                        score = sum_d q[d]*kp[d];  w_p = max(score,0)
 *   ctx[d]   = sum_p w_p * emb[p][d]
 *   a[h]     = max(0, sum_d ffw[h][d]*ctx[d] + ffb[h])
 *   logit[t] = sum_h out[t][h]*a[h] + ob[t]
 *   next     = argmax_t logit[t], ties -> smallest t. Append; repeat.
 *
 * usage: sampler <weights.json> <length> <prompt tokens...>
 * length >= 0. prompt needs >= 1 tokens in [0,V). Prints generated ids.
 * Exit codes: 0 ok, 2 usage, 1 weights/validation error.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAXD 64
#define MAXH 128
#define MAXW 40
#define MAXV 64

typedef struct { const char *s; long i, n; } J;

static void jerr(J *j, const char *msg){
    fprintf(stderr, "error: weights syntax at offset %ld: %s\n", (long)j->i, msg);
    exit(1);
}
static void ws(J *j){ while(j->i < j->n && (j->s[j->i]==' '||j->s[j->i]=='\t'||j->s[j->i]=='\n'||j->s[j->i]=='\r')) j->i++; }
static char jpeek(J *j){ ws(j); return (j->i < j->n) ? j->s[j->i] : 0; }
static void jexp(J *j, char c){ if(jpeek(j)!=c) jerr(j,"unexpected token"); j->i++; }
static long jint(J *j){ ws(j); char *e=NULL; long v=strtol(j->s+j->i, &e, 10);
    if(e==j->s+j->i) jerr(j, "expected integer"); j->i=e-j->s; return v; }
static void jkey(J *j, char buf[], int cap){
    jexp(j,'"'); int k=0;
    while(j->i<j->n && j->s[j->i]!='"'){ if(k<cap-1) buf[k++]=j->s[j->i]; j->i++; }
    if(j->i>=j->n) jerr(j,"unterminated string");
    j->i++; buf[k]=0;
}
static void jcomma(J *j){ if(jpeek(j)==',') j->i++; }
static long *jintarr(J *j, long *cnt){
    jexp(j,'[');
    long cap=8,n=0,*a=malloc((size_t)cap*sizeof(long));
    if(jpeek(j)==']'){ ws(j); j->i++; *cnt=n; return a; }
    for(;;){ if(n>=cap){cap*=2;a=realloc(a,(size_t)cap*sizeof(long));}
        a[n++]=jint(j); jcomma(j); if(jpeek(j)==']') break; }
    j->i++; *cnt=n; return a;
}
typedef struct { long rows, cols, *data; } Mat;
static Mat jmat(J *j){
    jexp(j,'['); Mat m={0,0,NULL};
    long cap=4096,n=0,*all=malloc((size_t)cap*sizeof(long)); long cols=-1;
    if(jpeek(j)==']'){ ws(j); j->i++; m.data=all; return m; }
    for(;;){
        long rc; long *row=jintarr(j,&rc);
        if(cols<0) cols=rc; else if(rc!=cols){ fprintf(stderr,"error: ragged matrix\n"); exit(1); }
        while(n+rc>cap){ cap*=2; all=realloc(all,(size_t)cap*sizeof(long)); }
        memcpy(all+n,row,(size_t)rc*sizeof(long)); n+=rc; free(row); m.rows++;
        jcomma(j); if(jpeek(j)==']') break;
    }
    j->i++; m.cols=cols; m.data=all; return m;
}
static void jstarr(J *j, long *cnt){ /* count quoted strings; store none */
    jexp(j,'['); long n=0;
    if(jpeek(j)==']'){ ws(j); j->i++; *cnt=n; return; }
    for(;;){ char b[64]; jkey(j,b,64); n++; jcomma(j); if(jpeek(j)==']') break; }
    j->i++; *cnt=n;
}

int main(int argc, char**argv){
    if(argc<4){ fprintf(stderr,"usage: sampler <weights.json> <length> <prompt tokens...>\n"); return 2; }
    long length=strtol(argv[2],NULL,10);
    if(length<0){ fprintf(stderr,"error: length must be >= 0\n"); return 1; }
    FILE *f=fopen(argv[1],"rb");
    if(!f){ fprintf(stderr,"error: cannot open %s\n",argv[1]); return 1; }
    fseek(f,0,SEEK_END); long sz=ftell(f); fseek(f,0,SEEK_SET);
    char *txt=malloc((size_t)sz+1); if(!txt) return 1;
    if(fread(txt,1,(size_t)sz,f)!=(size_t)sz){ fclose(f); return 1; }
    txt[sz]=0; fclose(f);
    J j={txt,0,sz};

    long V=0,D=0,H=0,W=0;
    long *emb=NULL,*keymat=NULL,*ffw=NULL,*ffb=NULL,*outv=NULL,*ob=NULL;
    jexp(&j,'{');
    char key[64];
    for(;;){
        jkey(&j,key,64); jexp(&j,':');
        if(!strcmp(key,"vocab")){ jstarr(&j,&V); }
        else if(!strcmp(key,"dim")) D=jint(&j);
        else if(!strcmp(key,"hidden")) H=jint(&j);
        else if(!strcmp(key,"window")) W=jint(&j);
        else if(!strcmp(key,"emb")){ Mat m=jmat(&j); emb=m.data; }
        else if(!strcmp(key,"keymat")){ Mat m=jmat(&j); keymat=m.data; }
        else if(!strcmp(key,"ffw")){ Mat m=jmat(&j); ffw=m.data; }
        else if(!strcmp(key,"ffb")){ long c; ffb=jintarr(&j,&c); }
        else if(!strcmp(key,"out")){ Mat m=jmat(&j); outv=m.data; }
        else if(!strcmp(key,"ob")){ long c; ob=jintarr(&j,&c); }
        else jerr(&j,"unknown key");
        jcomma(&j);
        if(jpeek(&j)=='}') break;
    }
    j.i++;
    if(V<1||V>MAXV||D<1||D>MAXD||H<1||H>MAXH||W<1){ fprintf(stderr,"error: invalid dimension\n"); return 1; }
    if(!emb||!keymat||!ffw||!ffb||!outv||!ob){ fprintf(stderr,"error: incomplete weights\n"); return 1; }

    int np=argc-3;
    long *pt=malloc((size_t)np*sizeof(long));
    for(int i=0;i<np;i++){ long t=strtol(argv[3+i],NULL,10); if(t<0||t>=V){ fprintf(stderr,"error: prompt token %ld out of range\n",t); return 1; } pt[i]=t; }

    long *hist=malloc(((size_t)np+(size_t)length+1)*sizeof(long));
    long histlen=0;
    for(int i=0;i<np;i++) hist[histlen++]=pt[i];
    long long q[MAXD], w[MAXW], ctx[MAXD], act[MAXH];
    for(long step=0; step<length; step++){
        long start=histlen-(long)W; if(start<0) start=0;
        int cnt=(int)(histlen-start);
        long last=hist[histlen-1];
        for(int dd=0;dd<D;dd++){ long long s=0; for(int e=0;e<D;e++) s+=(long long)emb[last*D+e]*keymat[e*D+dd]; q[dd]=s; }
        for(int pi=0;pi<cnt;pi++){ long p=hist[start+pi]; long long S=0;
            for(int dd=0;dd<D;dd++){ long long kp=0; for(int e=0;e<D;e++) kp+=(long long)emb[p*D+e]*keymat[e*D+dd]; S+=(long long)q[dd]*kp; }
            w[pi]=S>0?S:0; }
        for(int dd=0;dd<D;dd++){ long long S=0; for(int pi=0;pi<cnt;pi++) S+=(long long)w[pi]*emb[(long)hist[start+pi]*D+dd]; ctx[dd]=S; }
        for(int h=0;h<H;h++){ long long S=ffb[h]; for(int dd=0;dd<D;dd++) S+=(long long)ffw[h*D+dd]*ctx[dd]; act[h]=S>0?S:0; }
        long best=0; long long bestl=-1;
        for(int t=0;t<V;t++){ long long lt=ob[t]; for(int hh=0;hh<H;hh++) lt+=(long long)outv[t*H+hh]*act[hh];
            if(t==0||lt>bestl){ bestl=lt; best=t; } }
        printf("%ld\n",best);
        hist[histlen++]=best;
    }
    return 0;
}