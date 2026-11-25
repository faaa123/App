"""Builds the GeoJSON files bundled with the app (地図 tab).

Run once, offline; the outputs in ../Resources/Geo are committed and the app
never downloads anything.

    python -I -X utf8 build_geodata.py <raw-dir> <out-dir>

<raw-dir> must hold these downloads:

- Natural Earth 1:110m (public domain), from
  github.com/nvkelso/natural-earth-vector/tree/master/geojson:
  ne_110m_coastline, ne_110m_admin_0_boundary_lines_land, ne_110m_land,
  ne_110m_lakes (.geojson)
- Natural Earth 1:50m rivers (public domain): ne_50m_rivers_lake_centerlines
  (110m has too few rivers for a textbook map; the curated ones are
  simplified to 110m-like detail)
- PB2002 plate boundaries (Bird 2003, ODC-BY), steps file from
  github.com/fraxen/tectonicplates: GeoJSON/PB2002_steps.json
- Koppen-Geiger 1951-2000, 0.5 deg grid (Kottek et al. 2006), from
  koeppen-geiger.vu-wien.ac.at: Koeppen-Geiger-ASCII.zip, extracted to
  kg/Koeppen-Geiger-ASCII.txt

- Natural Earth 1:50m and 1:10m, for the detail shown when zooming in:
  ne_50m_coastline, ne_50m_admin_0_boundary_lines_land, ne_50m_land,
  ne_50m_lakes, ne_10m_coastline, ne_10m_admin_0_boundary_lines_land,
  ne_10m_lakes (.geojson)

Outputs: coastline, borders, land, lakes, rivers, plates, koppen (.geojson),
and the zoomed-in detail as .geobin (see GeoBinary.swift): coastline,
borders, lakes at 50m and 10m, and land at 50m.
"""

import json
import os
import sys
from collections import Counter, defaultdict, deque

import struct

import numpy as np

RAW, OUT = sys.argv[1], sys.argv[2]


def load(name):
    with open(os.path.join(RAW, name), encoding="utf8") as f:
        return json.load(f)


def save(name, features):
    path = os.path.join(OUT, name + ".geojson")
    with open(path, "w", encoding="utf8") as f:
        json.dump({"type": "FeatureCollection", "features": features}, f,
                  ensure_ascii=False, separators=(",", ":"))
    print(f"{name}: {len(features)} features, {os.path.getsize(path) // 1024} KB")


def rnd(p, nd=2):
    return [round(p[0], nd), round(p[1], nd)]


def dp(points, eps):
    """Douglas-Peucker on an open polyline; endpoints are kept."""
    if len(points) < 3:
        return list(points)
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = points[a]
        bx, by = points[b]
        dx, dy = bx - ax, by - ay
        norm = (dx * dx + dy * dy) ** 0.5
        best, bi = -1.0, -1
        for i in range(a + 1, b):
            px, py = points[i]
            if norm == 0:
                d = ((px - ax) ** 2 + (py - ay) ** 2) ** 0.5
            else:
                d = abs(dy * px - dx * py + bx * ay - by * ax) / norm
            # Ties break on the coordinates, so the same chain simplifies the
            # same way in both directions (shared Koppen borders stay shared).
            if d > best + 1e-12 or (abs(d - best) <= 1e-12 and tuple(points[i]) < tuple(points[bi])):
                best, bi = d, i
        if best > eps:
            keep[bi] = True
            stack += [(a, bi), (bi, b)]
    return [p for p, k in zip(points, keep) if k]


def lines_of(geom):
    if geom["type"] == "LineString":
        return [geom["coordinates"]]
    if geom["type"] == "MultiLineString":
        return geom["coordinates"]
    return []


# --- Base map -------------------------------------------------------------

def base_lines(src, out):
    feats = []
    for f in load(src)["features"]:
        for line in lines_of(f["geometry"]):
            feats.append({"type": "Feature", "properties": {},
                          "geometry": {"type": "LineString",
                                       "coordinates": [rnd(p) for p in line]}})
    save(out, feats)


def base_polygons(src, out):
    feats = []
    for f in load(src)["features"]:
        g = f["geometry"]
        polys = [g["coordinates"]] if g["type"] == "Polygon" else g["coordinates"]
        for poly in polys:
            feats.append({"type": "Feature", "properties": {},
                          "geometry": {"type": "Polygon",
                                       "coordinates": [[rnd(p) for p in r] for r in poly]}})
    save(out, feats)


# --- Detail for zooming in -------------------------------------------------

def save_bin(name, features):
    """features: list of parts (lists of [lon, lat]). Format: b"GEOB",
    u32 feature count; per feature u32 part count; per part u32 point count
    and float32 lon, lat pairs. Little endian."""
    path = os.path.join(OUT, name + ".geobin")
    points = 0
    with open(path, "wb") as f:
        f.write(b"GEOB")
        f.write(struct.pack("<I", len(features)))
        for parts in features:
            f.write(struct.pack("<I", len(parts)))
            for part in parts:
                f.write(struct.pack("<I", len(part)))
                f.write(struct.pack(f"<{2 * len(part)}f", *[c for p in part for c in p]))
                points += len(part)
    print(f"{name}: {len(features)} features, {points} points, {os.path.getsize(path) // 1024} KB")


def detail_lines(src, out, eps):
    feats = []
    for f in load(src)["features"]:
        for line in lines_of(f["geometry"]):
            simp = dp(line, eps)
            if len(simp) >= 2:
                feats.append([simp])
    save_bin(out, feats)


def detail_polygons(src, out, eps):
    """One feature per polygon (outer ring and its holes kept together)."""
    feats = []
    for f in load(src)["features"]:
        g = f["geometry"]
        polys = [g["coordinates"]] if g["type"] == "Polygon" else g["coordinates"]
        for poly in polys:
            rings = [r for r in (dp(r, eps) for r in poly) if len(r) >= 4]
            if rings and len(rings[0]) == len(dp(poly[0], eps)):
                feats.append(rings)
    save_bin(out, feats)


# --- Rivers ---------------------------------------------------------------

RIVERS = {
    "ナイル川": ["Nile", "Albert Nile", "Victoria Nile", "Bahr el Jebel", "El Bahr el Abyad",
              "Damietta Branch", "Rosetta Branch"],
    "コンゴ川": ["Congo", "Lualaba"],
    "ニジェール川": ["Niger"],
    "ザンベジ川": ["Zambezi"],
    "オレンジ川": ["Orange"],
    "アマゾン川": ["Amazonas", "Ucayali"],
    "パラナ川": ["Paraná"],
    "オリノコ川": ["Orinoco"],
    "ミシシッピ川": ["Mississippi"],
    "ミズーリ川": ["Missouri"],
    "セントローレンス川": ["St. Lawrence"],
    "マッケンジー川": ["Mackenzie", "Slave"],
    "ユーコン川": ["Yukon"],
    "コロラド川": ["Colorado"],
    "コロンビア川": ["Columbia"],
    "リオグランデ川": ["Rio Grande"],
    "ライン川": ["Rhine", "Rhein", "Rhin"],
    "ドナウ川": ["Danube", "Donau", "Borcea", "Bratul Chillia", "Bratul Sfintu Gheorghe", "Bratul Sulina"],
    "ヴォルガ川": ["Volga"],
    "オビ川": ["Ob", "Irtysh", "Ertis", "Ertix"],
    "エニセイ川": ["Yenisey", "Verkhniy Yenisey"],
    "レナ川": ["Lena"],
    "アムール川": ["Amur", "Heilong Jiang", "Argun’"],
    "黄河": ["Huang"],
    "長江": ["Chang Jiang", "Yangtze", "Jinsha", "Tongtian", "Tuotuo"],
    "メコン川": ["Mekong", "Lancang"],
    "ガンジス川": ["Ganges"],
    "インダス川": ["Indus"],
    "ブラマプトラ川": ["Brahmaputra", "Yarlung", "Dihang"],
    "エーヤワディー川": ["Ayeyarwady", "Irrawaddy Delta"],
    "ユーフラテス川": ["Euphrates", "Firat", "Al Furat", "Shatt al Arab"],
    "ティグリス川": ["Tigris", "Dicle"],
    "マリー川": ["Murray", "Darling", "Barwon"],
}


def rivers():
    alias = {en: ja for ja, ens in RIVERS.items() for en in ens}
    groups = defaultdict(list)
    for f in load("ne_50m_rivers_lake_centerlines.geojson")["features"]:
        ja = alias.get(f["properties"].get("name"))
        if ja:
            groups[ja] += lines_of(f["geometry"])
    feats = []
    for ja in RIVERS:
        lines = [[rnd(p) for p in dp(l, 0.08)] for l in groups.get(ja, [])]
        lines = [l for l in lines if len(l) >= 2]
        if not lines:
            print("missing river", ja)
            continue
        feats.append({"type": "Feature", "properties": {"name": ja},
                      "geometry": {"type": "MultiLineString", "coordinates": lines}})
    save("rivers", feats)


# --- Plate boundaries -----------------------------------------------------

PLATE_KIND = {"OSR": "divergent", "CRB": "divergent",
              "SUB": "convergent", "OCB": "convergent", "CCB": "convergent",
              "OTF": "transform", "CTF": "transform"}


def plates():
    steps = sorted(load("PB2002_steps.json")["features"], key=lambda f: f["properties"]["SEQNUM"])
    runs = []  # [kind, points]
    for f in steps:
        kind = PLATE_KIND[f["properties"]["STEPCLASS"]]
        pts = f["geometry"]["coordinates"]
        a, b = pts[0], pts[-1]
        if runs and runs[-1][0] == kind:
            last = runs[-1][1][-1]
            if abs(last[0] - a[0]) < 1e-3 and abs(last[1] - a[1]) < 1e-3:
                runs[-1][1].append(b)
                continue
        runs.append([kind, [a, b]])
    # Chain runs of one kind end to end wherever exactly two of them meet.
    merged = []
    for kind in ("divergent", "convergent", "transform"):
        lines = [pts for k, pts in runs if k == kind]
        key = lambda p: (round(p[0], 2), round(p[1], 2))
        while True:
            ends = defaultdict(list)
            for i, l in enumerate(lines):
                ends[key(l[0])].append(i)
                ends[key(l[-1])].append(i)
            joined = False
            for k, ids in ends.items():
                if len(ids) == 2 and ids[0] != ids[1]:
                    a, b = lines[ids[0]], lines[ids[1]]
                    if key(a[0]) == k:
                        a = a[::-1]
                    if key(b[-1]) == k:
                        b = b[::-1]
                    lines = [l for i, l in enumerate(lines) if i not in ids] + [a + b[1:]]
                    joined = True
                    break
            if not joined:
                break
        merged += [(kind, l) for l in lines]
    feats = []
    for kind in ("divergent", "convergent", "transform"):
        # The steps are ~1 deg apart already; a light pass merges straight runs.
        lines = [[rnd(p) for p in dp(pts, 0.05)] for k, pts in merged if k == kind]
        feats.append({"type": "Feature", "properties": {"kind": kind},
                      "geometry": {"type": "MultiLineString", "coordinates": lines}})
    save("plates", feats)


# --- Koppen ---------------------------------------------------------------

# High-school groups: As -> Aw, Ds -> Df, Cfc -> Cfb, Csc/Cwc -> Cs/Cw.
KOPPEN = ["Af", "Am", "Aw", "BS", "BW", "Cs", "Cw", "Cfa", "Cfb", "Df", "Dw", "ET", "EF"]


def koppen_group(c):
    if c in ("Af", "Am", "ET", "EF", "Cfa"):
        return c
    if c in ("Aw", "As"):
        return "Aw"
    if c.startswith("BW"):
        return "BW"
    if c.startswith("BS"):
        return "BS"
    if c.startswith("Cs"):
        return "Cs"
    if c.startswith("Cw"):
        return "Cw"
    if c in ("Cfb", "Cfc"):
        return "Cfb"
    if c.startswith("Dw"):
        return "Dw"
    if c.startswith("Df") or c.startswith("Ds"):
        return "Df"
    raise ValueError(c)


def koppen():
    H, W = 360, 720  # rows from 90N down, cols from 180W
    grid = np.full((H, W), -1, dtype=np.int16)
    with open(os.path.join(RAW, "kg", "Koeppen-Geiger-ASCII.txt")) as f:
        next(f)
        for line in f:
            lat, lon, c = line.split()
            r = int((90 - float(lat)) / 0.5)
            col = int((float(lon) + 180) / 0.5)
            grid[r, col] = KOPPEN.index(koppen_group(c))

    def neighbors(r, c):
        for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            rr, cc = r + dr, (c + dc) % W
            if 0 <= rr < H:
                yield rr, cc

    # Fold small patches (< MIN cells) into their most common neighbour, so
    # the map reads like a textbook's and the file stays small.
    MIN = 10
    for _ in range(4):
        seen = np.zeros_like(grid, dtype=bool)
        changed = 0
        for r in range(H):
            for c in range(W):
                if seen[r, c] or grid[r, c] < 0:
                    continue
                k = grid[r, c]
                comp, q = [], deque([(r, c)])
                seen[r, c] = True
                border = Counter()
                while q:
                    cr, cc = q.popleft()
                    comp.append((cr, cc))
                    for nr, nc in neighbors(cr, cc):
                        if grid[nr, nc] == k:
                            if not seen[nr, nc]:
                                seen[nr, nc] = True
                                q.append((nr, nc))
                        elif grid[nr, nc] >= 0:
                            border[grid[nr, nc]] += 1
                if len(comp) < MIN and border:
                    nk = border.most_common(1)[0][0]
                    for cr, cc in comp:
                        grid[cr, cc] = nk
                    changed += 1
        if not changed:
            break

    # Grow the classes 3 cells (1.5 deg) into the sea: the app clips the fill
    # to the Natural Earth land, so the coast never shows a white gap.
    for _ in range(3):
        new = grid.copy()
        for r in range(H):
            for c in range(W):
                if grid[r, c] >= 0:
                    continue
                around = Counter(grid[nr, nc] for nr, nc in neighbors(r, c) if grid[nr, nc] >= 0)
                if around:
                    new[r, c] = around.most_common(1)[0][0]
        grid = new

    def cls(r, c):
        if r < 0 or r >= H or c < 0 or c >= W:
            return -1  # outside the map edge counts as sea
        return grid[r, c]

    # Directed boundary edges, class on the left (counter-clockwise rings in
    # lon/lat). Vertex (i, j) = lon -180 + 0.5 j, lat 90 - 0.5 i.
    feats = []
    for k in range(len(KOPPEN)):
        out_edges = defaultdict(list)  # start vertex -> [(end vertex, class on right)]
        for r in range(H):
            for c in range(W):
                if grid[r, c] != k:
                    continue
                # cell corners: top-left (r, c) ... going CCW in lon/lat
                # (lat grows upward, so CCW = TL -> BL -> BR -> TR).
                sides = [((r, c), (r + 1, c), cls(r, c - 1)),          # west, going south
                         ((r + 1, c), (r + 1, c + 1), cls(r + 1, c)),  # south, going east
                         ((r + 1, c + 1), (r, c + 1), cls(r, c + 1)),  # east, going north
                         ((r, c + 1), (r, c), cls(r - 1, c))]          # north, going west
                for a, b, other in sides:
                    if other != k:
                        out_edges[a].append((b, other))
        rings = []
        while out_edges:
            start = next(iter(out_edges))
            ring, other_side = [start], []
            cur, prev_dir = start, None
            while True:
                outs = out_edges[cur]
                if len(outs) == 1:
                    i = 0
                else:  # pinch vertex: take the sharpest left turn
                    def turn(o):
                        d = (o[0][0] - cur[0], o[0][1] - cur[1])
                        if prev_dir is None:
                            return 0
                        # in (row, col) space a left turn in lon/lat is ...
                        cross = prev_dir[0] * d[1] - prev_dir[1] * d[0]
                        return -cross
                    i = min(range(len(outs)), key=lambda j: turn(outs[j]))
                nxt, other = outs.pop(i)
                if not outs:
                    del out_edges[cur]
                prev_dir = (nxt[0] - cur[0], nxt[1] - cur[1])
                other_side.append(other)
                cur = nxt
                if cur == start:
                    break
                ring.append(cur)
            rings.append((ring, other_side))

        polys = []
        for ring, other_side in rings:
            n = len(ring)
            # Drop collinear vertices first (keep corners and junctions).
            pts = [(-180 + 0.5 * v[1], 90 - 0.5 * v[0]) for v in ring]
            # junction: the class across the border changes at this vertex
            junction = [other_side[i - 1] != other_side[i] for i in range(n)]
            anchors = [i for i in range(n) if junction[i]]
            if not anchors:
                a0 = min(range(n), key=lambda i: pts[i])
                far = max(range(n), key=lambda i: ((pts[i][0] - pts[a0][0]) ** 2 + (pts[i][1] - pts[a0][1]) ** 2, pts[i]))
                anchors = sorted({a0, far})
            simp = []
            for ai, a in enumerate(anchors):
                b = anchors[(ai + 1) % len(anchors)]
                idx = list(range(a, b + 1)) if b > a else list(range(a, n)) + list(range(0, b + 1))
                chain = dp([pts[i] for i in idx], 0.4)
                simp += chain[:-1]
            if len(simp) < 3:
                continue
            area = 0.5 * sum(simp[i - 1][0] * simp[i][1] - simp[i][0] * simp[i - 1][1] for i in range(len(simp)))
            ringc = [[round(x, 2), round(y, 2)] for x, y in simp]
            ringc.append(ringc[0])
            polys.append((area, ringc))

        outers = [p for p in polys if p[0] > 0]
        holes = [p for p in polys if p[0] < 0]

        def inside(pt, ring):
            x, y = pt
            hit = False
            for i in range(len(ring) - 1):
                (x1, y1), (x2, y2) = ring[i], ring[i + 1]
                if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
                    hit = not hit
            return hit

        multipoly = [[o[1]] for o in sorted(outers, key=lambda o: o[0])]
        for _, h in holes:
            # a hole vertex can sit on the outer ring; test the middle of an edge
            probe = ((h[0][0] + h[1][0]) / 2, (h[0][1] + h[1][1]) / 2)
            for poly in multipoly:  # smallest enclosing outer first
                if inside(probe, poly[0]):
                    poly.append(h)
                    break
        feats.append({"type": "Feature", "properties": {"class": KOPPEN[k]},
                      "geometry": {"type": "MultiPolygon", "coordinates": multipoly}})
    save("koppen", feats)


os.makedirs(OUT, exist_ok=True)
base_lines("ne_110m_coastline.geojson", "coastline")
base_lines("ne_110m_admin_0_boundary_lines_land.geojson", "borders")
base_polygons("ne_110m_land.geojson", "land")
base_polygons("ne_110m_lakes.geojson", "lakes")
detail_lines("ne_50m_coastline.geojson", "coastline_50m", 0.02)
detail_lines("ne_50m_admin_0_boundary_lines_land.geojson", "borders_50m", 0.02)
detail_polygons("ne_50m_land.geojson", "land_50m", 0.02)
detail_polygons("ne_50m_lakes.geojson", "lakes_50m", 0.02)
detail_lines("ne_10m_coastline.geojson", "coastline_10m", 0.004)
detail_lines("ne_10m_admin_0_boundary_lines_land.geojson", "borders_10m", 0.004)
detail_polygons("ne_10m_lakes.geojson", "lakes_10m", 0.004)
rivers()
plates()
koppen()
