#!/usr/bin/env python3
"""Generates the app-icon candidates in branding/icons/ (numpy, no other deps).

Same philosophy as make_sounds.py: brand assets are synthesized in-repo so
they match the palette exactly (AppPalette.dawn / AppPalette.wind from
packages/core/lib/src/theme.dart), carry no licence baggage, and can be
regenerated or tweaked forever.

Rendering: signed-distance fields on a 2x supersampled grid, box-downsampled
to 1024x1024 — crisp anti-aliased geometry, no raster libraries. Every icon
is full-bleed square (the OS applies its own mask); motifs sit inside the
central ~62% so Android's adaptive-icon crop (66/108 safe zone) never clips
them. A *-preview.png per app shows the same candidates under an
Apple-style squircle mask on a dark launcher background.

Run from the repo root:  python3 tools/make_icons.py
    --apply also writes the real launcher assets into both apps (Android
    adaptive mipmaps for MainActivity + the two icon aliases, iOS
    AppIcon/AppIconTwo/AppIconThree single-size appiconsets, and the 256px
    in-app picker thumbnails under assets/icons/). Final resizes go through
    macOS `sips` for quality.
"""

import json
import struct
import subprocess
import sys
import zlib
from pathlib import Path

import numpy as np

SIZE = 1024
SS = 2  # supersample factor
R = SIZE * SS  # render-grid side
AA = 1.6 * SS  # anti-alias ramp in render pixels

OUT = Path(__file__).resolve().parent.parent / "branding" / "icons"

# AppPalette (theme.dart) — keep in sync.
DAWN = "#FFB067"
WIND = "#6FB7EC"


def hex_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)])


def grid():
    """Pixel-centre coordinates in 1024-space, at render resolution."""
    c = (np.arange(R) + 0.5) / SS
    x, y = np.meshgrid(c, c)
    return x, y


X, Y = grid()


class Canvas:
    def __init__(self, top="#111111", bottom="#040404"):
        """Near-black vertical gradient — pure #000 reads as a hole in a
        launcher grid; a whisper of depth reads premium."""
        t = (Y / SIZE)[..., None]
        self.img = hex_rgb(top) * (1 - t) + hex_rgb(bottom) * t

    def paint(self, alpha, color, opacity=1.0):
        """Compose an anti-aliased coverage mask (or per-pixel color array)."""
        a = np.clip(alpha, 0, 1)[..., None] * opacity
        self.img = self.img * (1 - a) + color * a

    def glow(self, cx, cy, sigma, color, opacity):
        """Soft gaussian light — the only non-geometry ingredient."""
        d2 = (X - cx) ** 2 + (Y - cy) ** 2
        self.paint(np.exp(-d2 / (2 * sigma * sigma)), hex_rgb(color), opacity)

    def down(self):
        s = self.img.reshape(SIZE, SS, SIZE, SS, 3).mean(axis=(1, 3))
        return s


# ---- SDF coverage helpers (return 0..1 alpha masks) -------------------------

def _cov(signed_d):
    """Coverage from a signed distance (negative = inside)."""
    return np.clip(0.5 - signed_d * SS / AA, 0, 1)


def disc(cx, cy, r, cut_below=None):
    d = np.hypot(X - cx, Y - cy) - r
    if cut_below is not None:  # keep only y <= cut_below (flat-bottom sun)
        d = np.maximum(d, Y - cut_below)
    return _cov(d)


def ring(cx, cy, r, thickness):
    return _cov(np.abs(np.hypot(X - cx, Y - cy) - r) - thickness / 2)


def stroke(ax, ay, bx, by, thickness):
    """Segment with round caps."""
    abx, aby = bx - ax, by - ay
    t = np.clip(((X - ax) * abx + (Y - ay) * aby) / (abx * abx + aby * aby), 0, 1)
    d = np.hypot(X - (ax + abx * t), Y - (ay + aby * t)) - thickness / 2
    return _cov(d)


def convex(points):
    """Filled convex polygon, either winding (screen coords)."""
    # Signed area decides the winding so edge distances point outward.
    area = sum(
        ax * by - bx * ay
        for (ax, ay), (bx, by) in zip(points, points[1:] + points[:1])
    )
    flip = -1.0 if area < 0 else 1.0
    d = None
    n = len(points)
    for i in range(n):
        ax, ay = points[i]
        bx, by = points[(i + 1) % n]
        ex, ey = bx - ax, by - ay
        ln = np.hypot(ex, ey)
        e = flip * ((X - ax) * ey - (Y - ay) * ex) / ln
        d = e if d is None else np.maximum(d, e)
    return _cov(d)


def arc(cx, cy, r, deg0, deg1, thickness):
    """Circular arc stroke with round caps. Math angles (y up, CCW),
    degrees, range must not cross the ±180° seam."""
    t = np.degrees(np.arctan2(-(Y - cy), X - cx))
    tt = np.radians(np.clip(t, deg0, deg1))
    d = np.hypot(X - (cx + r * np.cos(tt)), Y - (cy - r * np.sin(tt)))
    return _cov(d - thickness / 2)


def vgrad(c_top, c_bot, y0, y1):
    """Per-pixel vertical color ramp for gradient fills."""
    t = np.clip((Y - y0) / (y1 - y0), 0, 1)[..., None]
    return hex_rgb(c_top) * (1 - t) + hex_rgb(c_bot) * t


def rot(points, cx, cy, deg):
    """Rotate (x, y) tuples around (cx, cy). Screen coords, y down."""
    a = np.radians(deg)
    c, s = np.cos(a), np.sin(a)
    return [
        (cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c)
        for x, y in points
    ]


# ---- PNG out ----------------------------------------------------------------

def write_png(path, img):
    data = (np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)
    h, w, _ = data.shape
    raw = b"".join(b"\x00" + data[i].tobytes() for i in range(h))

    def chunk(tag, payload):
        body = tag + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(
            ">I", zlib.crc32(body) & 0xFFFFFFFF
        )

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    print(f"  {path.relative_to(OUT.parent.parent)}")


# ---- Arunoday: the dawn ----------------------------------------------------

def a1_horizon():
    """Half sun on the horizon — the literal arunoday (sunrise)."""
    c = Canvas()
    hy = 640
    c.glow(512, hy, 300, DAWN, 0.22)
    # Horizon, brightest under the sun, fading to the edges.
    line = stroke(64, hy, 960, hy, 10)
    fade = np.exp(-((X - 512) ** 2) / (2 * 330**2))
    c.paint(line * fade, hex_rgb(DAWN), 0.65)
    c.paint(
        disc(512, hy - 5, 215, cut_below=hy - 5),
        vgrad("#FFD9A8", "#FF8A4A", hy - 220, hy),
    )
    return c.down()


def a2_first_rays():
    """Classic sunrise glyph — half sun with rays. Instantly legible."""
    c = Canvas()
    hy = 660
    c.glow(512, hy, 260, DAWN, 0.16)
    sun_r = 150
    c.paint(
        disc(512, hy - 4, sun_r, cut_below=hy - 4),
        vgrad("#FFD9A8", "#FF8A4A", hy - 155, hy),
    )
    amber = hex_rgb(DAWN)
    for deg in (-64, -32, 0, 32, 64):  # from straight-up, fan of five
        a = np.radians(deg)
        dx, dy = np.sin(a), -np.cos(a)
        r0, r1 = sun_r + 64, sun_r + 168
        c.paint(
            stroke(512 + dx * r0, hy + dy * r0, 512 + dx * r1, hy + dy * r1, 36),
            amber,
        )
    for x0, x1 in ((104, 300), (724, 920)):  # horizon, parted for the sun
        c.paint(stroke(x0, hy, x1, hy, 10), amber, 0.5)
    return c.down()


def a3_dawn_dot():
    """Sun clear of the ground line — risen. The most abstract-minimal one."""
    c = Canvas()
    c.glow(512, 470, 260, DAWN, 0.18)
    c.paint(disc(512, 470, 195), vgrad("#FFD9A8", "#FF8A4A", 275, 665))
    c.paint(stroke(252, 762, 772, 762, 12), hex_rgb(DAWN), 0.55)
    return c.down()


# ---- Nivaat: the windless shuttlecock --------------------------------------

TILT = 26  # shuttle tilt, degrees clockwise from upright


def _shuttle_strokes(c, cx, cy, scale, color, alpha=1.0):
    """Line-art shuttlecock: cork disc + four feathers + mouth rim, tilted.

    Local frame before tilt: cork centre at (cx, cy), mouth opening straight
    up. All coordinates rotate around the cork by TILT.
    """
    s = scale
    cork_r = 92 * s
    c.paint(disc(cx, cy, cork_r), color, alpha)
    neck_y, mouth_y = cy - 118 * s, cy - 400 * s
    necks = (-46, -15, 15, 46)
    mouths = (-152, -51, 51, 152)
    for nx, mx in zip(necks, mouths):
        (a, b) = rot(
            [(cx + nx * s, neck_y), (cx + mx * s, mouth_y)], cx, cy, TILT
        )
        c.paint(stroke(*a, *b, 34 * s), color, alpha)
    (m0, m1) = rot(
        [(cx - 152 * s, mouth_y), (cx + 152 * s, mouth_y)], cx, cy, TILT
    )
    c.paint(stroke(*m0, *m1, 34 * s), color, alpha)


def _shuttle_filled(c, cx, cy, scale, color, seam="#0A0A0A"):
    """Solid shuttlecock silhouette (reads at the smallest sizes)."""
    s = scale
    c.paint(disc(cx, cy, 92 * s), color)
    neck_y, mouth_y = cy - 100 * s, cy - 390 * s
    quad = rot(
        [
            (cx - 46 * s, neck_y),
            (cx - 152 * s, mouth_y),
            (cx + 152 * s, mouth_y),
            (cx + 46 * s, neck_y),
        ],
        cx,
        cy,
        TILT,
    )
    c.paint(convex([quad[0], quad[3], quad[2], quad[1]]), color)
    # Feather seams, drawn in background ink over the fill.
    for nx, mx in ((-15, -51), (15, 51)):
        (a, b) = rot(
            [(cx + nx * s, neck_y), (cx + mx * s, mouth_y)], cx, cy, TILT
        )
        c.paint(stroke(*a, *b, 13 * s), hex_rgb(seam), 0.9)


def n1_shuttle():
    """The shuttlecock, line-drawn. Says badminton in one glance."""
    c = Canvas()
    c.glow(560, 420, 330, WIND, 0.10)
    _shuttle_strokes(c, 442, 668, 1.0, hex_rgb(WIND))
    return c.down()


def n2_calm():
    """Wind dying: three gusts, curls unwinding, fading out.
    The nivaat (windless) itself."""
    c = Canvas()
    blue = hex_rgb(WIND)
    th = 52
    # Each gust is ONE coverage mask (union of line + curl): translucent
    # strokes painted twice would show a seam at the joint.
    up = np.maximum(
        stroke(276, 380, 600, 380, th), arc(600, 380 - 58, 58, -90, 140, th)
    )
    c.paint(up, blue, 1.0)
    down = np.maximum(
        stroke(276, 530, 588, 530, th), arc(588, 530 + 50, 50, -150, 90, th)
    )
    c.paint(down, blue, 0.58)
    # Last of it: a straight breath, nearly gone.
    c.paint(stroke(276, 666, 470, 666, th), blue, 0.30)
    return c.down()


def n3_shuttle_badge():
    """Filled shuttlecock inside a thin ring — a crest."""
    c = Canvas()
    c.paint(ring(512, 512, 356, 24), hex_rgb(WIND), 0.85)
    _shuttle_filled(c, 462, 634, 0.80, hex_rgb(WIND))
    return c.down()


# ---- previews ---------------------------------------------------------------

def squircle_mask():
    """Apple-style superellipse alpha mask at final resolution."""
    c = (np.arange(SIZE) + 0.5) - SIZE / 2
    x, y = np.meshgrid(c, c)
    half = SIZE / 2
    n = 4.8
    f = (np.abs(x / half) ** n + np.abs(y / half) ** n) ** (1 / n)
    return np.clip(0.5 + (1 - f) * half / 2.2, 0, 1)[..., None]


def contact_sheet(icons):
    """Candidates side by side, squircle-masked, on a launcher-dark ground."""
    mask = squircle_mask()
    bg = hex_rgb("#1C1C22")
    pad, cell = 48, 512
    w = pad + len(icons) * (cell + pad)
    sheet = np.ones((cell + 2 * pad, w, 3)) * bg
    for i, icon in enumerate(icons):
        masked = bg * (1 - mask) + icon * mask
        small = masked.reshape(cell, 2, cell, 2, 3).mean(axis=(1, 3))
        x0 = pad + i * (cell + pad)
        sheet[pad : pad + cell, x0 : x0 + cell] = small
    return sheet


# ---- launcher assets (--apply) ----------------------------------------------

REPO = OUT.parent.parent
# Android adaptive foreground is a 108dp full-bleed layer of which launchers
# show the middle ~66-72dp; the raw square would sit too close to that crop,
# so the foreground is the icon scaled down onto its own background gradient.
ADAPTIVE_SHRINK = 0.80
FG_DP, LEGACY_DP = 108, 48
DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}


def resize_bilinear(img, out_size):
    h, w, _ = img.shape
    ys = np.linspace(0, h - 1, out_size)
    xs = np.linspace(0, w - 1, out_size)
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    y1 = np.minimum(y0 + 1, h - 1)
    x1 = np.minimum(x0 + 1, w - 1)
    fy = (ys - y0)[:, None, None]
    fx = (xs - x0)[None, :, None]
    top = img[y0][:, x0] * (1 - fx) + img[y0][:, x1] * fx
    bot = img[y1][:, x0] * (1 - fx) + img[y1][:, x1] * fx
    return top * (1 - fy) + bot * fy


def adaptive_foreground(icon):
    """The icon shrunk onto a fresh copy of its background gradient."""
    base = Canvas().down()
    small = resize_bilinear(icon, int(SIZE * ADAPTIVE_SHRINK))
    off = (SIZE - small.shape[0]) // 2
    base[off : off + small.shape[0], off : off + small.shape[1]] = small
    return base


def sips(src, dst, size):
    dst.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["sips", "-s", "format", "png", "-z", str(size), str(size),
         str(src), "--out", str(dst)],
        check=True, capture_output=True,
    )
    print(f"  {dst.relative_to(REPO)}")


ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/{name}_fg"/>
</adaptive-icon>
"""

BACKGROUND_XML = """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Behind the adaptive-icon foreground (visible only at parallax
         edges); matches the icons' own near-black gradient. -->
    <color name="ic_launcher_background">#FF060606</color>
</resources>
"""

IOS_CONTENTS = {
    "images": [
        {"filename": "Icon-1024.png", "idiom": "universal",
         "platform": "ios", "size": "1024x1024"}
    ],
    "info": {"author": "xcode", "version": 1},
}


def apply_launcher_assets(app, icons, tmp):
    """Write Android mipmaps, iOS appiconsets, and picker thumbnails."""
    res = REPO / "apps" / app / "android" / "app" / "src" / "main" / "res"
    xcassets = REPO / "apps" / app / "ios" / "Runner" / "Assets.xcassets"
    imgs = list(icons.values())

    # Full-res sources for sips.
    raws, fgs = [], []
    for i, img in enumerate(imgs, start=1):
        raw = tmp / f"{app}-{i}-raw.png"
        fg = tmp / f"{app}-{i}-fg.png"
        write_png(raw, img)
        write_png(fg, adaptive_foreground(img))
        raws.append(raw)
        fgs.append(fg)

    # Android: ic_launcher (default, also legacy) + ic_launcher_2/_3 aliases.
    mipmaps = ["ic_launcher", "ic_launcher_2", "ic_launcher_3"]
    for density, scale in DENSITIES.items():
        d = res / f"mipmap-{density}"
        sips(raws[0], d / "ic_launcher.png", round(LEGACY_DP * scale))
        for name, fg in zip(mipmaps, fgs):
            sips(fg, d / f"{name}_fg.png", round(FG_DP * scale))
    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    for name in mipmaps:
        (anydpi / f"{name}.xml").write_text(ADAPTIVE_XML.format(name=name))
    (res / "values" / "ic_launcher_background.xml").write_text(BACKGROUND_XML)

    # iOS: single-size 1024 appiconsets (Xcode 14+), replacing the Flutter
    # template's multi-size default set.
    for setname, img in zip(["AppIcon", "AppIconTwo", "AppIconThree"], imgs):
        s = xcassets / f"{setname}.appiconset"
        s.mkdir(parents=True, exist_ok=True)
        for old in s.glob("*.png"):
            old.unlink()
        (s / "Contents.json").write_text(json.dumps(IOS_CONTENTS, indent=2))
        write_png(s / "Icon-1024.png", img)

    # In-app picker thumbnails.
    for i, raw in enumerate(raws, start=1):
        sips(raw, REPO / "apps" / app / "assets" / "icons" / f"{i}.png", 256)


def main(apply):
    arunoday = {
        "a1-horizon": a1_horizon(),
        "a2-first-rays": a2_first_rays(),
        "a3-dawn-dot": a3_dawn_dot(),
    }
    nivaat = {
        "n1-shuttle": n1_shuttle(),
        "n2-calm": n2_calm(),
        "n3-shuttle-badge": n3_shuttle_badge(),
    }
    for app, icons in (("arunoday", arunoday), ("nivaat", nivaat)):
        for name, img in icons.items():
            write_png(OUT / app / f"{name}.png", img)
        write_png(OUT / f"{app}-preview.png", contact_sheet(list(icons.values())))
        if apply:
            tmp = REPO / "tools" / ".icon_tmp"
            tmp.mkdir(exist_ok=True)
            apply_launcher_assets(app, icons, tmp)
            for f in tmp.iterdir():
                f.unlink()
            tmp.rmdir()


if __name__ == "__main__":
    main(apply="--apply" in sys.argv)
