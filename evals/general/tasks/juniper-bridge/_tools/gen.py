#!/usr/bin/env python3
"""Clean-room fixture generator for juniper-bridge.

  python3 gen.py <outdir> <seed> <label>

Writes: grid.png, member.png, code.png, toolpath.txt, general.json,
fit/lin.csv, fit/box1.png, fit/box2.png, fit/rig_a.csv, fit/rig_b.csv,
and expected.json (ground truth) into <outdir>.
"""
import os, sys, json, glob
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import cv2

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fit

FW = [p for p in glob.glob('/usr/share/fonts/**/*.ttf', recursive=True) if 'DejaVuSansMono-Bold' in p][0]
DS = [p for p in glob.glob('/usr/share/fonts/**/*.ttf', recursive=True) if 'DejaVuSans' in p and 'Mono' not in p and 'Serif' not in p][0]

SECRETS = ["KELVIN", "CRIMSON", "POSEIDON", "OBELISK", "NIMBUS",
           "HARBOR", "VERDANT", "TOPAZ", "AZURE", "CEDAR"]
PHRASES = ["BRIDGE", "TRUSS", "SPAN", "PIER", "ARCH", "GIRDER", "TRESTLE", "CAUSEWAY"]


# ---------------- rendering helpers ----------------
def grid_image(grid):
    cell = 56; n = 9
    img = Image.new('L', (n*cell, n*cell), 255); d = ImageDraw.Draw(img)
    f = ImageFont.truetype(FW, int(cell*0.75))
    for row in range(n):
        for col in range(n):
            ch = grid[row][col]
            if ch == '0':
                continue
            bb = d.textbbox((0, 0), ch, font=f)
            w, h = bb[2]-bb[0], bb[3]-bb[1]
            d.text((col*cell+(cell-w)/2-bb[0], row*cell+(cell-h)/2-bb[1]),
                   ch, font=f, fill=0)
    # faint rulings only (do not let lines merge into the digits)
    return img


def member_image(sentence, pts=54):
    f = ImageFont.truetype(DS, pts)
    d0 = ImageDraw.Draw(Image.new('L', (4, 4)))
    bb = d0.textbbox((0, 0), sentence, font=f)
    img = Image.new('L', (bb[2]-bb[0]+10, bb[3]-bb[1]+14), 255)
    d = ImageDraw.Draw(img)
    d.text((5-bb[0], 7-bb[1]), sentence, font=f, fill=0)
    return img


def code_image(code_text, pts=34):
    f = ImageFont.truetype(FW, pts); asc, desc = f.getmetrics()
    adv = ImageDraw.Draw(Image.new('L', (4, 4))).textlength('MM', font=f)/2
    lines = code_text.split('\n')
    W = int(max(len(l) for l in lines)*adv)+14
    H = (asc+desc)*len(lines)+14
    img = Image.new('L', (W, H), 255); d = ImageDraw.Draw(img); y = 7+asc
    for ln in lines:
        d.text((7, y), ln, font=f, fill=0); y += asc+desc
    a = cv2.filter2D(np.array(img).astype(np.float32), -1,
                     np.ones((3, 3), np.float32)/9)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def make_tooltext(shapes, phrase):
    codes = [ord(ch)-64 for ch in phrase]
    lines = ["UNIT PREC46"]
    for s in shapes:
        if s['t'] == 'rect':
            lines.append("RECT %d %d %d %d" % (s['x'], s['y'], s['w'], s['h']))
        elif s['t'] == 'line':
            lines.append("LINE %d %d %d %d" % (s['x1'], s['y1'], s['x2'], s['y2']))
        elif s['t'] == 'circ':
            lines.append("CIRC %d %d %d" % (s['cx'], s['cy'], s['r']))
        elif s['t'] == 'poly':
            lines.append("POLY " + " ".join("%d %d" % p for p in s['pts']))
    lines.append("SEAL " + " ".join(str(c) for c in codes))
    return "\n".join(lines) + "\n"


# ---------------- feature builders ----------------
def line_points(seed, nin=92, nout=16, noise=3.0):
    r = np.random.RandomState(seed)
    x = np.linspace(0, 100, nin); y = 1.7*x+23.0
    pts = np.stack([x, y+r.uniform(-noise, noise, nin)], 1)
    out = np.stack([r.uniform(0, 100, nout), r.uniform(0, 210, nout)], 1)
    return np.vstack([pts, out])


def homography_pair(seed, size=240):
    r = np.random.RandomState(seed)
    a = r.randint(0, 256, (size, size)).astype(np.uint8)
    for _ in range(2):
        a = cv2.GaussianBlur(a, (3, 3), 0)
    H = np.array([[1.13, -0.04, 6.0], [0.02, 1.20, 4.0],
                  [1e-4, 1e-4, 1.0]], float)
    b = cv2.warpPerspective(a, H, (size+40, size+40))
    return a, b


def rigid_points(seed, n=80, outn=14):
    r = np.random.RandomState(seed)
    A = r.uniform(0, 120, (n, 2)).astype(float)
    ang = float(r.choice([-40, -30, 15, 30, 45]))
    a = np.deg2rad(ang)
    R = np.array([[np.cos(a), -np.sin(a)], [np.sin(a), np.cos(a)]])
    t = np.array([40., -10.])
    B = R.dot(A.T).T+t+r.uniform(-0.2, 0.2, (n, 2))
    A = np.vstack([A, r.uniform(0, 120, (outn, 2))])
    B = np.vstack([B, r.uniform(120, 280, (outn, 2))])
    return A, B


def seeded_grid(r):
    grid = []
    for row in range(9):
        grid.append(''.join(str(int(r.randint(1, 9))) for _ in range(9)))
    return grid


def code_value_for_code(Xv, U, Q):
    return (U*(U-1)//2)*Xv + Q


def default_shapes():
    return [
        {'t': 'rect', 'x': 10, 'y': 20, 'w': 60, 'h': 30},
        {'t': 'circ', 'cx': 180, 'cy': 40, 'r': 18},
        {'t': 'line', 'x1': 40, 'y1': 90, 'x2': 210, 'y2': 130},
        {'t': 'poly', 'pts': [(300, 30), (340, 80), (300, 120), (300, 30)]},
    ]


def build(out, seed, label):
    r = np.random.RandomState(seed)
    os.makedirs(out, exist_ok=True)

    grid = seeded_grid(r)
    grid_image(grid).save(os.path.join(out, 'grid.png'))

    secret = r.choice(SECRETS)
    sentence = "record of the day: the active code is %s for the main hall." % secret
    member_image(sentence).save(os.path.join(out, 'member.png'))

    Xv = int(r.choice([2, 4, 5, 7]))
    U = int(r.choice([7, 8, 9]))
    Q = int(r.choice([3, 5, 7, 9]))
    code_text = ("def compute(n):\n"
                 "  acc = 0\n"
                 "  for k in range(1, %d):\n"
                 "    acc = acc + k\n"
                 "  off = %d\n"
                 "  acc = acc*n\n"
                 "  return acc + off") % (U, Q)
    code_image(code_text).save(os.path.join(out, 'code.png'))
    code_value = code_value_for_code(Xv, U, Q)

    phrase = r.choice(PHRASES)
    shapes = default_shapes()
    if seed % 3 == 0:
        # degenerate geometric primitive: zero-area rectangle
        shapes.append({'t': 'rect', 'x': 55, 'y': 55, 'w': 0, 'h': 0})
    open(os.path.join(out, 'toolpath.txt'), 'w').write(make_tooltext(shapes, phrase))

    # features
    lpts = line_points(seed, 92, 16)
    np.savetxt(os.path.join(out, 'lin.csv'), lpts, delimiter=',')
    _model, line_inliers = fit.line_truth(lpts)

    a, b = homography_pair(seed)
    Image.fromarray(a).save(os.path.join(out, 'box1.png'))
    Image.fromarray(b).save(os.path.join(out, 'box2.png'))
    plane_inliers, _ = fit.plane_truth(a, b)

    A, B = rigid_points(seed)
    np.savetxt(os.path.join(out, 'rig_a.csv'), A, delimiter=',')
    np.savetxt(os.path.join(out, 'rig_b.csv'), B, delimiter=',')
    _rt, rigid_inliers = fit.rigid_truth(A, B)

    render_a = "summer field grid horizon"
    render_b = "open delta pass registry"
    general = {"x": Xv, "object": "compute",
               "render_a": render_a, "render_b": render_b}
    json.dump(general, open(os.path.join(out, 'general.json'), 'w'), indent=2)

    expected = {
        "label": label,
        "grid": grid,
        "member_secret": secret,
        "code_value": code_value,
        "render_a": render_a,
        "render_b": render_b,
        "print_word": phrase,
        "shapes": shapes,
        "line_inliers": int(line_inliers),
        "plane_inliers": int(plane_inliers),
        "rigid_inliers": int(rigid_inliers),
        "x": int(Xv),
    }
    json.dump(expected, open(os.path.join(out, 'expected.json'), 'w'), indent=2)
    print("wrote", out, "label", label,
          "line_in", line_inliers, "plane_in", plane_inliers,
          "rigid_in", rigid_inliers)


if __name__ == "__main__":
    build(sys.argv[1], int(sys.argv[2]), sys.argv[3])