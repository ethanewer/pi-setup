"""Build-time generator for the item-025 inbox set (deterministic).

Produces /app/inbox with 8 mixed-format documents. Run once at image-build,
then removed (not shipped in the container).
"""
import glob
import io
import os

import pymupdf
from PIL import Image, ImageDraw, ImageFont

INBOX = '/app/inbox'


def find_font():
    for c in ('/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf',
              '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
              '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf'):
        if os.path.exists(c):
            return c
    for pat in ('/usr/share/fonts/**/*.ttf', '/usr/share/fonts/**/*.otf'):
        hits = glob.glob(pat, recursive=True)
        if hits:
            return hits[0]
    raise RuntimeError('no ttf font found')


def lines(label, ref):
    return [(label, 62), ('Reference: %s' % ref, 36), ('Amount: $%d' % (len(ref) * 137), 36)]


def draw(lines, size, base):
    img = Image.new('RGB', size, 'white')
    d = ImageDraw.Draw(img)
    d.fontmode = 'L'
    y = 70
    for text, fs in lines:
        d.text((50, y), text, fill='black', font=ImageFont.truetype(find_font(), fs))
        y += fs + 40
    return img


def make_png(label, ref, out):
    img = draw(lines(label, ref), (1200, 700), 42)
    img.save(out, 'PNG')


def make_text_pdf(label, ref, out):
    doc = pymupdf.open()
    page = doc.new_page(width=560, height=500)
    y = 80
    for text, fs in lines(label, ref):
        page.insert_text((60, y), text, fontsize=14, fontname='helv')
        y += fs + 14
    doc.save(out)
    doc.close()


def make_raster_pdf(label, ref, out):
    img = draw(lines(label, ref), (580, 520), 34)
    buf = io.BytesIO()
    img.save(buf, format='PNG')
    doc = pymupdf.open()
    page = doc.new_page(width=580, height=520)
    page.insert_image(pymupdf.Rect(20, 20, 560, 500), stream=buf.getvalue())
    doc.save(out)
    doc.close()


def main():
    os.makedirs(INBOX, exist_ok=True)
    for f in os.listdir(INBOX):
        os.remove(os.path.join(INBOX, f))
    make_text_pdf('INVOICE', 'INV-1001', INBOX + '/doc-01.pdf')
    make_text_pdf('RECEIPT', 'RCP-2002', INBOX + '/doc-02.pdf')
    make_png('INVOICE', 'INV-3345', INBOX + '/doc-03.png')
    make_png('RECEIPT', 'RCP-1431', INBOX + '/doc-04.png')
    make_raster_pdf('INVOICE', 'INV-5011', INBOX + '/doc-05.pdf')
    make_raster_pdf('RECEIPT', 'RCP-8910', INBOX + '/doc-06.pdf')
    make_png('RECEIPT', 'RCP-3322', INBOX + '/doc-07.png')
    with open(INBOX + '/doc-08.bin', 'wb') as f:
        f.write(bytes(range(256)) * 4 + b'\x00' * 64 + b'\xff' * 64)


if __name__ == '__main__':
    main()
    print('generated:', sorted(os.listdir(INBOX)))