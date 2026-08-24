import os
import re

POV2 = '/app/pov2'


def read_scene(path):
    spheres = []
    bg = (0.05, 0.05, 0.10)
    w = h = None
    with open(path) as f:
        for line in f:
            tok = line.split()
            if not tok:
                continue
            if tok[0] == 'size' and len(tok) == 3:
                w, h = int(tok[1]), int(tok[2])
            elif tok[0] == 'background' and len(tok) == 4:
                bg = (float(tok[1]), float(tok[2]), float(tok[3]))
            elif tok[0] == 'sphere' and len(tok) == 8:
                spheres.append((float(tok[1]), float(tok[2]), float(tok[4]),
                                (float(tok[5]), float(tok[6]), float(tok[7]))))
    return w or 48, h or 36, bg, spheres


def read_ppm(path):
    with open(path, 'rb') as f:
        data = f.read()
    m = re.match(br'P6\s+(\d+)\s+(\d+)\s+255\s', data)
    if not m:
        raise ValueError('not a binary P6 PPM')
    w, h = int(m.group(1)), int(m.group(2))
    body = data[m.end():]
    if len(body) != w * h * 3:
        raise ValueError('bad body length')
    return w, h, body


def main():
    try:
        w, h, bg, spheres = read_scene(os.path.join(POV2, 'scene.pov'))
    except OSError:
        write_reward(0.0)
        return

    exp = bytearray()
    for y in range(h):
        v = 1.0 - 2.0 * float(y) / float(h - 1)
        for x in range(w):
            u = 2.0 * float(x) / float(w - 1) - 1.0
            c = bg
            for (sx, sy, rad, col) in spheres:
                du = u - sx
                dv = v - sy
                if du * du + dv * dv <= rad * rad:
                    c = col
            exp += bytes((int(c[0] * 255 + 0.5),
                          int(c[1] * 255 + 0.5),
                          int(c[2] * 255 + 0.5)))
    exp = bytes(exp)

    try:
        gw, gh, got = read_ppm(os.path.join(POV2, 'out.ppm'))
    except (OSError, ValueError):
        write_reward(0.0)
        return

    if (gw, gh) != (w, h):
        write_reward(0.0)
        return

    bad = sum(1 for i in range(len(exp)) if exp[i] != got[i])
    total = len(exp)
    if bad == 0:
        write_reward(1.0)
    else:
        write_reward(round((total - bad) / total, 4))


def write_reward(v):
    with open('/logs/verifier/reward.txt', 'w') as f:
        f.write(str(v))


if __name__ == '__main__':
    main()