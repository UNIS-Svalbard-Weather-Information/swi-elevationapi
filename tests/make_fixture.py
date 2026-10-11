"""Write a small synthetic DTM archive shaped like NP_S0_DTM20.zip.

usage: make_fixture.py <elevation> <out.zip> [--two-rasters]

The raster is a constant <elevation> field in EPSG:25833 (the NPI model's CRS) around
POINT, surrounded by nothing, so lookups inside it return <elevation> and anything
outside returns null.
"""
import sys
import tempfile
import zipfile
from pathlib import Path

import numpy as np
import rasterio
from pyproj import Transformer
from rasterio.transform import from_origin

POINT = (78.2232, 15.6261)  # lat, lon: Longyearbyen
NODATA = 3.4e38


def write_raster(path, elevation):
    x, y = Transformer.from_crs(4326, 25833, always_xy=True).transform(POINT[1], POINT[0])
    size = 200  # 200 x 200 cells of 20 m: +-2 km around the point
    data = np.full((size, size), elevation, dtype="float32")
    with rasterio.open(
        path, "w", driver="GTiff", height=size, width=size, count=1, dtype="float32",
        crs="EPSG:25833", transform=from_origin(x - 2000, y + 2000, 20, 20), nodata=NODATA,
    ) as dst:
        dst.write(data, 1)


def main():
    elevation, out = float(sys.argv[1]), Path(sys.argv[2])
    with tempfile.TemporaryDirectory() as tmp:
        tif = Path(tmp) / "S0_DTM20.tif"
        write_raster(tif, elevation)
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
            z.write(tif, "NP_S0_DTM20/S0_DTM20.tif")
            z.writestr("NP_S0_DTM20/_Lisens_License.txt", "CC BY 4.0\n")
            if "--two-rasters" in sys.argv:
                z.write(tif, "NP_S0_DTM20/other.tif")


main()
