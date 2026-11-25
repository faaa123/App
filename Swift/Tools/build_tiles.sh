#!/bin/sh
# Builds Resources/Geo/world.pmtiles, the base map's vector tiles (what web
# maps draw from: one file of per-zoom tiles, simplified per zoom by
# tippecanoe). Run once, offline, in Docker; the output is committed.
#
#   docker run --rm -v <raw-dir>:/raw -v <Swift/Resources/Geo>:/out \
#     -v <Swift/Tools>:/tools ubuntu:24.04 sh /tools/build_tiles.sh
#
# <raw-dir> holds Natural Earth 1:10m (public domain), from
# github.com/nvkelso/natural-earth-vector/tree/master/geojson:
# ne_10m_ocean, ne_10m_coastline, ne_10m_admin_0_boundary_lines_land,
# ne_10m_lakes (.geojson).
set -eu
apt-get update -qq
apt-get install -y -qq --no-install-recommends build-essential git ca-certificates \
  libsqlite3-dev zlib1g-dev > /dev/null
git clone -q --depth 1 --branch 2.79.0 https://github.com/felt/tippecanoe.git /tmp/tippecanoe
make -s -C /tmp/tippecanoe -j"$(nproc)" tippecanoe > /dev/null

# Zooms 0-6 are enough: the map overzooms the z6 tiles, and 1:10m data has
# no more detail than a z6 tile holds. -X drops every attribute; -r1 keeps
# every feature at every zoom (nothing thinned out of a coastline).
/tmp/tippecanoe/tippecanoe -o /out/world.pmtiles --force -Z0 -z6 -X -r1 \
  --no-feature-limit --no-tile-size-limit \
  --attribution='<a href="https://www.naturalearthdata.com">Natural Earth</a>' \
  -L ocean:/raw/ne_10m_ocean.geojson \
  -L coastline:/raw/ne_10m_coastline.geojson \
  -L borders:/raw/ne_10m_admin_0_boundary_lines_land.geojson \
  -L lakes:/raw/ne_10m_lakes.geojson
ls -l /out/world.pmtiles
