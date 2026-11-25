"""Builds 白地図帳.pdf: high-school geography white maps to write on in
Goodnotes. A4 landscape, Robinson projection with the Pacific in the
middle (as in Japanese atlases); each theme comes with names and without
(書き込み用), plus a blank map of Japan and its surroundings.

    python -I -X utf8 build_pdf.py <raw-dir> <out.pdf>

<raw-dir> holds Natural Earth downloads (public domain), from
github.com/nvkelso/natural-earth-vector/tree/master/geojson:
ne_50m_coastline, ne_50m_admin_0_boundary_lines_land, ne_50m_land,
ne_50m_lakes, ne_10m_coastline, ne_10m_admin_0_boundary_lines_land,
ne_10m_lakes (.geojson).

data/ holds the themes: rivers, plates, koppen (.geojson, from
build_geodata.py) and schematics.json (ocean currents, winds and pressure
belts, orogenic belts, ranges: textbook-level schematics).

Labels use BIZ UDGothic (SIL Open Font License), embedded as a subset.
"""

import json
import math
import os
import sys

from reportlab.lib.pagesizes import A4, landscape
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

RAW, OUT = sys.argv[1], sys.argv[2]
HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")

FONT_DIR = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts")
pdfmetrics.registerFont(TTFont("UD", os.path.join(FONT_DIR, "BIZ-UDGothicR.ttc"), subfontIndex=0))
pdfmetrics.registerFont(TTFont("UDB", os.path.join(FONT_DIR, "BIZ-UDGothicB.ttc"), subfontIndex=0))

PAGE_W, PAGE_H = landscape(A4)
CM = 150.0  # central meridian


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


# Colors: iOS system palette, as in the app.
RED, ORANGE, YELLOW = hexrgb("FF3B30"), hexrgb("FF9500"), hexrgb("FFCC00")
GREEN, MINT, TEAL = hexrgb("34C759"), hexrgb("00C7BE"), hexrgb("30B0C7")
BLUE, PURPLE, GRAY, BROWN = hexrgb("007AFF"), hexrgb("AF52DE"), hexrgb("8E8E93"), hexrgb("A2845E")
INK, BORDER, GRID = (0.1, 0.1, 0.1), (0.62, 0.62, 0.65), (0.82, 0.82, 0.85)
WHITE = (1, 1, 1)

KOPPEN = {
    "Af": (RED, 0.85), "Am": (RED, 0.55), "Aw": (ORANGE, 0.6),
    "BW": (YELLOW, 0.85), "BS": (YELLOW, 0.4),
    "Cs": (GREEN, 0.35), "Cw": (MINT, 0.6), "Cfa": (GREEN, 0.75), "Cfb": (TEAL, 0.45),
    "Df": (BLUE, 0.5), "Dw": (PURPLE, 0.55),
    "ET": (GRAY, 0.45), "EF": (GRAY, 0.15),
}
PLATES = {"divergent": (RED, 1.4, None), "convergent": (BLUE, 1.8, None), "transform": (GREEN, 1.4, (3, 2))}


def blend(rgb, a):
    """A color with alpha `a` over white paper, as a solid color."""
    return tuple(1 - a + a * v for v in rgb)


def load(path):
    with open(path, encoding="utf8") as f:
        return json.load(f)


def parts(geom, polygons=False):
    t, c = geom["type"], geom["coordinates"]
    if t == "LineString":
        return [c]
    if t in ("MultiLineString",):
        return c
    if t == "Polygon":
        return [c] if polygons else c
    if t == "MultiPolygon":
        return c if polygons else [r for p in c for r in p]
    return []


def dp(points, eps):
    """Douglas-Peucker, endpoints kept."""
    if len(points) < 3 or eps <= 0:
        return list(points)
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = points[a]
        bx, by = points[b]
        dx, dy = bx - ax, by - ay
        n = math.hypot(dx, dy)
        best, bi = -1.0, -1
        for i in range(a + 1, b):
            px, py = points[i]
            d = math.hypot(px - ax, py - ay) if n == 0 else abs(dy * px - dx * py + bx * ay - by * ax) / n
            if d > best:
                best, bi = d, i
        if best > eps:
            keep[bi] = True
            stack += [(a, bi), (bi, b)]
    return [p for p, k in zip(points, keep) if k]


def raw_lines(name, eps):
    out = []
    for f in load(os.path.join(RAW, name))["features"]:
        for line in parts(f["geometry"]):
            s = dp(line, eps)
            if len(s) >= 2:
                out.append(s)
    return out


def raw_polygons(name, eps):
    out = []
    for f in load(os.path.join(RAW, name))["features"]:
        for poly in parts(f["geometry"], polygons=True):
            rings = [r for r in (dp(r, eps) for r in poly) if len(r) >= 4]
            if rings:
                out.append(rings)
    return out


def densify(line, step=1.0):
    out = [line[0]]
    for a, b in zip(line, line[1:]):
        n = max(1, int(math.ceil(max(abs(b[0] - a[0]), abs(b[1] - a[1])) / step)))
        for i in range(1, n + 1):
            t = i / n
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


# --- Robinson ---------------------------------------------------------------

RX = [1.0000, 0.9986, 0.9954, 0.9900, 0.9822, 0.9730, 0.9600, 0.9427, 0.9216, 0.8962,
      0.8679, 0.8350, 0.7986, 0.7597, 0.7186, 0.6732, 0.6213, 0.5722, 0.5322]
RY = [0.0000, 0.0620, 0.1240, 0.1860, 0.2480, 0.3100, 0.3720, 0.4340, 0.4958, 0.5571,
      0.6176, 0.6769, 0.7346, 0.7903, 0.8435, 0.8936, 0.9394, 0.9761, 1.0000]


def robinson_factors(lat):
    f = min(max(abs(lat), 0), 90) / 5
    i = min(int(f), 17)
    t = f - i

    def spline(v):
        p0 = v[i - 1] if i > 0 else 2 * v[0] - v[1]
        p1, p2 = v[i], v[i + 1]
        p3 = v[i + 2] if i + 2 < len(v) else 2 * v[i + 1] - v[i]
        return 0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                      + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)
    return spline(RX), spline(RY)


HALF_W, HALF_H = 0.8487 * math.pi, 1.3523


class World:
    """Robinson, central meridian CM, fitted into the page's map box."""

    def __init__(self, box):
        x0, y0, x1, y1 = box
        self.s = min((x1 - x0) / (2 * HALF_W), (y1 - y0) / (2 * HALF_H))
        self.cx, self.cy = (x0 + x1) / 2, (y0 + y1) / 2
        self.box = (self.cx - HALF_W * self.s, self.cy - HALF_H * self.s,
                    self.cx + HALF_W * self.s, self.cy + HALF_H * self.s)

    def xy(self, lon, lat, k=0):
        lam = math.radians(lon - CM + 360 * k)
        fx, fy = robinson_factors(lat)
        return (self.cx + self.s * 0.8487 * fx * lam,
                self.cy + self.s * 1.3523 * fy * (1 if lat >= 0 else -1))

    @staticmethod
    def copies(lo, hi):
        return [k for k in (-1, 0, 1, 2) if hi - CM + 360 * k >= -180 and lo - CM + 360 * k <= 180]

    def lines(self, lines, step=None):
        out = []
        for line in lines:
            if len(line) < 2:
                continue
            pts = densify(line, step) if step else line
            lons = [p[0] for p in pts]
            for k in self.copies(min(lons), max(lons)):
                out.append([self.xy(p[0], p[1], k) for p in pts])
        return out

    def polygons(self, polys, step=None):
        out = []
        for rings in polys:
            dense = [densify(r, step) if step else r for r in rings]
            lons = [p[0] for p in dense[0]]
            for k in self.copies(min(lons), max(lons)):
                out.append([[self.xy(p[0], p[1], k) for p in r] for r in dense])
        return out

    def points(self, lon, lat):
        return [self.xy(lon, lat, k) for k in self.copies(lon, lon)]

    def outline(self):
        ring = [self.xy(CM + 180 - 1e-9, lat) for lat in range(-90, 91)]
        ring += [self.xy(CM - 180 + 1e-9, lat) for lat in range(90, -91, -1)]
        return ring

    def per_degree(self):
        return self.s * 1.3523 * 0.0124


class Region:
    """A simple equidistant cylindrical map of a region, x scaled by
    cos(mid latitude), fitted into the box."""

    def __init__(self, box, lon0, lon1, lat0, lat1):
        self.lon0, self.lon1, self.lat0, self.lat1 = lon0, lon1, lat0, lat1
        self.k = math.cos(math.radians((lat0 + lat1) / 2))
        x0, y0, x1, y1 = box
        w, h = (lon1 - lon0) * self.k, lat1 - lat0
        self.s = min((x1 - x0) / w, (y1 - y0) / h)
        self.ox = (x0 + x1) / 2 - w * self.s / 2
        self.oy = (y0 + y1) / 2 - h * self.s / 2
        self.box = (self.ox, self.oy, self.ox + w * self.s, self.oy + h * self.s)

    def xy(self, lon, lat):
        return (self.ox + (lon - self.lon0) * self.k * self.s, self.oy + (lat - self.lat0) * self.s)

    def lines(self, lines, step=None):
        out = []
        for line in lines:
            pts = densify(line, step) if step else line
            if any(self.lon0 - 5 <= p[0] <= self.lon1 + 5 and self.lat0 - 5 <= p[1] <= self.lat1 + 5 for p in pts):
                out.append([self.xy(*p) for p in pts])
        return out

    def polygons(self, polys):
        return [[[self.xy(*p) for p in r] for r in rings] for rings in polys
                if any(self.lon0 - 5 <= p[0] <= self.lon1 + 5 and self.lat0 - 5 <= p[1] <= self.lat1 + 5
                       for p in rings[0])]

    def outline(self):
        x0, y0, x1, y1 = self.box
        return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


# --- Drawing ----------------------------------------------------------------

def path_of(c, polylines, closed=False):
    p = c.beginPath()
    for line in polylines:
        if len(line) < 2:
            continue
        p.moveTo(*line[0])
        for v in line[1:]:
            p.lineTo(*v)
        if closed:
            p.close()
    return p


def stroke(c, polylines, color, width, dash=None, cap=1, alpha=None):
    c.saveState()
    c.setStrokeColorRGB(*color)
    if alpha is not None:
        c.setStrokeAlpha(alpha)
    c.setLineWidth(width)
    c.setLineCap(cap)
    c.setLineJoin(1)
    if dash:
        c.setDash(*dash)
    c.drawPath(path_of(c, polylines), stroke=1, fill=0)
    c.restoreState()


def fill(c, polygons, color, alpha=None, even_odd=True):
    c.saveState()
    c.setFillColorRGB(*color)
    if alpha is not None:
        c.setFillAlpha(alpha)
    p = path_of(c, [r for rings in polygons for r in rings], closed=True)
    c.drawPath(p, stroke=0, fill=1, fillMode=0 if even_odd else 1)
    c.restoreState()


def clip(c, rings, even_odd=True):
    c.clipPath(path_of(c, rings, closed=True), stroke=0, fill=0, fillMode=0 if even_odd else 1)


def label(c, text, x, y, size=7, color=INK, bold=False, anchor="middle"):
    font = "UDB" if bold else "UD"
    w = pdfmetrics.stringWidth(text, font, size)
    x = x - w / 2 if anchor == "middle" else x
    # A white outline first, then the text. The render mode is part of the
    # graphics state, so each pass is saved and restored: otherwise the
    # outline mode would carry on into every later text.
    for mode, col in ((1, WHITE), (0, color)):
        c.saveState()
        c.setStrokeColorRGB(*WHITE)
        c.setLineWidth(1.8)
        c.setLineJoin(1)
        c.setFillColorRGB(*col)
        t = c.beginText(x, y - size * 0.35)
        t.setFont(font, size)
        t.setTextRenderMode(mode)
        t.textOut(text)
        c.drawText(t)
        c.restoreState()


def arrow(c, line, color, width, head):
    if len(line) < 2:
        return
    tip = line[-1]
    back = line[-2]
    for p in reversed(line[:-1]):
        if math.hypot(tip[0] - p[0], tip[1] - p[1]) >= head:
            back = p
            break
    d = math.hypot(tip[0] - back[0], tip[1] - back[1])
    if d == 0:
        return
    ux, uy = (tip[0] - back[0]) / d, (tip[1] - back[1]) / d
    base = (tip[0] - ux * head, tip[1] - uy * head)
    body = [p for p in line if math.hypot(p[0] - tip[0], p[1] - tip[1]) >= head * 0.8] + [base]
    stroke(c, [body], color, width)
    c.saveState()
    c.setFillColorRGB(*color)
    p = c.beginPath()
    p.moveTo(*tip)
    p.lineTo(base[0] - uy * head * 0.5, base[1] + ux * head * 0.5)
    p.lineTo(base[0] + uy * head * 0.5, base[1] - ux * head * 0.5)
    p.close()
    c.drawPath(p, stroke=0, fill=1)
    c.restoreState()


def inside(world, x, y):
    x0, y0, x1, y1 = world.box
    return x0 + 4 <= x <= x1 - 4 and y0 + 4 <= y <= y1 - 4


class Labels:
    """Places a page's labels, most important first: each tries a few
    spots around its point and is left out if none is free or inside the
    map's outline."""

    def __init__(self, c, world):
        self.c, self.w, self.items = c, world, []

    def add(self, text, lon, lat, size=7, color=INK, bold=False, dy=0, priority=0):
        for x, y in self.w.points(lon, lat):
            self.items.append((priority, text, x, y + dy, size, color, bold))

    def _fits(self, x0, y0, x1, y1):
        # Every corner inside the outline (|λ| ≤ 180° at that height).
        for x, y in ((x0, y0), (x1, y0), (x0, y1), (x1, y1)):
            lat_fraction = (y - self.w.cy) / (self.w.s * HALF_H)
            if abs(lat_fraction) > 0.97:
                return False
            lat = lat_of(lat_fraction)
            half = self.w.s * 0.8487 * robinson_factors(lat)[0] * math.pi
            if abs(x - self.w.cx) > half - 2:
                return False
        return True

    def draw(self, taken=None):
        taken = list(taken or [])
        for _, text, x, y, size, color, bold in sorted(self.items, key=lambda i: -i[0]):
            font = "UDB" if bold else "UD"
            w, h = pdfmetrics.stringWidth(text, font, size) + 3, size + 2
            for ox, oy in ((0, 0), (0, h * 0.9), (0, -h * 0.9), (w / 2 + 4, 0), (-w / 2 - 4, 0)):
                r = (x + ox - w / 2, y + oy - h / 2, x + ox + w / 2, y + oy + h / 2)
                if not self._fits(*r):
                    continue
                if any(r[0] < t[2] and t[0] < r[2] and r[1] < t[3] and t[1] < r[3] for t in taken):
                    continue
                taken.append(r)
                label(self.c, text, x + ox, y + oy, size, color, bold)
                break


def lat_of(fraction):
    """Latitude whose Robinson height is `fraction` of the pole's."""
    lo, hi = 0.0, 90.0
    target = abs(fraction)
    for _ in range(30):
        mid = (lo + hi) / 2
        if robinson_factors(mid)[1] < target:
            lo = mid
        else:
            hi = mid
    return lo if fraction >= 0 else -lo


# --- Data -------------------------------------------------------------------

print("loading data...")
SCH = load(os.path.join(DATA, "schematics.json"))
BASE = {
    "coast": raw_lines("ne_50m_coastline.geojson", 0.03),
    "borders": raw_lines("ne_50m_admin_0_boundary_lines_land.geojson", 0.03),
    "lakes": raw_polygons("ne_50m_lakes.geojson", 0.03),
    "land": raw_polygons("ne_50m_land.geojson", 0.03),
}
PLATE_LINES = {}
for f in load(os.path.join(DATA, "plates.geojson"))["features"]:
    PLATE_LINES.setdefault(f["properties"]["kind"], []).extend(parts(f["geometry"]))
KOPPEN_POLYS = {}
for f in load(os.path.join(DATA, "koppen.geojson"))["features"]:
    KOPPEN_POLYS.setdefault(f["properties"]["class"], []).extend(parts(f["geometry"], polygons=True))
RIVERS = [(f["properties"]["name"], parts(f["geometry"])) for f in load(os.path.join(DATA, "rivers.geojson"))["features"]]

MAP_BOX = (24, 112, PAGE_W - 24, PAGE_H - 44)
W = World(MAP_BOX)
OUTLINE = W.outline()
FORMS = set()


def graticule():
    lines = []
    for k in range(-6, 7):
        lon = CM + 30 * k
        lines.append([(lon, -90), (lon, 90)])
    for lat in (-60, -30, 30, 60):
        lines.append([(-180, lat), (180, lat)])
    return lines


def base_form(c, borders=True):
    """The white map (graticule, borders, lakes, coastline, outline), drawn
    once into the PDF and reused on every page."""
    name = "base_borders" if borders else "base_coast"
    if name in FORMS:
        return name
    c.beginForm(name)
    c.saveState()
    clip(c, [OUTLINE])
    stroke(c, W.lines(graticule(), step=2), GRID, 0.35)
    stroke(c, W.lines([[(-180, la), (180, la)] for la in (23.44, -23.44, 66.56, -66.56)], step=2),
           GRID, 0.4, dash=(2, 2))
    stroke(c, W.lines([[(-180, 0), (180, 0)]], step=2), (0.6, 0.6, 0.63), 0.5)
    if borders:
        stroke(c, W.lines(BASE["borders"]), BORDER, 0.3)
    stroke(c, [r for rings in W.polygons(BASE["lakes"]) for r in rings], INK, 0.3)
    stroke(c, W.lines(BASE["coast"]), INK, 0.45)
    c.restoreState()
    stroke(c, [OUTLINE + [OUTLINE[0]]], INK, 0.7)
    c.endForm()
    FORMS.add(name)
    return name


def page_start(c, title, subtitle=None):
    c.setFillColorRGB(*WHITE)
    c.rect(0, 0, PAGE_W, PAGE_H, stroke=0, fill=1)
    c.setFillColorRGB(*INK)
    c.setFont("UDB", 15)
    c.drawString(28, PAGE_H - 30, title)
    if subtitle:
        c.setFont("UD", 9)
        c.setFillColorRGB(0.45, 0.45, 0.48)
        c.drawString(28 + pdfmetrics.stringWidth(title, "UDB", 15) + 10, PAGE_H - 30, subtitle)
    c.bookmarkPage(title)
    c.addOutlineEntry(title, title, level=0)


def footer(c, text):
    c.setFont("UD", 6)
    c.setFillColorRGB(0.55, 0.55, 0.58)
    c.drawRightString(PAGE_W - 24, 12, text)


NE = "地図データ: Natural Earth"


class Legend:
    """Legend entries laid out left to right in the strip under the map."""

    def __init__(self, c, top=100, left=40, row=14, col=190):
        self.c, self.x, self.y, self.top, self.left, self.row, self.col = c, left, top, top, left, row, col

    def _next(self):
        x, y = self.x, self.y
        self.y -= self.row
        if self.y < 22:
            self.y = self.top
            self.x += self.col
        return x, y

    def entry(self, text, draw):
        x, y = self._next()
        draw(self.c, x, y)
        self.c.setFont("UD", 8)
        self.c.setFillColorRGB(*INK)
        self.c.drawString(x + 26, y - 3, text)

    def line(self, text, color, width, dash=None):
        self.entry(text, lambda c, x, y: stroke(c, [[(x, y), (x + 20, y)]], color, width, dash=dash, cap=0))

    def box(self, text, color, outline=False):
        def d(c, x, y):
            c.saveState()
            c.setFillColorRGB(*color)
            c.setStrokeColorRGB(*INK)
            c.setLineWidth(0.4)
            c.rect(x + 2, y - 5, 16, 10, stroke=1 if outline else 0, fill=0 if outline else 1)
            c.restoreState()
        self.entry(text, d)

    def arrow(self, text, color, width=1.4):
        self.entry(text, lambda c, x, y: arrow(c, [(x, y), (x + 20, y)], color, width, 6))


# --- Pages ------------------------------------------------------------------

def page_blank(c, borders=True):
    page_start(c, "白地図" if borders else "白地図（海岸線のみ）", "ロビンソン図法・経緯線30°ごと")
    c.doForm(base_form(c, borders))
    lg = Legend(c)
    lg.line("赤道", (0.6, 0.6, 0.63), 0.5)
    lg.line("回帰線・極圏", GRID, 0.6, dash=(2, 2))
    if borders:
        lg.line("国境", BORDER, 0.6)
    footer(c, NE)
    c.showPage()


def page_plates(c, names):
    page_start(c, "プレート境界" + ("" if names else "（書き込み用）"))
    c.doForm(base_form(c))
    c.saveState()
    clip(c, [OUTLINE])
    for kind, (color, width, dash) in PLATES.items():
        stroke(c, W.lines(PLATE_LINES.get(kind, [])), color, width, dash=dash)
    c.restoreState()
    if names:
        lb = Labels(c, W)
        for p in SCH["plateNames"]:
            lb.add(p["name"], *p["at"], size=7.5, color=(0.35, 0.35, 0.38), bold=True)
        lb.draw()
    lg = Legend(c, col=260)
    for k in SCH["plateKinds"]:
        color, width, dash = PLATES[k["kind"]]
        lg.line(f"{k['name']}（{k['examples']}）", color, width, dash)
    footer(c, NE + "／プレート境界: PB2002 (Bird, 2003, ODC-BY)")
    c.showPage()


def page_koppen(c, colored):
    page_start(c, "ケッペンの気候区分" + ("" if colored else "（書き込み用）"),
               "1951〜2000年の平年値を高校の区分に簡略化")
    c.saveState()
    clip(c, [OUTLINE])
    clip(c, [r for rings in W.polygons(BASE["land"]) for r in rings])
    for code, polys in KOPPEN_POLYS.items():
        projected = W.polygons(polys)
        if colored:
            color, a = KOPPEN[code]
            fill(c, projected, blend(color, a))
        else:
            stroke(c, [r for rings in projected for r in rings], (0.4, 0.4, 0.43), 0.4)
    fill(c, W.polygons(BASE["lakes"]), WHITE)
    c.restoreState()
    # The blank one leaves out borders, so only climate boundaries show.
    c.doForm(base_form(c, borders=colored))
    lg = Legend(c, top=100, row=11.5, col=158)
    for k in SCH["koppenClasses"]:
        code = k["code"]
        if colored:
            color, a = KOPPEN[code]
            lg.box(f"{code}  {k['name']}", blend(color, a))
        else:
            lg.box(f"{code}  {k['name']}", WHITE, outline=True)
    footer(c, NE + "／気候区分: Kottek et al. (2006) の0.5°格子を簡略化")
    c.showPage()


def page_currents(c, names):
    page_start(c, "おもな海流" + ("" if names else "（書き込み用）"), "教科書レベルの模式図")
    c.doForm(base_form(c))
    c.saveState()
    clip(c, [OUTLINE])
    for cur in SCH["currents"]:
        for line in W.lines([cur["path"]], step=1):
            arrow(c, line, RED if cur["warm"] else BLUE, 1.6, 7)
    c.restoreState()
    if names:
        lb = Labels(c, W)
        seen = set()
        for cur in SCH["currents"]:
            # The circumpolar current is drawn in four pieces; name it once.
            if cur["name"] in seen and cur["name"].startswith("南極環流"):
                continue
            seen.add(cur["name"])
            lb.add(cur["name"], *cur["label"], size=6.5, color=RED if cur["warm"] else BLUE, dy=7)
        lb.draw()
    lg = Legend(c)
    lg.arrow("暖流", RED)
    lg.arrow("寒流", BLUE)
    footer(c, NE + "／海流は模式図")
    c.showPage()


def page_winds(c, season, names):
    s = SCH["seasons"][season]
    page_start(c, f"恒常風と気圧帯（{s['name']}）" + ("" if names else "（書き込み用）"), "教科書レベルの模式図")
    c.saveState()
    clip(c, [OUTLINE])
    for b in s["belts"]:
        fill(c, W.polygons([[b["ring"]]], step=2), ORANGE if b["low"] else BLUE, alpha=0.2 if b["low"] else 0.13)
    c.restoreState()
    c.doForm(base_form(c))
    c.saveState()
    clip(c, [OUTLINE])
    for w in s["winds"]:
        monsoon = w["kind"] == "monsoon"
        for line in W.lines([[w["from"], w["to"]]], step=1):
            arrow(c, line, PURPLE if monsoon else (0.35, 0.35, 0.38), 1.7 if monsoon else 1.1, 6)
    c.restoreState()
    if names:
        lb = Labels(c, W)
        for b in s["belts"]:
            for lon, lat in b["labels"]:
                lb.add(b["name"], lon, lat, size=7, color=ORANGE if b["low"] else BLUE, bold=True, priority=1)
        for wl in s["windLabels"]:
            lb.add(wl["name"], *wl["at"], size=6.5,
                   color=PURPLE if wl["kind"] == "monsoon" else (0.3, 0.3, 0.33))
        lb.draw()
    lg = Legend(c)
    lg.box("低圧帯", blend(ORANGE, 0.2))
    lg.box("高圧帯", blend(BLUE, 0.13))
    lg.arrow("恒常風", (0.35, 0.35, 0.38), 1.1)
    lg.arrow("季節風", PURPLE, 1.7)
    footer(c, NE + "／風・気圧帯は模式図")
    c.showPage()


def page_landforms(c, names):
    page_start(c, "おもな山脈・河川と造山帯" + ("" if names else "（書き込み用）"), "造山帯・山脈は模式図")
    c.saveState()
    clip(c, [OUTLINE])
    per_deg = W.per_degree()
    for o in SCH["orogeny"]:
        stroke(c, W.lines([o["path"]], step=1), ORANGE if o["young"] else GREEN,
               max(o["width"] * per_deg, 4), alpha=0.3)
    c.restoreState()
    c.doForm(base_form(c))
    c.saveState()
    clip(c, [OUTLINE])
    for _, lines in RIVERS:
        stroke(c, W.lines(lines), BLUE, 0.9)
    for r in SCH["ranges"]:
        stroke(c, W.lines([r["path"]], step=1), BROWN, 2.2)
    c.restoreState()
    if names:
        lb = Labels(c, W)
        for r in SCH["ranges"]:
            lb.add(r["name"], *r["label"], size=7, color=BROWN, bold=True, dy=-8, priority=1)
        for name, lines in RIVERS:
            longest = max(lines, key=len)
            lb.add(name, *longest[len(longest) // 2], size=6.5, color=BLUE, dy=6)
        lb.draw()
    lg = Legend(c)
    lg.box(SCH["orogenyNames"]["young"], blend(ORANGE, 0.3))
    lg.box(SCH["orogenyNames"]["old"], blend(GREEN, 0.3))
    lg.line("おもな山脈", BROWN, 2.2)
    lg.line("おもな河川", BLUE, 0.9)
    footer(c, NE + "／造山帯・山脈は模式図")
    c.showPage()


def page_japan(c):
    page_start(c, "日本とその周辺", "経緯線5°ごと")
    r = Region((40, 30, PAGE_W - 40, PAGE_H - 44), 120, 155, 20, 48)
    coast = raw_lines("ne_10m_coastline.geojson", 0.005)
    borders = raw_lines("ne_10m_admin_0_boundary_lines_land.geojson", 0.005)
    lakes = raw_polygons("ne_10m_lakes.geojson", 0.005)
    c.saveState()
    clip(c, [r.outline()])
    grat = [[(lon, 15), (lon, 55)] for lon in range(120, 156, 5)]
    grat += [[(110, lat), (165, lat)] for lat in range(20, 49, 5)]
    stroke(c, r.lines(grat, step=1), GRID, 0.4)
    stroke(c, r.lines(borders), BORDER, 0.4)
    stroke(c, [ring for rings in r.polygons(lakes) for ring in rings], INK, 0.35)
    stroke(c, r.lines(coast), INK, 0.5)
    c.restoreState()
    o = r.outline()
    stroke(c, [o + [o[0]]], INK, 0.7)
    c.setFont("UD", 7)
    c.setFillColorRGB(0.45, 0.45, 0.48)
    for lon in range(120, 156, 5):
        x, y = r.xy(lon, 20)
        c.drawCentredString(x, y - 10, f"{lon}°E")
    for lat in range(20, 49, 5):
        x, y = r.xy(120, lat)
        c.drawRightString(x - 3, y - 2.5, f"{lat}°N")
    footer(c, "地図データ: Natural Earth (1:10m)")
    c.showPage()


c = canvas.Canvas(OUT, pagesize=landscape(A4))
c.setTitle("白地図帳")
c.setAuthor("")
c.setSubject("高校地理の白地図（Goodnotes用）")
c.showOutline()
print("drawing pages...")
page_blank(c, borders=True)
page_blank(c, borders=False)
page_japan(c)
page_plates(c, names=True)
page_plates(c, names=False)
page_koppen(c, colored=True)
page_koppen(c, colored=False)
page_currents(c, names=True)
page_currents(c, names=False)
for season in ("january", "july"):
    page_winds(c, season, names=True)
for season in ("january", "july"):
    page_winds(c, season, names=False)
page_landforms(c, names=True)
page_landforms(c, names=False)
c.save()
print(f"{OUT}: {os.path.getsize(OUT) // 1024} KB")
