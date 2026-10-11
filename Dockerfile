# Open Topo Data (https://www.opentopodata.org) publishes no image, only a Dockerfile, so this
# one builds it from the upstream source at a pinned release and adds GDAL for the DTM
# preparation (prepare-data.sh). Follows upstream's docker/Dockerfile, with a current Python
# and current dependencies (requirements.txt).
ARG PYTHON_IMAGE=python:3.14-slim-trixie@sha256:a2b82f3c48559aa0a8446d9af49826b6e2b2016f4cd2afabfe6013ec53729170
# Open Topo Data v1.9.0
ARG OTD_REF=e93ff94ae530b7abccebf03889b06a7c72dfeea0

FROM scratch AS otd-source
ARG OTD_REF
ADD https://github.com/ajnisbet/opentopodata.git#${OTD_REF} /

FROM ${PYTHON_IMAGE} AS builder
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libc6-dev libmemcached-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt /requirements.txt
RUN pip wheel --no-cache-dir --wheel-dir=/wheels -r /requirements.txt

FROM ${PYTHON_IMAGE}
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl gdal-bin inotify-tools jq libmemcached11t64 memcached nginx supervisor unzip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /wheels /wheels
RUN pip install --no-cache-dir --no-index --find-links=/wheels /wheels/*.whl && rm -rf /wheels

WORKDIR /app
COPY --from=otd-source / /app/
# v1.9.0 calls DatasetReader.index() with arrays, which since rasterio 1.4 only handles scalars
# (upstream master has not fixed this properly yet). rasterio.transform.rowcol() does the same
# lookup for arrays. The build fails if the line is gone, so remove this patch once OTD_REF is
# bumped to a release that works with current rasterio.
RUN grep -q 'f.index(xs, ys, op=_noop)' opentopodata/backend.py \
    && grep -q '^import rasterio' opentopodata/backend.py \
    && sed -i 's/f\.index(xs, ys, op=_noop)/rasterio.transform.rowcol(f.transform, xs, ys, op=_noop)/' opentopodata/backend.py

# Service configuration: dataset list, nginx with the /api/ aliases, and the data preparation.
RUN rm -f /etc/nginx/sites-enabled/default
COPY nginx.conf /etc/nginx/conf.d/nginx.conf
COPY config.yaml /app/config.yaml
COPY datasets.json /opt/datasets.json
COPY prepare-data.sh /opt/prepare-data.sh
RUN chmod +x /opt/prepare-data.sh \
    && cp /app/docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

ENV CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    GDAL_DISABLE_READDIR_ON_OPEN=TRUE \
    GDAL_NUM_THREADS=ALL_CPUS \
    GDAL_CACHEMAX=512

# The prepared datasets live here (shared volume). prepare-data.sh fills it before the server starts.
VOLUME /data

EXPOSE 5000
CMD ["sh", "/app/docker/run.sh"]
