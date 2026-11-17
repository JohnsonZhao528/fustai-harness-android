#!/usr/bin/env python3
"""Renders the Android launcher icons and their vector layers from the brand masters.

Run from app/:

    python3 tool/make_launcher_icons.py

For every density this writes the legacy, round and adaptive-foreground layers of the
default, 霜白 (frost), 墨 (ink) and 夜幕 (night) icons under
android/app/src/main/res/mipmap-*/, and rewrites the two vector layers the themed and
status-bar icons use. Geometry and colours come from assets/brand/*.svg alone: change the
masters and rerun, never the generated files. Pure Python, no dependencies.
"""
import math
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_brand_mark as mark  # noqa: E402

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(APP, 'android', 'app', 'src', 'main', 'res')

SS = 4  # supersampling factor
DENSITIES = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0}
LEGACY_DP, ADAPTIVE_DP = 48, 108

# suffix: (gradient start, gradient end, glyph variant)
THEMES = {
    '': ('#5E82E4', '#1E3884', 'dark'),
    '_frost': ('#FCFDFF', '#DDE5F8', 'light'),
    '_ink': ('#292B30', '#0D0E11', 'dark'),
    '_night': ('#2C3D6C', '#0C122D', 'dark'),
}


def rgb(hexc):
    return tuple(int(hexc[i:i + 2], 16) for i in (1, 3, 5))


def sampler(g):
    """Returns f(x, y) -> (r, g, b, 255) for a parsed gradient in grid space."""
    stops = g['stops']
    cols = [rgb(c) for _, c in stops]
    offs = [o for o, _ in stops]

    def at(t):
        t = 0.0 if t < 0 else (1.0 if t > 1 else t)
        i = 0
        while i < len(offs) - 2 and t > offs[i + 1]:
            i += 1
        span = offs[i + 1] - offs[i]
        k = 0.0 if span <= 0 else (t - offs[i]) / span
        a, b = cols[i], cols[i + 1]
        return (round(a[0] + (b[0] - a[0]) * k), round(a[1] + (b[1] - a[1]) * k),
                round(a[2] + (b[2] - a[2]) * k), 255)

    if g['kind'] == 'linear':
        (x1, y1), (x2, y2) = g['p1'], g['p2']
        dx, dy = x2 - x1, y2 - y1
        inv = 1.0 / (dx * dx + dy * dy)
        return lambda x, y: at(((x - x1) * dx + (y - y1) * dy) * inv)

    cx, cy = g['c']
    r = g['r']
    return lambda x, y: at(math.hypot(x - cx, y - cy) / r)


def diagonal(a, b):
    """The icon's diagonal gradient, in the same coordinates as the tile master."""
    return dict(kind='linear', p1=(7.57, -5.87), p2=(100.43, 113.87),
                stops=[(0.0, a), (1.0, b)])


def fill(canvas, w, h, polys, sample, to_dev, to_grid):
    edges = []
    for poly in polys:
        pts = [to_dev(x, y) for x, y in poly]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]):
            if y0 != y1:
                edges.append((x0, y0, x1, y1))
    rows = {}
    for e in edges:
        ylo, yhi = (e[1], e[3]) if e[1] < e[3] else (e[3], e[1])
        for py in range(max(0, int(ylo)), min(h, int(math.ceil(yhi)))):
            rows.setdefault(py, []).append(e)
    for py, es in rows.items():
        y = py + 0.5
        xs = sorted(x0 + (y - y0) * (x1 - x0) / (y1 - y0) for x0, y0, x1, y1 in es
                    if min(y0, y1) <= y < max(y0, y1))
        for i in range(0, len(xs) - 1, 2):
            for px in range(max(0, int(xs[i] + 0.4999)), min(w, int(xs[i + 1] + 0.4999))):
                r, g, b, a = sample(*to_grid(px + 0.5, py + 0.5))
                o = (py * w + px) * 4
                if a == 255:
                    canvas[o:o + 4] = bytes((r, g, b, 255))
                elif a:
                    da = canvas[o + 3]
                    k = da / 255.0 * (1 - a / 255.0)
                    oa = a / 255.0 + k
                    canvas[o] = round((r * a / 255.0 + canvas[o] * k) / oa)
                    canvas[o + 1] = round((g * a / 255.0 + canvas[o + 1] * k) / oa)
                    canvas[o + 2] = round((b * a / 255.0 + canvas[o + 2] * k) / oa)
                    canvas[o + 3] = round(oa * 255)


def downsample(canvas, w, size):
    out = bytearray(size * size * 4)
    for y in range(size):
        for x in range(size):
            sr = sg = sb = sa = 0
            for dy in range(SS):
                base = ((y * SS + dy) * w + x * SS) * 4
                for dx in range(SS):
                    o = base + dx * 4
                    a = canvas[o + 3]
                    sr += canvas[o] * a
                    sg += canvas[o + 1] * a
                    sb += canvas[o + 2] * a
                    sa += a
            if sa:
                o = (y * size + x) * 4
                out[o] = round(sr / sa)
                out[o + 1] = round(sg / sa)
                out[o + 2] = round(sb / sa)
                out[o + 3] = round(sa / (SS * SS))
    return out


def png(size, rgba):
    raw = b''.join(b'\x00' + bytes(rgba[y * size * 4:(y + 1) * size * 4]) for y in range(size))

    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data
                + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff))

    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9))
            + chunk(b'IEND', b''))


class Masters:
    """Paths and gradients of the brand masters, flattened once for rasterising."""

    def __init__(self):
        light, dark, tile = (mark.read(n) for n in
                             ('glyph-light.svg', 'glyph-dark.svg', 'tile.svg'))
        p = mark.paths(light)
        self.polys = [mark.flatten(p[key], 24) for key in
                      ('body', 'fin-layer', 'belly-layer', 'bubble-layer')]
        self.subs = {k: p[k] for k in ('body', 'bubble-layer')}
        self.light = [sampler(mark.gradients(light)[k]) for k in
                      ('tail', 'fin', 'belly', 'bubble')]
        self.dark = [sampler(mark.gradients(dark)[k]) for k in
                     ('tail', 'fin', 'belly', 'bubble')]
        self.tile = mark.flatten(mark.paths(tile)['tile'], 24)


def circle(cx, cy, r, steps=360):
    return [(cx + r * math.cos(2 * math.pi * i / steps),
             cy + r * math.sin(2 * math.pi * i / steps)) for i in range(steps)]


def render(size, masters, bg, glyphs, square):
    """One icon: `bg` gradient (or None) inside `square`, then the glyph layers."""
    w = size * SS
    canvas = bytearray(w * w * 4)
    k = SS * size / 72.0
    to_dev = lambda x, y: ((x - 18) * k, (y - 18) * k)
    to_grid = lambda x, y: (x / k + 18, y / k + 18)
    if bg:
        shape = masters.tile if square else [circle(54, 54, 36)]
        fill(canvas, w, w, shape, sampler(bg), to_dev, to_grid)
    for polys, sample in zip(masters.polys, glyphs):
        fill(canvas, w, w, polys, sample, to_dev, to_grid)
    return png(size, downsample(canvas, w, size))


def render_foreground(size, masters, glyphs):
    w = size * SS
    canvas = bytearray(w * w * 4)
    k = SS * size / 108.0
    to_dev = lambda x, y: (x * k, y * k)
    to_grid = lambda x, y: (x / k, y / k)
    for polys, sample in zip(masters.polys, glyphs):
        fill(canvas, w, w, polys, sample, to_dev, to_grid)
    return png(size, downsample(canvas, w, size))


def num(v):
    s = f'{v:.2f}'.rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def android_path(subs, tx=0.0, ty=0.0, s=1.0):
    parts = []
    for start, segs in subs:
        parts.append(f'M{num(start[0] * s + tx)},{num(start[1] * s + ty)}')
        for (a, b), (c, d), (e, g) in segs:
            parts.append(f'C{num(a * s + tx)},{num(b * s + ty)} {num(c * s + tx)},{num(d * s + ty)} '
                         f'{num(e * s + tx)},{num(g * s + ty)}')
        parts.append('Z')
    return ''.join(parts)


def write(name, data):
    path = os.path.join(RES, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if isinstance(data, bytes):
        open(path, 'wb').write(data)
    else:
        open(path, 'w', encoding='utf-8', newline='\n').write(data)


MONO = '''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/make_launcher_icons.py from assets/brand/*.svg; do not edit.
     Themed-icon (Android 13+) layer: the marker's silhouette, same placement as
     mipmap/ic_launcher_foreground. The monogram as one shape, the accent dot as its own. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
%s</vector>
'''

STAT = '''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/make_launcher_icons.py from assets/brand/*.svg; do not edit.
     Status-bar icon for notifications: the marker's silhouette (ic_launcher_monochrome),
     cropped to fill the 22dp live area of the 24dp slot. Small icons are drawn from alpha
     only. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
%s</vector>
'''

PATH = ('    <path\n        android:fillColor="#FFFFFFFF"\n        android:pathData="%s" />\n')


def main():
    masters = Masters()
    for density, scale in DENSITIES.items():
        folder = f'mipmap-{density}'
        legacy = round(LEGACY_DP * scale)
        adaptive = round(ADAPTIVE_DP * scale)
        for suffix, (start, end, glyph) in THEMES.items():
            glyphs = masters.dark if glyph == 'dark' else masters.light
            bg = diagonal(start, end)
            for name, square in ((f'ic_launcher{suffix}.png', True),
                                 (f'ic_launcher{suffix}_round.png', False)):
                write(f'{folder}/{name}', render(legacy, masters, bg, glyphs, square))
            write(f'{folder}/ic_launcher{suffix}_foreground.png',
                  render_foreground(adaptive, masters, glyphs))

    write('drawable/ic_launcher_monochrome.xml',
          MONO % ''.join(PATH % android_path(masters.subs[k]) for k in ('body', 'bubble-layer')))

    box = mark.flatten(masters.subs['body'], 24) + mark.flatten(masters.subs['bubble-layer'], 24)
    xs = [x for poly in box for x, _ in poly]
    ys = [y for poly in box for _, y in poly]
    s = 22.0 / (max(ys) - min(ys))
    tx = (24 - (max(xs) - min(xs)) * s) / 2 - min(xs) * s
    ty = 1.0 - min(ys) * s
    write('drawable/ic_stat_dsh.xml',
          STAT % ''.join(PATH % android_path(masters.subs[k], tx, ty, s)
                         for k in ('body', 'bubble-layer')))
    print('wrote launcher icons and vector layers')


if __name__ == '__main__':
    main()