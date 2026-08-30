/*
 * zep.c - single-pass compiler for the Zephyr toy language.
 *
 * Zephyr is a small, clean-room, C-like language with byte buffers, signed
 * integers, arithmetic, conditionals, loops, user functions and two stream
 * builtins.  This program is the COMPILER: it reads a ".zh" source file,
 * parses it with a recursive-descent parser and emits an equivalent portable
 * C program, then invokes the host C compiler (gcc) to produce the native
 * executable (or, with -c, a relocatable object).
 *
 * It is intentionally self-contained: only standard libc is used, and it
 * depends on nothing from any third-party compiler source tree.
 *
 * Usage (installed as /app/cc/bin/cc):
 *   zep [-c] [-o OUT] SOURCE.zh
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* ------------------------------------------------------------------ */
/* Tokenizer                                                          */
/* ------------------------------------------------------------------ */
enum {
    T_EOF, T_ID, T_NUM,
    T_LP, T_RP, T_LB, T_RB, T_LC, T_RC,
    T_SEMI, T_COMMA, T_ASGN,
    T_PLUS, T_MINUS, T_STAR, T_SLASH, T_PERC,
    T_AMP, T_PIPE, T_BANG,
    T_LT, T_GT, T_LE, T_GE, T_EQEQ, T_NE,
    T_QUES, T_COLON, T_BAND, T_BOR,
    K_BREAK, K_IF, K_ELSE, K_WHILE, K_RETURN, K_BYTE, K_INT, K_VOID
};

#define MAXID 256
static char *src;
static size_t slen, spos;
static char  ident[MAXID];
static long  numval;
static int   cur;

static int isidc(int c){ return (c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='_'; }
static int isdig(int c){ return c>='0'&&c<='9'; }

static int kw(const char *s){
    if (!strcmp(s,"break")) return K_BREAK;
    if (!strcmp(s,"if")) return K_IF;
    if (!strcmp(s,"else")) return K_ELSE;
    if (!strcmp(s,"while")) return K_WHILE;
    if (!strcmp(s,"return")) return K_RETURN;
    if (!strcmp(s,"byte")) return K_BYTE;
    if (!strcmp(s,"int")) return K_INT;
    if (!strcmp(s,"void")) return K_VOID;
    return T_ID;
}

static void skip_ws(void){
    for (;;){
        while (spos < slen && (src[spos]==' '||src[spos]=='\t'||
               src[spos]=='\n'||src[spos]=='\r')) spos++;
        if (spos+1 < slen && src[spos]=='/' && src[spos+1]=='/'){
            while (spos < slen && src[spos]!='\n') spos++;
            continue;
        }
        if (spos+1 < slen && src[spos]=='/' && src[spos+1]=='*'){
            spos += 2;
            while (spos+1 < slen && !(src[spos]=='*'&&src[spos+1]=='/')) spos++;
            spos += 2;
            continue;
        }
        break;
    }
}

static int next_tok(void){
    skip_ws();
    if (spos >= slen) return (cur=T_EOF);
    int c = src[spos];
    if (isidc(c) && c!='0' && c!='1' && c!='2' && c!='3' && c!='4' &&
        c!='5' && c!='6' && c!='7' && c!='8' && c!='9'){
        int n=0; while (spos < slen && isidc(src[spos]) && n<MAXID-1) ident[n++]=src[spos++];
        ident[n]=0;
        return (cur = kw(ident));
    }
    if (isdig(c)){
        long v=0;
        if (c=='0' && spos+1 < slen && (src[spos+1]=='x'||src[spos+1]=='X')){
            spos += 2;
            while (spos < slen && (isdig(src[spos])||
                   (src[spos]>='a'&&src[spos]<='f')||(src[spos]>='A'&&src[spos]<='F'))){
                char ch=src[spos]; int d=
                    (ch>='a')? ch-'a'+10 : (ch>='A')? ch-'A'+10 : ch-'0';
                v = v*16 + d; spos++;
            }
        } else {
            while (spos < slen && isdig(src[spos])) { v=v*10 + (src[spos]-'0'); spos++; }
        }
        numval=v; return (cur=T_NUM);
    }
    spos++;
    switch (c){
        case '(': return (cur=T_LP);
        case ')': return (cur=T_RP);
        case '[': return (cur=T_LB);
        case ']': return (cur=T_RB);
        case '{': return (cur=T_LC);
        case '}': return (cur=T_RC);
        case ';': return (cur=T_SEMI);
        case ',': return (cur=T_COMMA);
        case '=':
            if (spos < slen && src[spos]=='='){ spos++; return (cur=T_EQEQ); }
            return (cur=T_ASGN);
        case '+': return (cur=T_PLUS);
        case '-': return (cur=T_MINUS);
        case '*': return (cur=T_STAR);
        case '/': return (cur=T_SLASH);
        case '%': return (cur=T_PERC);
        case '&':
            if (spos < slen && src[spos]=='&'){ spos++; return (cur=T_AMP); }
            return (cur=T_BAND);
        case '|':
            if (spos < slen && src[spos]=='|'){ spos++; return (cur=T_PIPE); }
            return (cur=T_BOR);
        case '!':
            if (spos < slen && src[spos]=='='){ spos++; return (cur=T_NE); }
            return (cur=T_BANG);
        case '<':
            if (spos < slen && src[spos]=='='){ spos++; return (cur=T_LE); }
            return (cur=T_LT);
        case '>':
            if (spos < slen && src[spos]=='='){ spos++; return (cur=T_GE); }
            return (cur=T_GT);
        case '?': return (cur=T_QUES);
        case ':': return (cur=T_COLON);
    }
    fprintf(stderr,"zep: unexpected character '%c'\n", c);
    exit(1);
}

/* ------------------------------------------------------------------ */
/* Output                                                             */
/* ------------------------------------------------------------------ */
static FILE *out;
static void o(const char *s){ fputs(s, out); }

/* ------------------------------------------------------------------ */
/* Expression parsing (precedence climbing)                           */
/* ------------------------------------------------------------------ */
static void gen_expr(void);

static void gen_primary(void){
    if (cur==T_NUM){ fprintf(out,"%ld", numval); next_tok(); }
    else if (cur==T_ID){
        char n[MAXID]; strncpy(n, ident, MAXID-1); n[MAXID-1]=0;
        next_tok();
        if (cur==T_LP){
            if (!strcmp(n,"out")) o("z_out(");
            else if (!strcmp(n,"read_all")) o("z_read_all(");
            else fprintf(out,"_%s(", n);
            next_tok(); /* ( */
            if (cur!=T_RP){ gen_expr(); while (cur==T_COMMA){ o(", "); next_tok(); gen_expr(); } }
            o(")");
            if (cur==T_RP) next_tok();
        } else if (cur==T_LB){
            fprintf(out,"%s[(", n);
            next_tok();
            gen_expr();
            o(")]");
            if (cur==T_RB) next_tok();
        } else {
            o(n);
        }
    }
    else if (cur==T_LP){
        next_tok(); o("("); gen_expr(); o(")"); if (cur==T_RP) next_tok();
    }
    else {
        fprintf(stderr,"zep: expected expression\n");
        exit(1);
    }
}

static void gen_unary(void){
    if (cur==T_BANG){ o("(!"); next_tok(); gen_unary(); o(")"); }
    else if (cur==T_MINUS){ o("(-"); next_tok(); gen_unary(); o(")"); }
    else gen_primary();
}
static void gen_mul(void){
    gen_unary();
    for(;;){
        if (cur==T_STAR){ o("*"); next_tok(); gen_unary(); }
        else if (cur==T_SLASH){ o("/"); next_tok(); gen_unary(); }
        else if (cur==T_PERC){ o("%"); next_tok(); gen_unary(); }
        else break;
    }
}
static void gen_add(void){
    gen_mul();
    for(;;){
        if (cur==T_PLUS){ o("+"); next_tok(); gen_mul(); }
        else if (cur==T_MINUS){ o("-"); next_tok(); gen_mul(); }
        else break;
    }
}
static void gen_cmp(void){
    gen_add();
    for(;;){
        if (cur==T_LT){ o("<"); next_tok(); gen_add(); }
        else if (cur==T_GT){ o(">"); next_tok(); gen_add(); }
        else if (cur==T_LE){ o("<="); next_tok(); gen_add(); }
        else if (cur==T_GE){ o(">="); next_tok(); gen_add(); }
        else break;
    }
}
static void gen_eq(void){
    gen_cmp();
    for(;;){
        if (cur==T_EQEQ){ o("=="); next_tok(); gen_cmp(); }
        else if (cur==T_NE){ o("!="); next_tok(); gen_cmp(); }
        else break;
    }
}
static void gen_band(void){ gen_eq(); while (cur==T_BAND){ o("&"); next_tok(); gen_eq(); } }
static void gen_and(void){ gen_band(); while (cur==T_AMP){ o("&&"); next_tok(); gen_band(); } }
static void gen_bor(void){ gen_and(); while (cur==T_BOR){ o("|"); next_tok(); gen_and(); } }
static void gen_or(void){ gen_bor(); while (cur==T_PIPE){ o("||"); next_tok(); gen_bor(); } }

static void gen_expr(void){
    gen_or();
    if (cur==T_QUES){
        o(" ? "); next_tok(); gen_expr();
        o(" : "); next_tok(); gen_expr();
    }
}

/* ------------------------------------------------------------------ */
/* Statements                                                         */
/* ------------------------------------------------------------------ */
static void gen_stmt(void);

static void gen_block(void){
    o("{\n");
    if (cur==T_LC) next_tok();
    while (cur!=T_RC && cur!=T_EOF) gen_stmt();
    if (cur==T_RC) next_tok();
    o("}\n");
}

static void gen_stmt(void){
    if (cur==K_IF){
        o("if ("); next_tok();
        if (cur==T_LP) next_tok();
        gen_expr();
        if (cur==T_RP) next_tok();
        o(") ");
        gen_stmt();
        if (cur==K_ELSE){ o(" else "); next_tok(); gen_stmt(); }
    }
    else if (cur==K_WHILE){
        o("while ("); next_tok();
        if (cur==T_LP) next_tok();
        gen_expr();
        if (cur==T_RP) next_tok();
        o(") ");
        gen_stmt();
    }
    else if (cur==K_RETURN){
        o("return"); next_tok();
        if (cur!=T_SEMI){ o(" "); gen_expr(); }
        o(";\n"); if (cur==T_SEMI) next_tok();
    }
    else if (cur==K_BREAK){
        o("break;\n"); next_tok();
    }
    else if (cur==T_SEMI){ o(";\n"); next_tok(); }
    else if (cur==T_LC){ gen_block(); }
    else if (cur==K_INT){
        next_tok();
        o("int ");
        if (cur==T_ID){ o(ident); next_tok(); }
        if (cur==T_ASGN){ o("="); next_tok(); gen_expr(); }
        o(";\n");
        if (cur==T_SEMI) next_tok();
    }
    else if (cur==K_BYTE){
        next_tok();
        if (cur==T_ID){ o("unsigned char "); o(ident); next_tok(); }
        if (cur==T_LB){
            o("["); next_tok();
            if (cur==T_NUM){ fprintf(out,"%ld", numval); next_tok(); }
            o("]");
            if (cur==T_RB) next_tok();
        }
        o(";\n");
        if (cur==T_SEMI) next_tok();
    }
    else if (cur==T_ID){
        char n[96]; strcpy(n, ident); next_tok();
        if (cur==T_ASGN){
            fprintf(out,"%s = ", n); next_tok(); gen_expr();
            o(";\n"); if (cur==T_SEMI) next_tok();
        }
        else if (cur==T_LB){
            fprintf(out,"%s[(", n); next_tok(); gen_expr();
            o(")]"); if (cur==T_RB) next_tok();
            if (cur==T_ASGN){ o(" = "); next_tok(); gen_expr(); o(";\n"); if (cur==T_SEMI) next_tok(); }
            else { fprintf(stderr,"zep: need '=' after index\n"); exit(1); }
        }
        else if (cur==T_LP){
            if (!strcmp(n,"out")) o("z_out(");
            else if (!strcmp(n,"read_all")) o("z_read_all(");
            else fprintf(out,"_%s(", n);
            next_tok();
            if (cur!=T_RP){ gen_expr(); while(cur==T_COMMA){ o(","); next_tok(); gen_expr(); } }
            o(");\n"); if (cur==T_RP) next_tok(); if (cur==T_SEMI) next_tok();
        }
        else { fprintf(stderr,"zep: bad statement (id=%s cur=%d)\n", n, cur); exit(1); }
    }
    else { fprintf(stderr,"zep: unexpected statement (cur=%d)\n", cur); exit(1); }
}

/* ------------------------------------------------------------------ */
/* Functions                                                          */
/* ------------------------------------------------------------------ */
static void gen_func(void){
    int is_main = 0;
    if (cur==K_INT){ o("int "); next_tok(); }
    else if (cur==K_VOID){ o("void "); next_tok(); }
    else o("void ");
    if (cur==T_ID){
        if (!strcmp(ident,"main")) is_main=1;
        if (is_main) fprintf(out,"main"); else fprintf(out,"_%s",ident);
        next_tok();
    } else { fprintf(stderr,"zep: function name\n"); exit(1); }
    fprintf(out,"(");
    if (cur==T_LP) next_tok();
    if (cur==K_VOID && /* param list void */ 0){}
    if (cur!=T_RP){
        int first=1;
        for(;;){
            if (!first) fprintf(out,", ");
            first=0;
            if (cur==K_INT) next_tok(); else { fprintf(stderr,"zep: param type 'int'\n"); exit(1); }
            if (cur==T_ID){ fprintf(out,"int %s", ident); next_tok(); }
            else { fprintf(stderr,"zep: param name\n"); exit(1); }
            if (cur==T_COMMA){ next_tok(); continue; }
            break;
        }
    }
    fprintf(out,")");
    if (cur==T_RP) next_tok();
    o(" ");
    if (cur==T_LC){ gen_block(); }
    else { fprintf(stderr,"zep: function body\n"); exit(1); }
}

/* ------------------------------------------------------------------ */
/* Driver                                                             */
/* ------------------------------------------------------------------ */

int main(int argc, char **argv){
    const char *infile=NULL, *outfile="a.out";
    int obj=0;
    for (int i=1;i<argc;i++){
        if (!strcmp(argv[i],"-c")) obj=1;
        else if (!strcmp(argv[i],"-o") && i+1<argc){ outfile=argv[++i]; }
        else if (!strncmp(argv[i],"-std=",5)){ /* accepted but unused */ }
        else if (argv[i][0]!='-') infile=argv[i];
        else { fprintf(stderr,"zep: bad option %s\n", argv[i]); return 2; }
    }
    if (!infile){ fprintf(stderr,"zep: no input file\n"); return 2; }

    FILE *in=fopen(infile,"rb"); if(!in){ perror("zep: input"); return 2; }
    fseek(in,0,SEEK_END); long sz=ftell(in); fseek(in,0,SEEK_SET);
    src=malloc(sz+1); if(!src){ return 2; }
    if (fread((void*)src,1,sz,in)!=sz){ return 2; }
    src[sz]=0; slen=sz; fclose(in);

    char tc[4096]; snprintf(tc,sizeof tc,"/tmp/zep_%ld.c", (long)getpid());
    out=fopen(tc,"w");
    o("#include <stdio.h>\n");
    o("static int z_read_all(unsigned char *d){ int n=0,c; while((c=getchar())!=EOF){ d[n++]=(unsigned char)c; } return n; }\n");
    o("static void z_out(int b){ putchar((unsigned char)b); }\n\n");
    next_tok();
    while (cur!=T_EOF){
        if (cur==K_BYTE){
            next_tok();
            if (cur==T_ID){ fprintf(out,"unsigned char %s[", ident); next_tok();
                if (cur==T_LB) next_tok();
                if (cur==T_NUM){ fprintf(out,"%ld", numval); next_tok(); }
                o("];\n"); if (cur==T_RB) next_tok(); if (cur==T_SEMI) next_tok();
            } else { fprintf(stderr,"zep: global byte array\n"); return 1; }
        } else if (cur==K_INT || cur==K_VOID || cur==T_ID){
            gen_func();
        } else { fprintf(stderr,"zep: top-level token\n"); return 1; }
    }
    fclose(out);

    char cmd[8192];
    if (obj) snprintf(cmd,sizeof cmd,"gcc -O2 -w -c -o %s %s", outfile, tc);
    else     snprintf(cmd,sizeof cmd,"gcc -O2 -w -o %s %s", outfile, tc);
    int rc = system(cmd);
    if (getenv("ZEP_KEEP")) fprintf(stderr,"[zep] kept temp C at %s\n", tc);
    else remove(tc);
    return rc;
}