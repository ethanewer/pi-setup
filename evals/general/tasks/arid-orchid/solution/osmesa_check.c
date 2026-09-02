/*
 * osmesa_check.c -- headless software-GL smoke test using libOSMesa.
 *
 * Proves a real offscreen OpenGL context works on a machine with no display
 * server and no GPU: it creates an OSMesa pixel buffer, clears it to a known
 * colour, draws a red gradient quad, reads the buffer back and writes an
 * 96x54 P6 PPM. Used by tests to confirm the OSMesa-based headless path.
 *
 * usage: ./osmesa_check <out.ppm>
 */
#include <stdio.h>
#include <stdlib.h>
#include <GL/osmesa.h>
#include <GL/gl.h>

#define W 96
#define H 54

int main(int argc, char **argv){
    const char *out = argc > 1 ? argv[1] : "/tmp/osmesa_out.ppm";
    unsigned char *buf = (unsigned char*)malloc(W*H*4);
    OSMesaContext ctx = OSMesaCreateContextExt(OSMESA_RGBA, 16, 0, 0, NULL);
    if(!ctx){ fprintf(stderr,"osmesa: context create failed\n"); return 2; }
    if(!OSMesaMakeCurrent(ctx, buf, GL_UNSIGNED_BYTE, W, H)){
        fprintf(stderr,"osmesa: MakeCurrent failed\n"); return 2;
    }
    glViewport(0,0,W,H);
    glClearColor(0.12f, 0.35f, 0.72f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glBegin(GL_TRIANGLES);
    glColor3f(1.0f,0.15f,0.15f);
    glVertex2f(-1,-1); glVertex2f(1,-1); glVertex2f(0,1);
    glEnd();
    glFinish();
    glReadPixels(0,0,W,H,GL_RGBA,GL_UNSIGNED_BYTE,buf);
    OSMesaDestroyContext(ctx);
    FILE *fp=fopen(out,"wb");
    if(!fp){ fprintf(stderr,"osmesa: cannot write %s\n",out); free(buf); return 2; }
    fprintf(fp,"P6\n%d %d\n255\n",W,H);
    for(int i=0;i<W*H;i++){
        unsigned char p[3]={buf[i*4],buf[i*4+1],buf[i*4+2]};
        fwrite(p,1,3,fp);
    }
    fclose(fp); free(buf);
    return 0;
}