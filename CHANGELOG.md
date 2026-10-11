# Changelog

## [1.0.0](https://github.com/UNIS-Svalbard-Weather-Information/swi-elevationapi/compare/0.0.4...1.0.0) (2026-10-11)


### ⚠ BREAKING CHANGES

* **elevation:** the container listens on 5000 instead of 8080 and stores its data in /data. The legacy lookup response now has location.lat/lng instead of latitude/longitude and POST is not supported.

### Features

* **elevation:** replace Open-Elevation with Open Topo Data ([c4638b4](https://github.com/UNIS-Svalbard-Weather-Information/swi-elevationapi/commit/c4638b49892dbaacea7434ed4daa23a220c28ece))


### Bug Fixes

* **security:** remove pip from the image and pin urllib3 2.8.0 ([f15cc59](https://github.com/UNIS-Svalbard-Weather-Information/swi-elevationapi/commit/f15cc59518da1026c82171d73aa55e127a0b0240))


### Miscellaneous Chores

* release 1.0.0 ([db8feb9](https://github.com/UNIS-Svalbard-Weather-Information/swi-elevationapi/commit/db8feb9fccc8be56ec6ecebc95018a2fc51a1881))

## [0.0.4](https://github.com/UNIS-Svalbard-Weather-Information/swi-elevationapi/compare/0.0.3...0.0.4) (2026-09-07)


### Bug Fixes

* Enable semantic commits in renovate.json ([710e583](https://github.com/UNIS-Svalbard-Weather-Information/swi-elevationapi/commit/710e58349adbc4689ae60955e375c57811c70338))

## [0.0.3](https://github.com/UNIS-Svalbard-Weather-Information/swi-elevationapi/compare/0.0.2...0.0.3) (2026-08-29)


### Bug Fixes

* publish images as a same-run job instead of a separate tag trigger ([05367fa](https://github.com/UNIS-Svalbard-Weather-Information/swi-elevationapi/commit/05367fa20d0f2311d3b8b744dedd6bb8f662a026))

## [0.0.2](https://github.com/UNIS-Svalbard-Weather-Information/swi-elevationapi/compare/0.0.1...0.0.2) (2026-08-29)


### Bug Fixes

* add docker build check ahead of ongoing deployment work ([ade30d0](https://github.com/UNIS-Svalbard-Weather-Information/swi-elevationapi/commit/ade30d09f19a1e40f08db64c881b3de265cc371b))
