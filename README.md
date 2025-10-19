# SWI Elevation API

**A regional elevation API for Svalbard, based on the Norwegian Polar Institute's Digital Terrain Model (NP DTM).**

This project builds on the work of [Jorl17/open-elevation](https://github.com/Jorl17/open-elevation), providing a ready-to-use API for Svalbard by automating the download, reprojection, and deployment of the NP DTM using the original Open-Elevation container for the Svalbard Weather Information platform.

---

## API Documentation

The API is simple and intuitive, with a single endpoint for elevation lookups. For full details, see the [Jorl17/open-elevation documentation](https://github.com/Jorl17/open-elevation/blob/master/docs/api.md).

### Endpoints

#### `GET /api/v1/lookup`
Returns elevation data for one or more `(latitude,longitude)` points.

**Parameters:**
- `locations`: List of locations, separated by `|` in `latitude,longitude` format.

**Example Request:**
```bash
curl 'https://your-api-url/api/v1/lookup?locations=78.2232,15.6261|78.2233,15.6262'
```

**Example Response:**
```json
{
   "results":[
      {
         "latitude":78.2232,
         "longitude":15.6261,
         "elevation":123
      },
      {
         "latitude":78.2233,
         "longitude":15.6262,
         "elevation":125
      }
   ]
}
```

#### `POST /api/v1/lookup`
Allows for larger requests via JSON payload.

**Example Request:**
```bash
curl -X POST \
  https://your-api-url/api/v1/lookup \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
    "locations":[
        {"latitude":78.2232, "longitude":15.6261},
        {"latitude":78.2233, "longitude":15.6262}
    ]
}'
```

**Example Response:**
```json
{
   "results":[
      {
         "latitude":78.2232,
         "longitude":15.6261,
         "elevation":123
      },
      {
         "latitude":78.2233,
         "longitude":15.6262,
         "elevation":125
      }
   ]
}
```

---

## Usage

This project simplifies deployment by providing a script to download the NP DTM, reproject it, and launch the API using the original Open-Elevation container.

To run the API:
```bash
docker run -p 80:8080 ghcr.io/unis-svalbard-weather-information/swi-elevationapi:latest
```

---

## License

This project is licensed under the **GNU General Public License v2.0**. See the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- This project is based on [Jorl17/open-elevation](https://github.com/Jorl17/open-elevation).
- Elevation data provided by the Norwegian Polar Institute.

---

## Contact

For questions or support, please contact the maintainers via GitHub issues.
