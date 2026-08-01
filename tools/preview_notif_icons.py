#!/usr/bin/env python3
"""Renders the status-bar notification icons at the size they're actually seen.

    python3 tools/preview_notif_icons.py     # -> build/notif-icons/shipped.png

A small icon is about 4mm on screen and path data tells you nothing about how
it reads there: both icons were wrong the first time in ways invisible in the
XML and obvious at 18px (Arunoday drawn at a third of its own canvas height,
Nivaat's stroked feathers reading as a trident). Render before shipping.

It PARSES the two ic_notification.xml files rather than mirroring them here,
so it can't show a stale shape, and it refuses rather than guesses: any path
command outside MmLlHhVvAaZz, or a drawable that comes out empty, is an error.
Numpy only, like make_icons.py — supersample the 24-unit viewport, then box-
downsample. See CLAUDE.md's notification-icon note for why these exist.
"""

import re
import struct
import zlib
from pathlib import Path

import numpy as np

VIEW, SS = 24.0, 24          # viewport units, supersample factor
N = int(VIEW * SS)
_ys, _xs = np.mgrid[0:N, 0:N]
PX, PY = (_xs + 0.5) / SS, (_ys + 0.5) / SS

ROOT = Path(__file__).resolve().parent.parent
DRAWABLE = "android/app/src/main/res/drawable/ic_notification.xml"
ICONS = {app: ROOT / "apps" / app / DRAWABLE for app in ("arunoday", "nivaat")}

# Letters are captured broadly, NOT just the supported ones: a dropped "C"
# would leave its numbers to be eaten as the previous command's coordinates,
# i.e. a wrong shape drawn confidently.
_TOKEN = re.compile(r"[A-Za-z]|-?\d*\.?\d+(?:[eE][-+]?\d+)?")
_SUPPORTED = "MmLlHhVvAaZz"


def _arc_points(p0, rx, ry, phi_deg, large, sweep, p1, steps=96):
    """SVG elliptical arc, endpoint -> centre parameterisation (F.6.5)."""
    (x1, y1), (x2, y2) = p0, p1
    if (x1, y1) == (x2, y2):
        return []          # F.6.2: identical endpoints omit the arc
    if rx == 0 or ry == 0:
        return [p1]        # F.6.2: zero radius is a straight line
    phi = np.radians(phi_deg)
    cosp, sinp = np.cos(phi), np.sin(phi)
    dx2, dy2 = (x1 - x2) / 2, (y1 - y2) / 2
    x1p, y1p = cosp * dx2 + sinp * dy2, -sinp * dx2 + cosp * dy2
    rx, ry = abs(rx), abs(ry)
    lam = (x1p / rx) ** 2 + (y1p / ry) ** 2
    if lam > 1:                                   # F.6.6: radii too small
        rx, ry = rx * np.sqrt(lam), ry * np.sqrt(lam)
    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    if den == 0:
        # Reachable despite the equality check above: den SQUARES x1p/y1p, and
        # a square underflows to zero long before the value does (endpoints
        # 1e-300 apart get here). Without this it returns an arc of nan.
        return [p1]
    coef = (-1 if large == sweep else 1) * np.sqrt(max(num, 0) / den)
    cxp, cyp = coef * rx * y1p / ry, -coef * ry * x1p / rx
    cx = cosp * cxp - sinp * cyp + (x1 + x2) / 2
    cy = sinp * cxp + cosp * cyp + (y1 + y2) / 2
    t1 = np.arctan2((y1p - cyp) / ry, (x1p - cxp) / rx)
    dt = np.arctan2((-y1p - cyp) / ry, (-x1p - cxp) / rx) - t1
    if not sweep and dt > 0:
        dt -= 2 * np.pi
    elif sweep and dt < 0:
        dt += 2 * np.pi
    ts = t1 + dt * np.linspace(0, 1, steps)
    return [(cx + rx * np.cos(t) * cosp - ry * np.sin(t) * sinp,
             cy + rx * np.cos(t) * sinp + ry * np.sin(t) * cosp) for t in ts[1:]]


def parse_path(d):
    """pathData -> list of closed subpaths (point lists). Arcs flattened."""
    toks = _TOKEN.findall(d)
    i, cmd = 0, None
    cur = start = (0.0, 0.0)
    subs, sub = [], []

    def num():
        nonlocal i
        i += 1
        return float(toks[i - 1])

    while i < len(toks):
        if toks[i].isalpha():
            if toks[i] not in _SUPPORTED:
                raise ValueError(f"unsupported path command {toks[i]!r}; this "
                                 f"parser covers {_SUPPORTED} only — refuse "
                                 f"rather than draw the wrong shape quietly")
            cmd, i = toks[i], i + 1
        if cmd is None:
            raise ValueError("pathData does not start with a command")
        rel, c = cmd.islower(), cmd.upper()
        if c == "Z":
            if sub:
                subs.append(sub)
            sub, cur = [], start
            continue
        if c == "M":
            x, y = num(), num()
            cur = (cur[0] + x, cur[1] + y) if rel else (x, y)
            if sub:
                subs.append(sub)
            # A relative `m` mid-path continues the same shape (the circle
            # idiom `M cx,cy m-r,0 a...`), so only the pen moves.
            sub, start = [cur], cur
            cmd = "l" if rel else "L"
            continue
        if c == "L":
            x, y = num(), num()
            cur = (cur[0] + x, cur[1] + y) if rel else (x, y)
        elif c == "H":
            x = num()
            cur = (cur[0] + x, cur[1]) if rel else (x, cur[1])
        elif c == "V":
            y = num()
            cur = (cur[0], cur[1] + y) if rel else (cur[0], y)
        elif c == "A":
            rx, ry, rot_, la, sw = num(), num(), num(), num(), num()
            x, y = num(), num()
            end = (cur[0] + x, cur[1] + y) if rel else (x, y)
            sub.extend(_arc_points(cur, rx, ry, rot_, int(la), int(sw), end))
            cur = end
            continue
        sub.append(cur)
    if sub:
        subs.append(sub)
    return [s for s in subs if len(s) >= 3]


def load_drawable(path):
    """Union of every pathData in the file, non-zero winding (M3 default)."""
    xml = re.sub(r"<!--.*?-->", "", path.read_text(), flags=re.S)
    datas = re.findall(r'android:pathData="([^"]+)"', xml)
    if not datas:
        raise SystemExit(f"no pathData in {path}")
    wind = np.zeros_like(PX)
    for d in datas:
        try:
            subs = parse_path(d)
        except ValueError as e:
            raise SystemExit(f"{path}:\n  {e}")
        for sub in subs:
            pts = sub + [sub[0]]
            for (ax, ay), (bx, by) in zip(pts, pts[1:]):
                if ay == by:
                    continue
                hit = ((ay <= PY) & (by > PY)) | ((by <= PY) & (ay > PY))
                t = np.where(hit, (PY - ay) / (by - ay), 0.0)
                wind += np.where(hit & (PX < ax + t * (bx - ax)),
                                 1.0 if by > ay else -1.0, 0.0)
    mask = wind != 0
    if not mask.any():
        raise SystemExit(f"{path}:\n  parsed to an empty shape")
    return mask


def write_png(path, img):
    data = (np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)
    h, w, _ = data.shape
    raw = b"".join(b"\x00" + data[i].tobytes() for i in range(h))

    def chunk(tag, payload):
        body = tag + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(
            ">I", zlib.crc32(body) & 0xFFFFFFFF)

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 9))
                     + chunk(b"IEND", b""))


def main():
    """One row per icon: 18px, 24px, 72px (true 3x pixels), 24px zoomed."""
    cell, pad = 108, 10
    sheet = np.zeros((len(ICONS) * (cell + pad) + pad,
                      4 * (cell + pad) + pad, 3)) + 0.043
    for r, (name, path) in enumerate(ICONS.items()):
        mask = load_drawable(path)
        for c, px, up in ((0, 18, 6), (1, 24, 4), (2, 72, 1), (3, 24, 4)):
            block = N // px
            small = mask[:block * px, :block * px].astype(float).reshape(
                px, block, px, block).mean(axis=(1, 3))
            tile = np.repeat(np.repeat(small, up, 0), up, 1)
            y0, x0 = pad + r * (cell + pad), pad + c * (cell + pad)
            h, w = tile.shape
            oy, ox = y0 + (cell - h) // 2, x0 + (cell - w) // 2
            for ch in range(3):
                sheet[oy:oy + h, ox:ox + w, ch] = np.maximum(
                    sheet[oy:oy + h, ox:ox + w, ch], tile)
        print(f"  {name:9s} fills {mask.any(axis=0).sum() / N * 100:4.1f}% width,"
              f" {mask.any(axis=1).sum() / N * 100:4.1f}% height")
    out = ROOT / "build" / "notif-icons" / "shipped.png"
    write_png(out, sheet)
    print(f"\nwrote {out}")


if __name__ == "__main__":
    main()
