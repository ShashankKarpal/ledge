#!/usr/bin/env python3
"""Ink and Bone mark pipeline.

Single source of truth for every project mark and its full export matrix.
Geometry lives in MARKS below, drawn on a 96x96 grid, stroke 7, round caps,
true arcs. Each mark has three variants: master, s24, s16 (optically
simplified). Everything else (SVG, PDF, PNG, JPEG, iconsets, icns, ico,
appiconsets, watch assets, menu bar templates, favicons, banners, social
previews, wordmark lockups, contact sheets) is generated from those
definitions. Nothing is hand-placed.

Run:  python3 generate_marks.py [project ...]
Deps: cairosvg, pillow, fonttools, icnsutil
On macOS, .icns can also be rebuilt natively:
  iconutil -c icns out/<p>/macos/AppIcon.iconset -o AppIcon.icns
"""

import base64
import io
import json
import math
import os
import random
import shutil
import sys

import cairosvg
from PIL import Image
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
FONT_PATH = os.path.join(HERE, "..", "brand", "font", "KarpalGeometric-Regular.ttf")

PAL = {
    "dark": {"page": "#0B0C0D", "ink": "#F3F1EB",
             "copper": "#B17E51", "brass": "#BFB287", "mist": "#CFDFE8",
             "quiet": "#8F8C85", "card": "#171614"},
    "light": {"page": "#F5F5F3", "ink": "#1A1917",
              "copper": "#99612F", "brass": "#4D4323", "mist": "#2D647F",
              "quiet": "#5A5852", "card": "#FFFFFF"},
}
GRAIN = {"dark": 0.16, "light": 0.07}

# element helpers -----------------------------------------------------------

def R(x, y, w, h, rx, role="ink", mode="fill", sw=0, rot=None):
    return {"t": "rect", "x": x, "y": y, "w": w, "h": h, "rx": rx,
            "role": role, "mode": mode, "sw": sw, "rot": rot}

def C(cx, cy, r, role="ink", mode="fill", sw=0):
    return {"t": "circle", "cx": cx, "cy": cy, "r": r,
            "role": role, "mode": mode, "sw": sw}

def P(d, role="ink", mode="stroke", sw=7, fill_too=False, rot=None):
    return {"t": "path", "d": d, "role": role, "mode": mode, "sw": sw,
            "fill_too": fill_too, "rot": rot}

def G(inner, transform, role="ink", sw=7):
    return {"t": "group", "inner": inner, "transform": transform,
            "role": role, "sw": sw}

MARKS = {
    "ledge": {
        "cat": "copper", "private": False,
        "story": "an idea lands on the step, one more chance on the floor, "
                 "caught before the gutter",
        "master": [R(14, 38, 36, 44, 7), R(14, 64, 68, 18, 7),
                   C(46, 28, 10, role="acc")],
        "s24": [R(10, 36, 38, 48, 8), R(10, 62, 76, 22, 8),
                C(46, 23, 13, role="acc")],
        "s16": [R(8, 34, 40, 52, 9), R(8, 60, 80, 26, 9),
                C(46, 19, 15, role="acc")],
    },
    "content-digest-app": {
        "cat": "copper", "private": False,
        "story": "three lines in, one line carried out",
        "master": [P("M14 28 40 28M14 48 50 48M14 68 40 68"),
                   P("M62 48 84 48", role="acc")],
        "s24": [P("M12 26 40 26M12 48 50 48M12 70 40 70", sw=10),
                P("M62 48 86 48", role="acc", sw=10)],
        "s16": [P("M10 24 38 24M10 48 48 48M10 72 38 72", sw=13),
                P("M62 48 88 48", role="acc", sw=13)],
    },
    "helios": {
        "cat": "brass", "private": False,
        "story": "many sources into one hub, one steady line out",
        "master": [C(52, 48, 11, mode="stroke", sw=7),
                   P("M12 20 36.8 37.4M10 48 33.5 48M12 76 36.8 58.6"),
                   P("M70.5 48 86 48", role="acc")],
        "s24": [C(50, 48, 12, mode="stroke", sw=10),
                P("M12 22 32.7 36.1M10 48 29 48M12 74 32.7 59.9", sw=10),
                P("M71 48 88 48", role="acc", sw=10)],
        "s16": [C(46, 48, 13, mode="stroke", sw=13),
                P("M10 18 27.2 32.3M10 78 27.2 63.7", sw=13),
                P("M69.5 48 90 48", role="acc", sw=13)],
    },
    "zest": {
        "cat": "brass", "private": False,
        "story": "a cell with charge in it",
        "master": [P("M40 12 56 12"), R(30, 22, 36, 60, 10, mode="stroke", sw=7),
                   P("M36 52 60 36 60 68 Z", role="acc", sw=4, fill_too=True)],
        "s24": [P("M40 13 56 13", sw=10), R(28, 24, 40, 58, 11, mode="stroke", sw=10),
                P("M36 52 58 38 58 66 Z", role="acc", sw=4, fill_too=True)],
        "s16": [P("M40 14 56 14", sw=13), R(26, 26, 44, 56, 12, mode="stroke", sw=13),
                P("M36 54 56 42 56 66 Z", role="acc", sw=5, fill_too=True)],
    },
    "switchdeck": {
        "cat": "mist", "private": False,
        "story": "a fanned deck, the active card in front",
        "master": [R(26, 48, 44, 28, 7, mode="stroke", sw=7, rot=(-30, 26, 76)),
                   R(26, 48, 44, 28, 7, mode="stroke", sw=7, rot=(-15, 26, 76)),
                   R(26, 48, 44, 28, 7, role="acc")],
        "s24": [R(24, 50, 48, 30, 8, mode="stroke", sw=10, rot=(-30, 24, 80)),
                R(24, 50, 48, 30, 8, mode="stroke", sw=10, rot=(-15, 24, 80)),
                R(24, 50, 48, 30, 8, role="acc")],
        "s16": [R(22, 46, 52, 32, 9, rot=(-20, 22, 78)),
                R(22, 46, 52, 32, 9, role="acc")],
    },
    "uebersicht-claude-tokens": {
        "cat": "mist", "private": False, "display": "claude-tokens",
        "story": "stacks of coins, one loose on top",
        "master": ([R(14, y, 22, 7, 3.5, role="acc") for y in (65, 75)] +
                   [R(38, y, 22, 7, 3.5, role="acc") for y in (45, 55, 65, 75)] +
                   [R(62, y, 22, 7, 3.5, role="acc") for y in (25, 35, 45, 55, 65, 75)] +
                   [R(62, 10, 22, 7, 3.5, rot=(-12, 73, 13.5))]),
        "s24": ([R(8, y, 26, 10, 5, role="acc") for y in (72, 58)] +
                [R(38, y, 26, 10, 5, role="acc") for y in (72, 58, 44)] +
                [R(68, y, 26, 10, 5, role="acc") for y in (72, 58, 44, 30)] +
                [R(68, 12, 26, 10, 5, rot=(-14, 81, 17))]),
        "s16": ([R(8, 70, 26, 12, 6, role="acc")] +
                [R(38, y, 26, 12, 6, role="acc") for y in (70, 54)] +
                [R(68, y, 26, 12, 6, role="acc") for y in (70, 54, 38)] +
                [R(68, 16, 26, 12, 6, rot=(-16, 81, 22))]),
    },
    "claude-bridge": {
        "cat": "mist", "private": True,
        "story": "two accounts, a span, the payload crossing",
        "master": [C(22, 66, 10, mode="stroke", sw=7), C(74, 66, 10, mode="stroke", sw=7),
                   P("M22 49 A 34 34 0 0 1 74 49"), C(48, 30, 6.5, role="acc")],
        "s24": [C(20, 67, 11, mode="stroke", sw=10), C(76, 67, 11, mode="stroke", sw=10),
                P("M20 48 A 38 38 0 0 1 76 48", sw=10), C(48, 24, 8, role="acc")],
        "s16": [C(18, 68, 12, mode="stroke", sw=13), C(78, 68, 12, mode="stroke", sw=13),
                P("M18 48 A 40 40 0 0 1 78 48", sw=13), C(48, 19, 9, role="acc")],
    },
    "claude-burnrate": {
        "cat": "mist", "private": True,
        "story": "spend sloping toward the baseline, the ember about to land",
        "master": [P("M14 78 82 78"), P("M18 24 70 66"), C(76, 68, 6.5, role="acc")],
        "s24": [P("M12 79 84 79", sw=10), P("M16 22 66 62", sw=10),
                C(74, 66, 8, role="acc")],
        "s16": [P("M10 80 86 80", sw=13), P("M14 22 62 60", sw=13),
                C(74, 64, 10, role="acc")],
    },
    "claude-skills-workspace": {
        "cat": "ink", "private": True,
        "story": "a workspace of tiles, one skill lifted out",
        "master": [R(26, 26, 22, 22, 6, mode="stroke", sw=7),
                   R(26, 52, 22, 22, 6, mode="stroke", sw=7),
                   R(52, 52, 22, 22, 6, mode="stroke", sw=7),
                   R(52, 18, 22, 22, 6, mode="stroke", sw=7, rot=(9, 63, 29))],
        "s24": [R(22, 24, 24, 24, 7, mode="stroke", sw=10),
                R(22, 52, 24, 24, 7, mode="stroke", sw=10),
                R(52, 52, 24, 24, 7, mode="stroke", sw=10),
                R(52, 16, 24, 24, 7, mode="stroke", sw=10, rot=(9, 64, 28))],
        "s16": [R(20, 26, 26, 26, 8), R(20, 56, 26, 26, 8), R(54, 56, 26, 26, 8),
                R(54, 16, 26, 26, 8, rot=(10, 67, 29))],
    },
    "monogram": {
        "cat": "copper", "private": True, "no_wordmark": True,
        "story": "sk in Karpal Geometric with the copper period. never published",
        "master": [G("M 32.8,51.1 A 11.5,11.5 0 1 0 24,70 A 11.5,11.5 0 1 1 15.2,88.9",
                     "translate(10,5) scale(0.75)", sw=12),
                   G("M 0,14 L 0,100 M 26,50 L 0,74 M 9,66 L 28,100",
                     "translate(52,5) scale(0.75)", sw=12),
                   C(84, 73, 7, role="acc")],
        "s24": [G("M 32.8,51.1 A 11.5,11.5 0 1 0 24,70 A 11.5,11.5 0 1 1 15.2,88.9",
                  "translate(10,5) scale(0.75)", sw=15),
                G("M 0,14 L 0,100 M 26,50 L 0,74 M 9,66 L 28,100",
                  "translate(52,5) scale(0.75)", sw=15),
                C(85, 72, 9, role="acc")],
        "s16": [G("M 32.8,51.1 A 11.5,11.5 0 1 0 24,70 A 11.5,11.5 0 1 1 15.2,88.9",
                  "translate(8,5) scale(0.75)", sw=18),
                G("M 0,14 L 0,100 M 26,50 L 0,74 M 9,66 L 28,100",
                  "translate(52,5) scale(0.75)", sw=18),
                C(86, 70, 11, role="acc")],
    },
}

# svg emit ------------------------------------------------------------------

def colour(role, theme, mono=None):
    if mono:
        return mono
    p = PAL[theme]
    return p["ink"] if role == "ink" else p[role]

def el_svg(e, theme, cat, mono=None):
    role = e.get("role", "ink")
    col = colour("ink" if role == "ink" else cat, theme, mono)
    if e["t"] == "group":
        return ('<g fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round" '
                'stroke-linejoin="round" transform="%s"><path d="%s"/></g>'
                % (col, e["sw"], e["transform"], e["inner"]))
    if e["t"] == "circle":
        if e["mode"] == "stroke":
            return ('<circle cx="%s" cy="%s" r="%s" fill="none" stroke="%s" '
                    'stroke-width="%s"/>' % (e["cx"], e["cy"], e["r"], col, e["sw"]))
        return '<circle cx="%s" cy="%s" r="%s" fill="%s"/>' % (e["cx"], e["cy"], e["r"], col)
    if e["t"] == "rect":
        rot = ' transform="rotate(%s %s %s)"' % e["rot"] if e.get("rot") else ""
        if e["mode"] == "stroke":
            return ('<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="none" '
                    'stroke="%s" stroke-width="%s" stroke-linejoin="round"%s/>'
                    % (e["x"], e["y"], e["w"], e["h"], e["rx"], col, e["sw"], rot))
        return ('<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="%s"%s/>'
                % (e["x"], e["y"], e["w"], e["h"], e["rx"], col, rot))
    if e["t"] == "path":
        rot = ' transform="rotate(%s %s %s)"' % e["rot"] if e.get("rot") else ""
        if e.get("fill_too"):
            return ('<path d="%s" fill="%s" stroke="%s" stroke-width="%s" '
                    'stroke-linejoin="round"%s/>' % (e["d"], col, col, e["sw"], rot))
        return ('<path d="%s" fill="none" stroke="%s" stroke-width="%s" '
                'stroke-linecap="round" stroke-linejoin="round"%s/>'
                % (e["d"], col, e["sw"], rot))
    raise ValueError(e["t"])

def mark_svg(project, variant, theme, ground=None, mono=None, size=None):
    m = MARKS[project]
    body = "".join(el_svg(e, theme, m["cat"], mono) for e in m[variant])
    bg = '<rect width="96" height="96" fill="%s"/>' % ground if ground else ""
    wh = ' width="%s" height="%s"' % (size, size) if size else ""
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96"%s>%s%s</svg>'
            % (wh, bg, body))

def variant_for(px):
    if px >= 48:
        return "master"
    if px >= 20:
        return "s24"
    return "s16"

def favicon_svg(project):
    m = MARKS[project]
    dark = "".join(el_svg(e, "dark", m["cat"]) for e in m["s16"])
    light = "".join(el_svg(e, "light", m["cat"]) for e in m["s16"])
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96">'
            '<style>.d{display:none}@media(prefers-color-scheme:dark)'
            '{.l{display:none}.d{display:inline}}</style>'
            '<g class="l">%s</g><g class="d">%s</g></svg>' % (light, dark))

# raster --------------------------------------------------------------------

def svg_to_png(svg, px_w, px_h=None):
    px_h = px_h or px_w
    return cairosvg.svg2png(bytestring=svg.encode(), output_width=px_w,
                            output_height=px_h)

def png_bytes_to_img(b):
    return Image.open(io.BytesIO(b)).convert("RGBA")

def save_png(svg, path, px_w, px_h=None):
    with open(path, "wb") as f:
        f.write(svg_to_png(svg, px_w, px_h))

def grain_overlay(size_wh, opacity):
    random.seed(96)
    w, h = size_wh
    tile = Image.effect_noise((256, 256), 64).convert("L")
    g = Image.new("L", (w, h))
    for x in range(0, w, 256):
        for y in range(0, h, 256):
            g.paste(tile, (x, y))
    a = g.point(lambda v: int(abs(v - 128) * 2 * opacity))
    rgb = g.point(lambda v: 255 if v > 128 else 0)
    out = Image.merge("RGBA", (rgb, rgb, rgb, a))
    return out

# wordmarks -----------------------------------------------------------------

_font = None

def font():
    global _font
    if _font is None:
        _font = TTFont(FONT_PATH)
    return _font

def text_paths(text, em=100, tracking=0.02):
    f = font()
    cmap = f.getBestCmap()
    glyphs = f.getGlyphSet()
    upem = f["head"].unitsPerEm
    s = em / upem
    x = 0.0
    out = []
    for ch in text.lower():
        gname = cmap.get(ord(ch))
        if gname is None:
            x += 0.35 * em
            continue
        pen = SVGPathPen(glyphs)
        glyphs[gname].draw(pen)
        d = pen.getCommands()
        if d:
            out.append('<g transform="translate(%.2f,0) scale(%.6f,-%.6f)">'
                       '<path d="%s"/></g>' % (x, s, s, d))
        x += glyphs[gname].width * s + tracking * em
    return out, x

def wordmark_svg(project, theme, layout, ground=None):
    m = MARKS[project]
    ink = PAL[theme]["ink"]
    paths, tw = text_paths(m.get("display", project))
    em = 100
    asc, desc = 68.8, 22.4
    mark_h = 120
    mark = "".join(el_svg(e, theme, m["cat"]) for e in m["master"])
    pad = 40
    if layout == "horizontal":
        W = pad + mark_h + 40 + tw + pad
        H = pad + max(mark_h, asc + desc) + pad
        mk_y = (H - mark_h) / 2
        base = H / 2 + asc / 2 - 6
        body = ('<g transform="translate(%s,%s) scale(%.4f)">%s</g>'
                '<g fill="%s" transform="translate(%s,%.1f)">%s</g>'
                % (pad, mk_y, mark_h / 96.0, mark, ink,
                   pad + mark_h + 40, base, "".join(paths)))
    else:
        W = max(mark_h, tw) + 2 * pad
        H = pad + mark_h + 36 + asc + desc + pad
        body = ('<g transform="translate(%s,%s) scale(%.4f)">%s</g>'
                '<g fill="%s" transform="translate(%s,%.1f)">%s</g>'
                % ((W - mark_h) / 2, pad, mark_h / 96.0, mark, ink,
                   (W - tw) / 2, pad + mark_h + 36 + asc, "".join(paths)))
    bg = '<rect width="%s" height="%s" fill="%s"/>' % (W, H, ground) if ground else ""
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %.0f %.0f">%s%s</svg>'
            % (W, H, bg, body)), W, H

# banners and social --------------------------------------------------------

GRAIN_FILTER = ('<filter id="gr"><feTurbulence type="fractalNoise" '
                'baseFrequency="0.9" numOctaves="3"/>'
                '<feColorMatrix type="saturate" values="0"/>'
                '<feComponentTransfer><feFuncA type="linear" slope="%s"/>'
                '</feComponentTransfer><feComposite operator="in" in2="SourceGraphic"/></filter>')

def banner_svg(project, theme, W=1400, H=400):
    m = MARKS[project]
    p = PAL[theme]
    rail = p["ink"] if m["cat"] == "ink" else p[m["cat"]]
    mark = "".join(el_svg(e, theme, m["cat"]) for e in m["master"])
    paths, tw = text_paths(m.get("display", project))
    scale_txt = min(1.1, (W - 360 - 60) / tw) if tw else 1.1
    mark_h = 200
    body = [
        '<rect width="%s" height="%s" fill="%s"/>' % (W, H, p["page"]),
        '<defs>%s</defs>' % (GRAIN_FILTER % GRAIN[theme]),
        '<rect width="%s" height="%s" fill="%s" filter="url(#gr)" opacity="%s"/>'
        % (W, H, p["ink"], GRAIN[theme]),
        '<rect width="8" height="%s" fill="%s"/>' % (H, rail),
        '<g transform="translate(90,%s) scale(%.4f)">%s</g>'
        % ((H - mark_h) / 2, mark_h / 96.0, mark),
        '<g fill="%s" transform="translate(360,%.1f) scale(%s)">%s</g>'
        % (p["ink"], H / 2 + 68.8 * scale_txt / 2, scale_txt, "".join(paths)),
    ]
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s">%s</svg>'
            % (W, H, "".join(body)))

def social_svg(project, W=1280, H=640):
    m = MARKS[project]
    p = PAL["dark"]
    rail = p["ink"] if m["cat"] == "ink" else p[m["cat"]]
    mark = "".join(el_svg(e, "dark", m["cat"]) for e in m["master"])
    paths, tw = text_paths(m.get("display", project))
    ts = min(1.0, (W - 140) / tw) if tw else 1.0
    mark_h = 280
    body = [
        '<rect width="%s" height="%s" fill="%s"/>' % (W, H, p["page"]),
        '<defs>%s</defs>' % (GRAIN_FILTER % GRAIN["dark"]),
        '<rect width="%s" height="%s" fill="%s" filter="url(#gr)" opacity="%s"/>'
        % (W, H, p["ink"], GRAIN["dark"]),
        '<rect y="%s" width="%s" height="8" fill="%s"/>' % (H - 8, W, rail),
        '<g transform="translate(%s,110) scale(%.4f)">%s</g>'
        % ((W - mark_h) / 2, mark_h / 96.0, mark),
        '<g fill="%s" transform="translate(%s,505) scale(%.4f)">%s</g>'
        % (p["ink"], (W - tw * ts) / 2, ts, "".join(paths)),
    ]
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s">%s</svg>'
            % (W, H, "".join(body)))

def render_with_grain(svg, path, W, H, theme):
    img = png_bytes_to_img(svg_to_png(svg, W, H))
    img.alpha_composite(grain_overlay((W, H), GRAIN[theme]))
    img.convert("RGB").save(path)

# icon tiles ----------------------------------------------------------------

def tile_svg(project, px, radius_pct=0.225, scale=0.62, square=False):
    variant = variant_for(int(px * scale))
    m = MARKS[project]
    mark = "".join(el_svg(e, "dark", m["cat"]) for e in m[variant])
    r = 0 if square else 96 * radius_pct
    inner = 96 * scale
    off = (96 - inner) / 2
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96">'
            '<rect width="96" height="96" rx="%s" fill="%s"/>'
            '<g transform="translate(%s,%s) scale(%.4f)">%s</g></svg>'
            % (r, PAL["dark"]["page"], off, off, scale / 1.0 * 1.0 * (inner / 96) * 96 / 96
               if False else inner / 96.0, mark))

IOS_ICONS = [
    ("iphone", 20, [2, 3]), ("iphone", 29, [2, 3]), ("iphone", 40, [2, 3]),
    ("iphone", 60, [2, 3]), ("ipad", 20, [1, 2]), ("ipad", 29, [1, 2]),
    ("ipad", 40, [1, 2]), ("ipad", 76, [1, 2]), ("ipad", 83.5, [2]),
    ("ios-marketing", 1024, [1]),
]
WATCH_ICONS = [
    ("watch", 22, [2], "notificationCenter", "38mm"),
    ("watch", 24, [2], "notificationCenter", "42mm"),
    ("watch", 29, [2, 3], "companionSettings", None),
    ("watch", 40, [2], "appLauncher", "38mm"),
    ("watch", 44, [2], "appLauncher", "40mm"),
    ("watch", 50, [2], "appLauncher", "44mm"),
    ("watch", 86, [2], "quickLook", "38mm"),
    ("watch", 98, [2], "quickLook", "42mm"),
    ("watch", 108, [2], "quickLook", "44mm"),
    ("watch-marketing", 1024, [1], None, None),
]

def write_appiconset(project, folder, entries, watch=False):
    os.makedirs(folder, exist_ok=True)
    images = []
    for entry in entries:
        idiom, pt, scales = entry[0], entry[1], entry[2]
        role, subtype = (entry[3], entry[4]) if watch else (None, None)
        for sc in scales:
            px = int(round(pt * sc))
            name = "icon-%s@%sx.png" % (str(pt).replace(".0", ""), sc)
            square = idiom in ("ios-marketing", "watch-marketing")
            svg = tile_svg(project, px, square=square)
            img = png_bytes_to_img(svg_to_png(svg, px))
            if square:
                img = img.convert("RGB")
            img.save(os.path.join(folder, name))
            rec = {"idiom": idiom, "size": "%sx%s" % (pt, pt),
                   "scale": "%sx" % sc, "filename": name}
            if role:
                rec["role"] = role
            if subtype:
                rec["subtype"] = subtype
            images.append(rec)
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"images": images,
                   "info": {"version": 1, "author": "generate_marks.py"}}, f, indent=2)

def mono_mark_png(project, px, color=(0, 0, 0, 255), pad_pct=0.08):
    inner = int(px * (1 - 2 * pad_pct))
    svg = mark_svg(project, variant_for(inner), "dark", mono="#000000")
    img = png_bytes_to_img(svg_to_png(svg, inner))
    r, g, b, a = img.split()
    solid = Image.new("RGBA", img.size, color)
    solid.putalpha(a)
    out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    out.paste(solid, ((px - inner) // 2, (px - inner) // 2), solid)
    return out

# contact sheet -------------------------------------------------------------

def contact_sheet(project, pdir):
    from PIL import ImageDraw
    disp = MARKS[project].get("display", project)
    cell, pad = 220, 24
    cols = 4
    items = [(p, l) for p, l in [
        (os.path.join(pdir, "png", "mark-512-page.png"), "master dark"),
        (os.path.join(pdir, "png", "mark-512-paper.png"), "master light"),
        (os.path.join(pdir, "macos", "AppIcon.iconset", "icon_512x512.png"), "app icon"),
        (os.path.join(pdir, "web", "social-preview-1280x640.png"), "social"),
        (os.path.join(pdir, "web", "banner-dark-1400x400.png"), "banner dark"),
        (os.path.join(pdir, "web", "banner-light-1400x400.png"), "banner light"),
        (os.path.join(pdir, "wordmark", "wordmark-horizontal-dark.png"), "wordmark"),
        (os.path.join(pdir, "png", "mark-16.png"), "16 px actual"),
    ] if os.path.exists(p)]
    rows = math.ceil(len(items) / cols)
    W = cols * cell + (cols + 1) * pad
    H = rows * cell + rows * 30 + (rows + 1) * pad + 40
    sheet = Image.new("RGB", (W, H), (23, 22, 20))
    d = ImageDraw.Draw(sheet)
    for i, (path, label) in enumerate(items):
        cx = pad + (i % cols) * (cell + pad)
        cy = pad + (i // cols) * (cell + pad + 30)
        im = Image.open(path).convert("RGBA")
        if label == "16 px actual":
            canvas = Image.new("RGBA", (cell, cell), (11, 12, 13, 255))
            big = im.resize((160, 160), Image.NEAREST)
            canvas.paste(big, ((cell - 160) // 2, 10), big)
            canvas.paste(im, ((cell - 16) // 2, 186), im)
            im = canvas
        else:
            im.thumbnail((cell, cell))
            canvas = Image.new("RGBA", (cell, cell), (32, 30, 27, 255))
            canvas.paste(im, ((cell - im.width) // 2, (cell - im.height) // 2), im)
            im = canvas
        sheet.paste(im.convert("RGB"), (cx, cy))
        d.text((cx + 4, cy + cell + 6), label, fill=(143, 140, 133))
    d.text((pad, H - 34), disp + "  .  ink and bone", fill=(243, 241, 235))
    out = os.path.join(pdir, "contact-sheet-%s.png" % disp)
    sheet.save(out)
    old = os.path.join(pdir, "contact-sheet.png")
    if os.path.exists(old):
        try:
            os.remove(old)
        except OSError:
            sheet.save(old)
    return out

# main build ----------------------------------------------------------------

PNG_SIZES = [1024, 512, 256, 128, 64, 48, 32, 24, 16]

def build(project):
    m = MARKS[project]
    pdir = os.path.join(OUT, "private" if m["private"] and project == "monogram" else "",
                        project)
    for sub in ("svg", "pdf", "png", "jpeg", "wordmark", "macos", "ios",
                "watchos", "web", "appstore"):
        os.makedirs(os.path.join(pdir, sub), exist_ok=True)

    sv = os.path.join(pdir, "svg")
    files = {
        "mark.svg": mark_svg(project, "master", "dark"),
        "mark-light.svg": mark_svg(project, "master", "light"),
        "mark-24.svg": mark_svg(project, "s24", "dark", size=24),
        "mark-24-light.svg": mark_svg(project, "s24", "light", size=24),
        "mark-16.svg": mark_svg(project, "s16", "dark", size=16),
        "mark-16-light.svg": mark_svg(project, "s16", "light", size=16),
        "mark-mono.svg": mark_svg(project, "master", "dark", mono="#000000"),
    }
    for name, svg in files.items():
        with open(os.path.join(sv, name), "w") as f:
            f.write(svg)

    cairosvg.svg2pdf(bytestring=files["mark-light.svg"].encode(),
                     write_to=os.path.join(pdir, "pdf", "mark.pdf"))
    cairosvg.svg2pdf(bytestring=files["mark.svg"].encode(),
                     write_to=os.path.join(pdir, "pdf", "mark-dark.pdf"))

    for px in PNG_SIZES:
        v = variant_for(px)
        save_png(mark_svg(project, v, "dark"),
                 os.path.join(pdir, "png", "mark-%s.png" % px), px)
        save_png(mark_svg(project, v, "light"),
                 os.path.join(pdir, "png", "mark-light-%s.png" % px), px)
        save_png(mark_svg(project, v, "dark", ground=PAL["dark"]["page"]),
                 os.path.join(pdir, "png", "mark-%s-page.png" % px), px)
        save_png(mark_svg(project, v, "light", ground=PAL["light"]["page"]),
                 os.path.join(pdir, "png", "mark-%s-paper.png" % px), px)
    for px in (1024, 512):
        for gname, theme in (("page", "dark"), ("paper", "light")):
            img = png_bytes_to_img(svg_to_png(
                mark_svg(project, "master", theme, ground=PAL[theme]["page"]), px))
            img.convert("RGB").save(
                os.path.join(pdir, "jpeg", "mark-%s-%s.jpg" % (px, gname)), quality=92)

    if not m.get("no_wordmark"):
        for layout in ("horizontal", "stacked"):
            for theme in ("dark", "light"):
                svg, W, H = wordmark_svg(project, theme, layout)
                base = os.path.join(pdir, "wordmark",
                                    "wordmark-%s-%s" % (layout, theme))
                with open(base + ".svg", "w") as f:
                    f.write(svg)
                cairosvg.svg2pdf(bytestring=svg.encode(), write_to=base + ".pdf")
                save_png(svg, base + ".png", int(W * 2), int(H * 2))

    iconset = os.path.join(pdir, "macos", "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    for pt in (16, 32, 128, 256, 512):
        for sc in (1, 2):
            px = pt * sc
            suffix = "" if sc == 1 else "@2x"
            save_png(tile_svg(project, px),
                     os.path.join(iconset, "icon_%sx%s%s.png" % (pt, pt, suffix)), px)
    try:
        import icnsutil
        icns = icnsutil.IcnsFile()
        for fn in sorted(os.listdir(iconset)):
            icns.add_media(file=os.path.join(iconset, fn))
        icns.write(os.path.join(pdir, "macos", "AppIcon.icns"))
    except Exception as ex:
        print("  icns skipped (%s); use iconutil on macOS" % ex)

    for sc, px in ((1, 22), (2, 44), (3, 66)):
        suffix = "" if sc == 1 else "@%sx" % sc
        mono_mark_png(project, px).save(
            os.path.join(pdir, "macos", "%s-template%s.png" % (project, suffix)))

    write_appiconset(project, os.path.join(pdir, "ios", "AppIcon.appiconset"), IOS_ICONS)
    save_png(tile_svg(project, 180), os.path.join(pdir, "ios", "apple-touch-icon.png"), 180)
    write_appiconset(project, os.path.join(pdir, "watchos", "AppIcon.appiconset"),
                     WATCH_ICONS, watch=True)
    comp = os.path.join(pdir, "watchos", "complications")
    os.makedirs(comp, exist_ok=True)
    for name, px in (("circular@2x", 72), ("extra-large@2x", 224),
                     ("graphic-corner@2x", 80), ("graphic-circular@2x", 94)):
        mono_mark_png(project, px, color=(255, 255, 255, 255)).save(
            os.path.join(comp, "complication-%s.png" % name))

    web = os.path.join(pdir, "web")
    with open(os.path.join(web, "favicon.svg"), "w") as f:
        f.write(favicon_svg(project))
    icons = [png_bytes_to_img(svg_to_png(mark_svg(project, variant_for(px), "dark"), px))
             for px in (48, 32, 16)]
    icons[0].save(os.path.join(web, "favicon.ico"), sizes=[(48, 48), (32, 32), (16, 16)],
                  append_images=icons[1:])
    if not m.get("no_wordmark"):
        for theme in ("dark", "light"):
            bsvg = banner_svg(project, theme)
            with open(os.path.join(web, "banner-%s-1400x400.svg" % theme), "w") as f:
                f.write(bsvg)
            render_with_grain(bsvg, os.path.join(web, "banner-%s-1400x400.png" % theme),
                              1400, 400, theme)
        ssvg = social_svg(project)
        with open(os.path.join(web, "social-preview-1280x640.svg"), "w") as f:
            f.write(ssvg)
        render_with_grain(ssvg, os.path.join(web, "social-preview-1280x640.png"),
                          1280, 640, "dark")

    img = png_bytes_to_img(svg_to_png(tile_svg(project, 1024, square=True), 1024))
    img.convert("RGB").save(os.path.join(pdir, "appstore", "AppStore-1024.png"))

    sheet = contact_sheet(project, pdir)
    print("  built %s -> %s" % (project, os.path.relpath(pdir, HERE)))
    return sheet

def main():
    targets = sys.argv[1:] or list(MARKS.keys())
    os.makedirs(OUT, exist_ok=True)
    priv = os.path.join(OUT, "private")
    os.makedirs(priv, exist_ok=True)
    with open(os.path.join(priv, "README-PRIVATE.md"), "w") as f:
        f.write("# PRIVATE. Do not publish.\n\nEverything in this folder is "
                "personal and must never appear in a README, a repo, or any "
                "public surface on GitHub. The monogram lives here by "
                "Shanky's explicit instruction.\n")
    for p in targets:
        build(p)

if __name__ == "__main__":
    main()
