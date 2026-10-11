# Open Topo Data (https://www.opentopodata.org) publishes no image, only a Dockerfile, so this
# one builds it from the upstream source at a pinned release and adds GDAL for the DTM
# preparation (prepare-data.sh). Mirrors upstream's docker/Dockerfile at the same ref.
ARG PYTHON_IMAGE=python:3.11-slim-bookworm@sha256:0a310eeecf4e1f5a0743f9a6520c90c88d089c903ca5fd283f501e3a805f5f89
# Open Topo Data v1.9.0
ARG OTD_REF=e93ff94ae530b7abccebf03889b06a7c72dfeea0

FROM scratch AS otd-source
ARG OTD_REF
ADD https://github.com/ajnisbet/opentopodata.git#${OTD_REF} /

FROM ${PYTHON_IMAGE} AS builder
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*
RUN pip wheel --no-cache-dir --wheel-dir=/root/wheels uwsgi==2.0.28 regex==2024.11.6

FROM ${PYTHON_IMAGE}
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl gdal-bin inotify-tools jq memcached nginx supervisor unzip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /root/wheels /root/wheels
COPY --from=otd-source /requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir --no-index --find-links=/root/wheels uwsgi regex \
    && pip install --no-cache-dir -r /app/requirements.txt \
    && rm -rf /root/wheels /app/requirements.txt

WORKDIR /app
COPY --from=otd-source / /app/

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
