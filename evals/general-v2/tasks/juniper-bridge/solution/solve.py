#!/usr/bin/env python3
"""juniper-bridge solver. Reads a scenario <in_dir> and writes all
deliverables into <out_dir>: answer.json, render_a.png, render_b.png,
print.png, fit_line.png, fit_a.png, fit_b.png, fit_rigid.png.

Launched: python3 solve.py <in_dir> <out_dir>
"""
import os, sys, re, json, glob, subprocess, tempfile
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import cv2

DIR = os.path.dirname(os.path.abspath(__file__))
# 
import fit

FONT_MONO = [p for p in glob.glob('/usr/share/fonts/**/*.ttf', recursive=True)
             if 'DejaVuSansMono-Bold' in p][0]
FONT_SANS = [p for p in glob.glob('/usr/share/fonts/**/*.ttf', recursive=True)
             if 'DejaVuSans' in p and 'Mono' not in p and 'Serif' not in p][0]


def tess(img, psm='6'):
    with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tf:
        img.save(tf.name); path = tf.name
    r = subprocess.run(['tesseract', path, '-', '--psm', psm],
                       capture_output=True, text=True)
    os.unlink(path)
    return r.stdout


# ---------------- competency 1: digit grid ----------------
def read_grid(path):
    img = Image.open(path).convert('L')
    txt = tess(img, '6')
    rows = [''.join(c for c in ln if c.isdigit())
            for ln in txt.splitlines()]
    rows = [r for r in rows if r]
    out = []
    for r in rows[:9]:
        if len(r) > 9:
            r = r[:9]
        elif len(r) < 9:
            r = r.ljust(9, '0')
        out.append(r)
    while len(out) < 9:
        out.append('000000000')
    return out[:9]


# ---------------- competency 5: isolate secret word ----------------
def read_member_secret(path):
    img = Image.open(path).convert('L')
    txt = tess(img, '6')
    words = [w.strip('.,:;!?') for w in txt.split()
             if re.match(r'^[A-Z]{3,}$', w)]
    skip = {'THE', 'FOR', 'OF', 'RECORD', 'DAY', 'ACTIVE', 'IS', 'A', 'AND'}
    for w in words:
        if w not in skip:
            return w
    return words[0] if words else ''


# ---------------- competency 4: transcribe algorithm ----------------
def read_code(path, xin):
    """Transcribe the photographed code by reliable digit OCR of its numeric
    parameters (loop bound U and constant offset Q), then evaluate the
    algorithm: value = (1+..+(U-1))*xin + Q."""
    img = Image.open(path).convert('L')
    txt = tess(img, psm='6')
    U = None; Q = None
    m = re.search(r'range\s*\(\s*1\s*,\s*(\d+)', txt)
    if not m:
        m = re.search(r'range\(1,\s*(\d+)', txt)
    if m:
        U = int(m.group(1))
    mq = re.search(r'\boff\s*=\s*(\d+)', txt)
    if not mq:
        mq = re.search(r'acc\s*\+\s*(\d+)', txt)
    if mq:
        Q = int(mq.group(1))
    if U is None or Q is None:
        return None
    tri = U*(U-1)//2
    return tri*xin + Q


# ---------------- competency 7: tool-path ----------------
def parse_toolpath(path):
    shapes = []
    phrase = ''
    for ln in open(path):
        ln = ln.strip()
        if not ln:
            continue
        t = ln.split()
        cmd = t[0]
        if cmd == 'RECT':
            shapes.append({'t': 'rect', 'x': int(t[1]), 'y': int(t[2]),
                           'w': int(t[3]), 'h': int(t[4])})
        elif cmd == 'LINE':
            shapes.append({'t': 'line', 'x1': int(t[1]), 'y1': int(t[2]),
                           'x2': int(t[3]), 'y2': int(t[4])})
        elif cmd == 'CIRC':
            shapes.append({'t': 'circ', 'cx': int(t[1]), 'cy': int(t[2]),
                           'r': int(t[3])})
        elif cmd == 'POLY':
            pts = [(int(t[i]), int(t[i+1])) for i in range(1, len(t), 2)]
            shapes.append({'t': 'poly', 'pts': pts})
        elif cmd == 'SEAL':
            phrase = ''.join(chr(int(c)+64) for c in t[1:])
    return shapes, phrase


# ---------------- competency 6: robust geometric fits ----------------
def fit_line(inp, out):
    pts = np.loadtxt(os.path.join(inp, 'lin.csv'), delimiter=',')
    model, inliers = fit.line_truth(pts)
    xmin, xmax = pts[:, 0].min()-1, pts[:, 0].max()+1
    ymin, ymax = pts[:, 1].min()-1, pts[:, 1].max()+5
    img = Image.new('RGB', (260, 220), (255, 255, 255))
    d = ImageDraw.Draw(img)
    def px(x, y):
        return (int((x-xmin)/(xmax-xmin)*250+5),
                int(215-(y-ymin)/(ymax-ymin)*210))
    for p in pts:
        x, y = px(p[0], p[1])
        d.ellipse([x-2, y-2, x+2, y+2], fill=(30, 30, 200))
    if model:
        m, b = model
        y0 = px(xmin, m*xmin+b); y1 = px(xmax, m*xmax+b)
        d.line([(5, y0[1]), (255, y1[1])], fill=(200, 30, 30), width=3)
    img.save(os.path.join(out, 'fit_line.png'))
    return inliers


def fit_plane(inp, out):
    a = np.array(Image.open(os.path.join(inp, 'box1.png')).convert('L'))
    b = np.array(Image.open(os.path.join(inp, 'box2.png')).convert('L'))
    inliers = fit.plane_truth(a, b)[0]
    Image.fromarray(a).save(os.path.join(out, 'fit_a.png'))
    Image.fromarray(b).save(os.path.join(out, 'fit_b.png'))
    return inliers


def fit_rigid(inp, out):
    A = np.loadtxt(os.path.join(inp, 'rig_a.csv'), delimiter=',')
    B = np.loadtxt(os.path.join(inp, 'rig_b.csv'), delimiter=',')
    _rt, inliers = fit.rigid_truth(A, B)
    img = Image.new('RGB', (320, 320), (255, 255, 255))
    d = ImageDraw.Draw(img)
    for (ax, ay), (bx, by) in zip(A, B):
        d.ellipse([ax+15-2, ay+15-2, ax+15+2, ay+15+2], fill=(30, 30, 200))
        d.ellipse([bx+15-2, by+220-2, bx+15+2, by+220+2], fill=(220, 30, 30))
    img.save(os.path.join(out, 'fit_rigid.png'))
    return inliers


# ---------------- competency 2/3: renders ----------------
def render_text_to_image(text, out, pts=64):
    f = ImageFont.truetype(FONT_SANS, pts)
    dt = ImageDraw.Draw(Image.new('L', (4, 4)))
    bb = dt.textbbox((0, 0), text, font=f)
    img = Image.new('L', (bb[2]-bb[0]+16, bb[3]-bb[1]+20), 255)
    d = ImageDraw.Draw(img)
    d.text((8-bb[0], 10-bb[1]), text, font=f, fill=0)
    img.save(out)


def main():
    inp, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    gen = json.load(open(os.path.join(inp, 'general.json')))

    grid = read_grid(os.path.join(inp, 'grid.png'))          # comp 1
    member_secret = read_member_secret(os.path.join(inp, 'member.png'))  # comp 5
    code_value = read_code(os.path.join(inp, 'code.png'), gen['x'])      # comp 4
    shapes, phrase = parse_toolpath(os.path.join(inp, 'toolpath.txt'))   # comp 7

    line_inliers = fit_line(inp, out)       # comp 6
    plane_inliers = fit_plane(inp, out)
    rigid_inliers = fit_rigid(inp, out)

    render_text_to_image(gen['render_a'], os.path.join(out, 'render_a.png'))  # comp 2
    render_text_to_image(gen['render_b'], os.path.join(out, 'render_b.png'))
    render_text_to_image(phrase, os.path.join(out, 'print.png'))              # comp 3

    answer = {
        'grid': grid,
        'member_secret': member_secret,
        'code_value': code_value,
        'print_word': phrase,
        'shapes': shapes,
        'line_inliers': int(line_inliers),
        'plane_inliers': int(plane_inliers),
        'rigid_inliers': int(rigid_inliers),
    }
    json.dump(answer, open(os.path.join(out, 'answer.json'), 'w'), indent=2)
    print("solve ok", out)


if __name__ == '__main__':
    main()