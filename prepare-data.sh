#!/usr/bin/env bash
# Download and prepare the elevation datasets listed in datasets.json under $DATA_DIR.
#
# Usage: prepare-data.sh [all|download|prepare]
#
# Meant to run as the Compose `pre_start` step of the elevation service (see README.md),
# so the server only starts once the data is ready and a plain restart never re-downloads.
#
# A dataset is rebuilt when its fingerprint (url, GDAL options, source file, PREP_VERSION)
# or its upstream file (ETag / size / Last-Modified) differs from what `.ready` records.
# Environment:
#   DATA_DIR            output directory, shared volume (default /data)
#   MANIFEST            dataset manifest (default /opt/datasets.json)
#   FORCE_REPREPARE=1   rebuild every dataset
#   PRUNE=1             remove dataset directories that are no longer in the manifest
#   OTD_URL_<NAME>      override the download url of dataset <NAME> (upper case, "-" as "_")
#   OTD_SOURCE_FILE_<NAME>  override its source_file
set -euo pipefail

# Bump when the preparation logic or its default options change, to rebuild existing data.
PREP_VERSION="1"

MANIFEST="${MANIFEST:-/opt/datasets.json}"
DATA_DIR="${DATA_DIR:-/data}"
STEP="${1:-all}"

log() { echo "[prepare-data] $*"; }
die() { echo "[prepare-data] ERROR: $*" >&2; exit 1; }

case "$STEP" in all | download | prepare) ;; *) die "unknown step '$STEP' (all|download|prepare)" ;; esac
[ -f "$MANIFEST" ] || die "manifest $MANIFEST not found"
mkdir -p "$DATA_DIR/.tmp"

# One runner at a time on the shared volume. A second runner waits here, then finds a
# matching .ready and skips. The kernel drops the lock if the process dies.
exec 9>"$DATA_DIR/.prepare.lock"
flock -w 7200 9 || die "could not take $DATA_DIR/.prepare.lock"

# Prints "etag|length|last-modified" of the upstream file, or nothing when unreachable.
remote_signature() {
  local headers
  headers="$(curl -fsSIL --retry 3 --max-time 60 "$1" 2>/dev/null | tr -d '\r' | tr 'A-Z' 'a-z')" || return 0
  # Headers of the final response only (after redirects).
  headers="$(echo "$headers" | awk 'BEGIN{RS="";ORS="\n\n"} {last=$0} END{print last}')"
  local etag length modified
  etag="$(echo "$headers" | sed -n 's/^etag: *//p' | head -n1)"
  length="$(echo "$headers" | sed -n 's/^content-length: *//p' | head -n1)"
  modified="$(echo "$headers" | sed -n 's/^last-modified: *//p' | head -n1)"
  [ -n "$etag$length$modified" ] && echo "$etag|$length|$modified"
  return 0
}

download_dataset() {
  local name="$1" url="$2" tmp="$3"
  if [ -f "$tmp/source.done" ] && [ "$(cat "$tmp/source.done")" = "$url" ]; then
    log "$name: archive already downloaded"
    return
  fi
  rm -f "$tmp/source.done"
  log "$name: downloading $url"
  curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors -C - \
    -o "$tmp/source.zip" "$url"
  unzip -tq "$tmp/source.zip" >/dev/null || { rm -f "$tmp/source.zip"; die "$name: downloaded archive is corrupt"; }
  echo "$url" >"$tmp/source.done"
}

convert_dataset() {
  local name="$1" source_file="$2" options="$3" tmp="$4"
  [ -f "$tmp/source.done" ] || die "$name: nothing to prepare, run the download step first"

  rm -rf "$tmp/extract" "$tmp/out"
  mkdir -p "$tmp/extract" "$tmp/out"
  log "$name: extracting"
  unzip -q "$tmp/source.zip" -d "$tmp/extract"

  local -a sources
  mapfile -t sources < <(find "$tmp/extract" -type f -iname "${source_file:-*.tif}" | sort)
  [ "${#sources[@]}" -eq 1 ] || die "$name: expected one raster, found ${#sources[@]}: ${sources[*]:-none} (set source_file)"
  local src="${sources[0]}"

  log "$name: gdal_translate $(basename "$src") ($options)"
  # shellcheck disable=SC2086  # options are intentionally split
  gdal_translate -q -of GTiff $options "$src" "$tmp/out/dtm.tif"

  # Sanity checks on the result.
  local in out
  in="$(gdalinfo -json "$src" | jq -c '{size: .size, crs: (.stac["proj:epsg"] // null)}')"
  out="$(gdalinfo -json "$tmp/out/dtm.tif" | jq -c '{size: .size, crs: (.stac["proj:epsg"] // null)}')"
  [ "$in" = "$out" ] || die "$name: converted raster differs from the source ($in vs $out)"
  log "$name: ok $(gdalinfo -json "$tmp/out/dtm.tif" | jq -c '{size, epsg: .stac["proj:epsg"], block: .bands[0].block, nodata: .bands[0].noDataValue, type: .bands[0].type}')"
}

prepare_dataset() {
  local name="$1" url="$2" source_file="$3" options="$4"
  local upper="${name^^}"; upper="${upper//-/_}"
  local url_var="OTD_URL_$upper" file_var="OTD_SOURCE_FILE_$upper"
  url="${!url_var:-$url}"
  source_file="${!file_var:-$source_file}"

  local dir="$DATA_DIR/$name" tmp="$DATA_DIR/.tmp/$name"
  local fingerprint remote
  fingerprint="$(printf '%s|%s|%s|%s' "$url" "$source_file" "$options" "$PREP_VERSION" | sha256sum | cut -d' ' -f1)"
  remote="$(remote_signature "$url")"

  if [ "${FORCE_REPREPARE:-0}" != "1" ] && [ "$STEP" != "prepare" ] && [ -f "$dir/.ready" ] && [ -f "$dir/dtm.tif" ]; then
    local ready_fp ready_remote
    ready_fp="$(jq -r '.fingerprint' "$dir/.ready")"
    ready_remote="$(jq -r '.source_signature' "$dir/.ready")"
    if [ "$ready_fp" = "$fingerprint" ]; then
      if [ -z "$remote" ]; then
        log "$name: Skipping (upstream unreachable, keeping the prepared data)"
        return
      fi
      if [ "$ready_remote" = "$remote" ]; then
        log "$name: Skipping (up to date)"
        return
      fi
      log "$name: upstream file changed ($ready_remote -> $remote)"
    else
      log "$name: configuration changed, rebuilding"
    fi
  fi

  mkdir -p "$tmp"
  if [ "$STEP" != "prepare" ]; then
    download_dataset "$name" "$url" "$tmp"
  fi
  if [ "$STEP" = "download" ]; then
    return
  fi
  convert_dataset "$name" "$source_file" "$options" "$tmp"

  jq -n --arg fp "$fingerprint" --arg sig "$remote" --arg url "$url" --arg pv "$PREP_VERSION" \
    --arg gdal "$(gdal_translate --version | head -n1)" --arg at "$(date -u +%FT%TZ)" \
    '{fingerprint: $fp, source_signature: $sig, url: $url, prep_version: $pv, gdal: $gdal, prepared_at: $at}' \
    >"$tmp/out/.ready"

  # Swap the new directory in; .ready travels with it, so it only exists once the data is complete.
  rm -rf "$DATA_DIR/.old-$name"
  [ -d "$dir" ] && mv "$dir" "$DATA_DIR/.old-$name"
  mv "$tmp/out" "$dir"
  rm -rf "$DATA_DIR/.old-$name" "$tmp"
  log "$name: ready"
}

# Leftovers from a run that was killed between the two renames.
for old in "$DATA_DIR"/.old-*; do
  [ -d "$old" ] || continue
  name="${old##*/.old-}"
  [ -d "$DATA_DIR/$name" ] || mv "$old" "$DATA_DIR/$name"
  rm -rf "$old"
done

declare -a names=()
while IFS=$'\t' read -r name url source_file options; do
  names+=("$name")
  [ "$source_file" = "-" ] && source_file=""  # `read` collapses empty tab-separated fields
  prepare_dataset "$name" "$url" "$source_file" "$options"
done < <(jq -r '.datasets[] | [.name, .url, (.source_file // "-"), (.creation_options | join(" "))] | @tsv' "$MANIFEST")

if [ "${PRUNE:-0}" = "1" ]; then
  for dir in "$DATA_DIR"/*/; do
    base="$(basename "$dir")"
    case " ${names[*]} " in *" $base "*) ;; *) log "pruning $base"; rm -rf "$dir" ;; esac
  done
fi
log "done"
