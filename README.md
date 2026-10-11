# SWI Elevation API

**A regional elevation API for Svalbard, based on the Norwegian Polar Institute's Digital Terrain Model (NP DTM).**

This service runs [Open Topo Data](https://www.opentopodata.org) on the NPI S0 terrain model (20 m, EPSG:25833). The container image bundles the server, GDAL and a preparation script that downloads the DTM and converts it into a compressed, internally tiled GeoTIFF (as recommended in [opentopodata#114](https://github.com/ajnisbet/opentopodata/issues/114)).

It replaces the previous Open-Elevation based image.

---

## API

Open Topo Data API, dataset `svalbard`. See the [Open Topo Data API docs](https://www.opentopodata.org/api/) for all options (for example `interpolation`).

```bash
curl 'https://your-api-url/v1/svalbard?locations=78.2232,15.6261|78.2233,15.6262'
```

```json
{
  "results": [
    { "dataset": "svalbard", "elevation": 25.49, "location": { "lat": 78.2232, "lng": 15.6261 } },
    { "dataset": "svalbard", "elevation": 25.71, "location": { "lat": 78.2233, "lng": 15.6262 } }
  ],
  "status": "OK"
}
```

`elevation` is `null` outside the terrain model (sea). At most 100 locations per request.

### Paths

The container listens on port 5000 and serves every path both with and without an `/api` prefix, so it fits behind the `/oeapi/` -> `/api/` reverse proxy rewrite used in `swi-production-deployment`:

| Path | |
|---|---|
| `/v1/svalbard`, `/api/v1/svalbard` | Open Topo Data lookup |
| `/api/v1/lookup` | **Deprecated**, Open-Elevation compatible `GET` lookup, served by the `svalbard` dataset |

The legacy path exists for the migration only. It returns the Open Topo Data body: `results[].elevation` is unchanged, but `latitude` / `longitude` became `location.lat` / `location.lng`, and `POST` is no longer supported (405). It will be removed once the frontend uses `/v1/svalbard`.

---

## Data preparation

`/opt/prepare-data.sh` reads `datasets.json` and prepares each dataset in `/data/<name>/` (a volume). It is meant to run **once, before the server starts**, as a Compose [`pre_start`](https://docs.docker.com/reference/compose-file/services/#pre_start) step:

```yaml
services:
  elevation_api:
    image: ghcr.io/unis-svalbard-weather-information/swi-elevationapi:<version>
    volumes:
      - elevation_data:/data
    pre_start:
      - command: ["/opt/prepare-data.sh"]
        per_replica: false   # once for the whole service, not per replica
```

- A restart of the container does not run it again. It re-runs when the service is recreated (for example a new image tag).
- `per_replica: false` plus an exclusive `flock` on `/data/.prepare.lock` guarantee a single preparation even with several replicas sharing the volume. A second runner waits, sees the finished data and skips.
- Each dataset directory holds `dtm.tif` and a `.ready` file with the fingerprint (url, GDAL options, source file and the script's `PREP_VERSION`) and the upstream `ETag` / size / `Last-Modified`. The data is rebuilt when any of them changes, so a new upstream file, a changed option or a new `PREP_VERSION` is picked up automatically. If the upstream is unreachable, the existing data is kept.
- The new data is built in `/data/.tmp` and swapped in with a rename, so a crash never leaves a half-written dataset.

Run it by hand (a single step: `download` or `prepare`; `FORCE_REPREPARE=1` forces a rebuild, `PRUNE=1` removes datasets that are no longer in the manifest):

```bash
docker compose run --rm --no-deps --entrypoint /opt/prepare-data.sh elevation_api
```

(On Windows Git Bash prefix the command with `MSYS_NO_PATHCONV=1`.)

### Adding or changing a dataset

1. Add an entry to `datasets.json` (`name`, `url`, `creation_options`, optional `source_file` when the archive has several rasters).
2. Add the same `name` to `config.yaml` with `path: /data/<name>/`.
3. Release. The next deployment prepares only the new dataset.

For development a different archive can be used with `OTD_URL_<NAME>` (and `OTD_SOURCE_FILE_<NAME>`), for example the 50 m model:

```bash
OTD_URL_SVALBARD=https://public.data.npolar.no/kartdata/S0_Terrengmodell/Mosaikk/NP_S0_DTM50.zip docker compose up --build
```

The DTM is kept in its native CRS; Open Topo Data reprojects the query points.

---

## Local development

```bash
docker compose up --build        # prepares the data on first run (about 600 MB download), then serves :5000
curl 'http://localhost:5000/v1/svalbard?locations=78.2232,15.6261'
```

The image builds Open Topo Data from source at the release pinned in the `Dockerfile` (`OTD_REF`), because the project publishes no image. It runs on a current Python (see the `Dockerfile`) with the dependencies in `requirements.txt`; upstream's own pins only support Python 3.11. Open Topo Data 1.9.0 is not compatible with rasterio 1.4+ as is, so the `Dockerfile` patches the one affected line and fails the build when that line changes upstream.

### Tests

```bash
docker build -t swi-elevationapi:test .
docker run --rm --entrypoint bash -v "$PWD/tests:/tests:ro" swi-elevationapi:test /tests/run.sh
```

(On Windows Git Bash prefix `docker run` with `MSYS_NO_PATHCONV=1`.) `tests/run.sh` builds a tiny synthetic DTM, serves it from localhost and checks, with no network and in about a minute:

- the preparation: output format (256x256 tiles, ZSTD, EPSG:25833), skipping when up to date, rebuilding when the upstream file, the url or `FORCE_REPREPARE` changes, a single download with two concurrent runs, corrupt or ambiguous archives, and keeping the data when the upstream is unreachable;
- the API: `/v1/svalbard`, `/api/v1/svalbard` and the legacy `/api/v1/lookup` return the elevation, `null` outside the model, a 405 for the legacy `POST`, a 400 above 100 locations, and no CORS header.

CI runs them on every pull request, followed by a smoke test with the real 50 m model.

---

## License

This project is licensed under the **GNU General Public License v2.0**. See the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- [Open Topo Data](https://github.com/ajnisbet/opentopodata) (MIT).
- Elevation data: [Terrengmodell Svalbard (S0 Terrengmodell)](https://data.npolar.no/dataset/dce53a47-c726-4845-85c3-a65b46fe2fea), Norwegian Polar Institute, CC BY 4.0.

---

## Contact

For questions or support, please contact the maintainers via GitHub issues.
