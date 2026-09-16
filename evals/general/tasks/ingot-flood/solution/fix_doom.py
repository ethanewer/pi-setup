#!/usr/bin/env python3
"""Apply the ingot-flood modernisation repairs to a pristine
linuxdoom-1.10 tree.

Every edit is a root-cause fix for a 1997-code-on-2024-toolchain
incompatibility. Apply from the tree root:

    cd /app/src/linuxdoom-1.10 && python3 fix_doom.py

Each edit is verified by re-reading the file; any anchor that no longer
matches (upstream drift) is reported and the script exits non-zero.
"""

EDIT = []
def edit(path, old, new):
    EDIT.append((path, old, new))

# ---- i_video.c: libc5-era header name ------------------------------------
edit("i_video.c",
     "#include <errnos.h>",
     "#include <errno.h>")

# ---- i_sound.c: drop obsolete sys/filio.h, use glibc's errno ------------
edit("i_sound.c",
     "#include <sys/filio.h>",
     "")
edit("i_sound.c",
     "#include <sys/ioctl.h>\n\n// Linux voxware output.",
     "#include <sys/ioctl.h>\n#include <errno.h>\n\n// Linux voxware output.")
edit("i_sound.c",
     "    int\t\trc;\n    extern int\terrno;\n",
     "    int\t\trc;\n")

# ---- Makefile: no longer link the retired libnsl stub library ------------
edit("Makefile",
     "LIBS=-lXext -lX11 -lnsl -lm",
     "LIBS=-lXext -lX11 -lm")

# ---- m_misc.c: string-valued defaults cannot store pointer constants -----
for i in range(9):
    edit("m_misc.c",
         '{"chatmacro%d", (int *) &chat_macros[%d], (int) HUSTR_CHATMACRO%d },' % (i, i, i),
         '{"chatmacro%d", (int *) &chat_macros[%d], 0 },' % (i, i))
edit("m_misc.c",   # last entry of the table: no trailing comma
     '{"chatmacro9", (int *) &chat_macros[9], (int) HUSTR_CHATMACRO9 }',
     '{"chatmacro9", (int *) &chat_macros[9], 0 }')
edit("m_misc.c",
     '    {"sndserver", (int *) &sndserver_filename, (int) "sndserver"},',
     '    {"sndserver", (int *) &sndserver_filename, 0},')
edit("m_misc.c",
     '    {"mousedev", (int*)&mousedev, (int)"/dev/ttyS0"},',
     '    {"mousedev", (int*)&mousedev, 0},')
edit("m_misc.c",
     '    {"mousetype", (int*)&mousetype, (int)"microsoft"},',
     '    {"mousetype", (int*)&mousetype, 0},')
edit("m_misc.c",
     """    for (i=0 ; i<numdefaults ; i++)
	*defaults[i].location = defaults[i].defaultvalue;""",
     """    for (i=0 ; i<numdefaults ; i++)
	if (defaults[i].defaultvalue)
	    *defaults[i].location = defaults[i].defaultvalue;""")

# ---- d_main.c: IWAD discovery buffers were sized exactly, then--->
# ---- sprintf wrote past them (abort under -O2 fortification) ----
for wad, n9 in (("doom2wad", 9), ("doomuwad", 8),
                ("doomwad", 8), ("doom1wad", 9)):
    edit("d_main.c",
         "    %s = malloc(strlen(doomwaddir)+1+%d+1);" % (wad, n9),
         "    %s = malloc(strlen(doomwaddir)+16);" % wad)

# ---- r_data.c: 32-bit-era pointer-array sizing and pointer casts ---------
edit("r_data.c",
     """    textures = Z_Malloc (numtextures*4, PU_STATIC, 0);
    texturecolumnlump = Z_Malloc (numtextures*4, PU_STATIC, 0);
    texturecolumnofs = Z_Malloc (numtextures*4, PU_STATIC, 0);
    texturecomposite = Z_Malloc (numtextures*4, PU_STATIC, 0);""",
     """    textures = Z_Malloc (numtextures*sizeof(*textures), PU_STATIC, 0);
    texturecolumnlump = Z_Malloc (numtextures*sizeof(*texturecolumnlump), PU_STATIC, 0);
    texturecolumnofs = Z_Malloc (numtextures*sizeof(*texturecolumnofs), PU_STATIC, 0);
    texturecomposite = Z_Malloc (numtextures*sizeof(*texturecomposite), PU_STATIC, 0);""")
edit("r_data.c",
     "    colormaps = (byte *)( ((int)colormaps + 255)&~0xff); ",
     "    colormaps = (byte *)( ((unsigned long)colormaps + 255)&~0xffUL); ")

# ---- r_draw.c: same pointer-cast misalignment in the light tables --------
edit("r_draw.c",
     "    translationtables = (byte *)(( (int)translationtables + 255 )& ~255);",
     "    translationtables = (byte *)( ((unsigned long)translationtables + 255) & ~255UL );")


def main():
    failures = []
    for path, old, new in EDIT:
        try:
            s = open(path).read()
        except OSError as exc:
            failures.append("%s: cannot open: %s" % (path, exc))
            continue
        if old not in s:
            failures.append("%s: anchor missing: %r" % (path, old[:70]))
            continue
        open(path, "w").write(s.replace(old, new))
        print("ok   %-10s %s" % (path, old.splitlines()[0][:50]))
    if failures:
        print("fix_doom: %d edit(s) failed:" % len(failures))
        for f in failures:
            print("  " + f)
        raise SystemExit(1)
    print("ingot-flood: all repairs applied and verified")


if __name__ == "__main__":
    main()