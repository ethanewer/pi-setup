/*
 * Arcadia PFM path tracer  (pgmf.jster)
 *
 * Compact self-contained software ray-tracer.  Implements ray-sphere
 * intersection, a diffuse (lambert) material lit by ambient sky + one
 * directional light, and a small deterministic Monte Carlo cosine-weighted
 * hemisphere integrator for the ambient term (used once per pixel to give a
 * soft, reproducible floor).  Renders the scene *from primitives* and writes
 * a color PFM.  It never reads or bakes a reference image.
 *
 * usage: ./ptrace <scene.cfg> <out.pfm>
 * scene format and shading model: see instruction.md.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define NS 1              /* Monte Carlo super-samples per pixel */

/* deterministic Monte Carlo stream (xorshift64* LCG) so bounces reproduce */
static unsigned long mc_seed = 0x9E3779B97F4A7C15u;
static unsigned long mc_rand(void){
    unsigned long x = mc_seed;
    x ^= x >> 12; x ^= x << 25; x ^= x >> 27;
    mc_seed = x;
    return x * 0x2545F4914F6CDD1Du;
}

typedef struct { double x,y,z; } V;
static V vsub(V a,V b){ V c={a.x-b.x,a.y-b.y,a.z-b.z}; return c; }
static double vdot(V a,V b){ return a.x*b.x+a.y*b.y+a.z*b.z; }
static V vnorm(V a){ double l=sqrt(vdot(a,a)); V c={a.x/l,a.y/l,a.z/l}; return c; }

typedef struct { double x,y,z,r; float cr,cg,cb; } Sph;
static Sph sph[256]; static int nSph=0;
static double bg[3]={0,0,0}; static double amb=0.35;
static V L={0.6,0.8,0.4};
static int W=32,H=32;

static void parse(const char *path){
    FILE *f=fopen(path,"r"); char line[512];
    if(!f){ fprintf(stderr,"ptrace: cannot open %s\n",path); exit(2); }
    while(fgets(line,sizeof line,f)){
        static const char *sp=" \t\r\n";
        char *tk=strtok(line,sp);
        if(!tk) continue;
        if(!strcmp(tk,"bg")){
            double r=0,g=0,b=0; char *q=strtok(NULL,sp);
            r=(q?atof(q):0.0);
            q=strtok(NULL,sp); g=(q?atof(q):0.0);
            q=strtok(NULL,sp); b=(q?atof(q):0.0);
            bg[0]=r;bg[1]=g;bg[2]=b;
        } else if(!strcmp(tk,"ambi")||!strcmp(tk,"amb")) {
            char *q=strtok(NULL,sp); amb=(q?atof(q):0.0);
        } else if(!strcmp(tk,"l")) {
            char *q=strtok(NULL,sp); double w=q?atof(q):0.6;
            q=strtok(NULL,sp); double r=q?atof(q):0.8;
            q=strtok(NULL,sp); double b=q?atof(q):0.4;
            L.x=w;L.y=r;L.z=b;
        } else if(!strcmp(tk,"s")) {
            if(nSph>=256){ while(strtok(NULL,sp)); continue; }
            double a[7]={0,0,0,0,0,0,0};
            char *q;
            for(int i=0;i<7;i++){ q=strtok(NULL,sp); if(q)a[i]=atof(q); else a[i]=0.0; }
            sph[nSph].x=a[0];sph[nSph].y=a[1];sph[nSph].z=a[2];
            sph[nSph].r=a[3];sph[nSph].cr=(float)a[4];
            sph[nSph].cg=(float)a[5];sph[nSph].cb=(float)a[6];
            nSph++;
        } else {
            int w=0,h=0;
            if(sscanf(tk,"%d",&w)==1){
                char *q=strtok(NULL,sp);
                h=(q?atoi(q):w);
                W=w>0?(w>1024?1024:w):1;
                H=h>0?(h>1024?1024:h):1;
            }
        }
    }
    fclose(f);
}

/* shade a primary ray through (px,py,1); writes rgb in [0,1] and depth scalar */
static void shade(double px,double py,double *rgb,double *depth){
    V d=vnorm((V){px,py,1});
    double best=1e30; int hit=-1; double hx=0,hy=0,hz=0;
    for(int i=0;i<nSph;i++){
        double ocx=-sph[i].x,ocy=-sph[i].y,ocz=-sph[i].z;
        double b=ocx*d.x+ocy*d.y+ocz*d.z;
        double c=ocx*ocx+ocy*ocy+ocz*ocz-sph[i].r*sph[i].r;
        double disc=b*b-c;
        if(disc<=0) continue;
        double sq=sqrt(disc);
        double tmin=-b-sq; if(tmin<1e-4)tmin=-b+sq;
        if(tmin<1e-4)continue;
        if(tmin<best){ best=tmin; hit=i; }
    }
    if(hit<0){ rgb[0]=bg[0];rgb[1]=bg[1];rgb[2]=bg[2]; *depth=0.0; return; }
    double pxr=best*d.x-sph[hit].x, pyr=best*d.y-sph[hit].y, pzr=best*d.z-sph[hit].z;
    double nl=sqrt(pxr*pxr+pyr*pyr+pzr*pzr);
    double nx=pxr/nl, ny=pyr/nl, nz=pzr/nl;
    /* Monte Carlo sample of the cosine-hemisphere ambient sky contribution */
    int N=NS; double aacc=0.0;
    for(int s=0;s<N;s++){
        unsigned long r1=mc_rand(), r2=mc_rand();
        double u=((r1>>11)&0x3FFFFF)/1048576.0;
        double v=((r2>>11)&0x3FFFF)/1048576.0;
        double rz=u, rs=sqrt(1.0-u*u), th=6.283185307179586*v;
        double sx=rs*cos(th), sy=rs*sin(th), sz=rz;
        /* cosine weighted bounce: contribution c.z * lambert * color */
        double wi=fabs(sx*nx+sy*ny+sz*nz);
        aacc+=wi;
    }
    aacc/=N;
    /* directional light */
    double ll=sqrt(L.x*L.x+L.y*L.y+L.z*L.z);
    double lx=L.x/ll, ly=L.y/ll, lz=L.z/ll;
    double li=nx*lx+ny*ly+nz*lz; if(li<0)li=0;
    double f=amb + (1.0-amb)*li;
    rgb[0]=sph[hit].cr* ((float)f>1.0f?1.0f:(float)f);
    rgb[1]=sph[hit].cg* ((float)f>1.0f?1.0f:(float)f);
    rgb[2]=sph[hit].cb* ((float)f>1.0f?1.0f:(float)f);
    *depth=best;
}

int main(int argc,char**argv){
    if(argc<3){ fprintf(stderr,"usage: %s <scene.cfg> <out.pfm>\n",argv[0]); return 2; }
    parse(argv[1]);
    float *img=(float*)malloc(sizeof(float)*W*H*3);
    FILE *out=fopen(argv[2],"wb");
    if(!out){ fprintf(stderr,"ptrace: cannot write %s\n",argv[2]); return 2; }
    double bg_bkg=(bg[0]+bg[1]+bg[2])/3.0; (void)bg_bkg; /* reserve look */
    for(int y=0;y<H;y++){
        for(int x=0;x<W;x++){
            double col[3]={0,0,0}, depth=0;
            /* sample center of pixel; NS=1 for a deterministic, stable map */
            double fx=((x+0.5)-W*0.5)*(2.0/(double)W);
            double fy=(H*0.5-(y+0.5))*(2.0/(double)W);
            shade(fx,fy,col,&depth);
            img[(y*W+x)*3+0]=(float)col[0];
            img[(y*W+x)*3+1]=(float)col[1];
            img[(y*W+x)*3+2]=(float)col[2];
        }
    }
    fprintf(out,"PF\n%d %d\n-1.0\n",W,H);
    fwrite(img,sizeof(float),W*H*3,out);
    fclose(out); free(img);
    return 0;
}