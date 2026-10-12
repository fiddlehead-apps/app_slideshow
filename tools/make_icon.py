"""Erzeugt das App-Icon (1024 px) neu: python3 tools/make_icon.py

Gleiches Motiv wie die Web-App (webapp_slideshow/tools/make_icons.py):
zwei schräg liegende Fotoabzüge auf Blau. Braucht Pillow.
"""
import math
import os

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   'Slideshow', 'Assets.xcassets', 'AppIcon.appiconset', 'icon-1024.png')
SS = 4

BLUE = '#2446D8'
BACK = '#7E93F2'
CARD = '#FFFFFF'
PHOTO = '#16181D'
HILL = '#8BA3FF'
SUN = '#FFC857'

BACK_CARD = ((272, 276), (330, 244), 9)
FRONT_CARD = ((246, 248), (330, 244), -6)
PHOTO_INSET = 22
SUN_AT, SUN_R = (82, -46), 20
HILLS = [(-143, 100), (-63, 6), (-7, 66), (35, 28), (143, 100)]


def rot(points, center, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    cx, cy = center
    return [(cx + x * c - y * s, cy + x * s + y * c) for x, y in points]


def rrect(w, h, r, steps=10):
    pts = []
    for qx, qy, start in ((w / 2 - r, -h / 2 + r, -90), (w / 2 - r, h / 2 - r, 0),
                          (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180)):
        for i in range(steps + 1):
            a = math.radians(start + 90 * i / steps)
            pts.append((qx + r * math.cos(a), qy + r * math.sin(a)))
    return pts


def circle(cx, cy, r, steps=48):
    return [(cx + r * math.cos(2 * math.pi * i / steps), cy + r * math.sin(2 * math.pi * i / steps)) for i in range(steps)]


def scene(size):
    k = size / 512.0
    place = lambda pts: [(x * k, y * k) for x, y in pts]
    (bc, (bw, bh), bd) = BACK_CARD
    (fc, (fw, fh), fd) = FRONT_CARD
    pw, ph = fw - 2 * PHOTO_INSET, fh - 2 * PHOTO_INSET
    return [
        (BACK, place(rot(rrect(bw, bh, 18), bc, bd))),
        (CARD, place(rot(rrect(fw, fh, 18), fc, fd))),
        (PHOTO, place(rot(rrect(pw, ph, 5), fc, fd))),
        (SUN, place(rot(circle(SUN_AT[0], SUN_AT[1], SUN_R), fc, fd))),
        (HILL, place(rot(HILLS, fc, fd))),
    ]


if __name__ == '__main__':
    size = 1024
    big = size * SS
    im = Image.new('RGB', (big, big), BLUE)  # iOS rundet selbst ab, kein Alpha erlaubt
    d = ImageDraw.Draw(im)
    for color, pts in scene(big):
        d.polygon(pts, fill=color)
    im.resize((size, size), Image.LANCZOS).save(OUT, optimize=True)
    print('Icon geschrieben nach', OUT)
