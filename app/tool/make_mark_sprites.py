"""Builds the activity sprites in assets/whale/ from the brand masters.

Run from app/:

    python3 tool/make_mark_sprites.py

The sheets are white + alpha masks that the app tints at run time. Level 1 is the
still marker; levels 2-4 sweep a soft highlight across it, with the band narrowing
and the low end deepening as the level rises. Frame size, column count and level
timing match the widget's expectations (lib/ui/chat/widgets/whale_tail.dart).
Pure Python, no dependencies.
"""
import json
import math
import os
import struct
import zlib

import make_launcher_icons as icons

OUT = os.path.join(icons.APP, 'assets', 'whale')
FRAME_W, FRAME_H = 120, 96
COLUMNS = 6
MARGIN = 8

# The masters' ink box: the monogram and its accent dot in the 108 grid.
INK_CENTRE = (54.0, 54.0)
INK_HEIGHT = 52.0

# level, frames, frameMs, alpha outside the band, band width (px)
LEVELS = ((1, 1, 0, 1.0, 0.0),
          (2, 24, 30, 0.55, 22.0),
          (3, 24, 20, 0.45, 18.0),
          (4, 36, 20, 0.35, 12.0))


def mask(masters):
    """Coverage of the marker (monogram + accent dot) at frame resolution."""
    w, h = FRAME_W * icons.SS, FRAME_H * icons.SS
    s = (FRAME_H - 2 * MARGIN) / INK_HEIGHT
    cx, cy = INK_CENTRE

    def to_dev(x, y):
        return ((FRAME_W / 2 + (x - cx) * s) * icons.SS,
                (FRAME_H / 2 + (y - cy) * s) * icons.SS)

    def to_grid(x, y):
        return ((x / icons.SS - FRAME_W / 2) / s + cx,
                (y / icons.SS - FRAME_H / 2) / s + cy)

    canvas = bytearray(w * h * 4)
    polys = masters.polys[0] + masters.polys[3]
    icons.fill(canvas, w, h, polys, lambda x, y: (255, 255, 255, 255), to_dev, to_grid)

    out = []
    n = icons.SS * icons.SS * 255.0
    for y in range(FRAME_H):
        row = []
        for x in range(FRAME_W):
            a = 0
            for dy in range(icons.SS):
                base = ((y * icons.SS + dy) * w + x * icons.SS) * 4 + 3
                for dx in range(icons.SS):
                    a += canvas[base + dx * 4]
            row.append(a / n)
        out.append(row)
    return out


def sweep(base, phase, floor, half):
    """The mask dimmed everywhere except a soft band travelling across it."""
    span = FRAME_W + 4 * half
    centre = -2 * half + phase * span
    out = []
    for row in base:
        out.append([a * (floor + (1.0 - floor) * math.exp(-(((x - centre) / half) ** 2)))
                    for x, a in enumerate(row)])
    return out


def png(w, h, rows):
    raw = b''.join(b'\x00' + bytes(r) for r in rows)

    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data
                + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff))

    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9))
            + chunk(b'IEND', b''))


def sheet(base, level, frames, floor, half):
    rows = (frames + COLUMNS - 1) // COLUMNS
    w, h = FRAME_W * COLUMNS, FRAME_H * rows
    out = [bytearray(w * 4) for _ in range(h)]
    for i in range(frames):
        alpha = base if level == 1 else sweep(base, i / frames, floor, half)
        ox, oy = (i % COLUMNS) * FRAME_W, (i // COLUMNS) * FRAME_H
        for y in range(FRAME_H):
            row, src = out[oy + y], alpha[y]
            for x in range(FRAME_W):
                a = round(src[x] * 255)
                if a:
                    o = (ox + x) * 4
                    row[o:o + 4] = bytes((255, 255, 255, a))
    return png(w, h, out)


def main():
    base = mask(icons.Masters())
    levels = []
    for level, frames, frame_ms, floor, half in LEVELS:
        name = f'whale_{level}.png'
        with open(os.path.join(OUT, name), 'wb') as fh:
            fh.write(sheet(base, level, frames, floor, half))
        levels.append({'level': level, 'image': name, 'frames': frames, 'frameMs': frame_ms})
        print(f'wrote {name}: {frames} frames')
    manifest = {'frameWidth': FRAME_W, 'frameHeight': FRAME_H, 'columns': COLUMNS, 'levels': levels}
    with open(os.path.join(OUT, 'whale.json'), 'w', encoding='utf-8', newline='\n') as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2)
        fh.write('\n')
    print('wrote whale.json')


if __name__ == '__main__':
    main()