#!/usr/bin/env bash
# Tests for the data preparation and the API, run inside the built image:
#   docker run --rm --entrypoint bash -v "$PWD/tests:/tests:ro" <image> /tests/run.sh
# They use a tiny synthetic DTM served from localhost, so they need no network and take
# about a minute. Exit status is the number of failed checks.
set -uo pipefail

PREPARE=/opt/prepare-data.sh
PORT=8765
BASE="http://127.0.0.1:$PORT"
work="$(mktemp -d)"
mkdir "$work/srv"
pass=0
fail=0
http_pid=""
api_pid=""

ok() { pass=$((pass + 1)); echo "  ok   - $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL - $1"; if [ -n "${2:-}" ]; then echo "$2" | sed 's/^/         /'; fi; }
# check "description" command...   (passes when the command succeeds)
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else ko "$d"; fi; }
# run_prepare <data_dir> <url> [VAR=value...]: sets $out and $rc
run_prepare() {
  local dir="$1" url="$2"; shift 2
  out="$(env DATA_DIR="$dir" OTD_URL_SVALBARD="$url" "$@" "$PREPARE" 2>&1)"; rc=$?
}
expect_out() { if echo "$out" | grep -q "$2"; then ok "$1"; else ko "$1" "$out"; fi; }
gets() { grep -c "GET /dtm.zip" "$work/http.log" || true; }
fixture() { python3 /tests/make_fixture.py "$@"; }
start_http() {
  python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$work/srv" >"$work/http.log" 2>&1 &
  http_pid=$!
  for _ in $(seq 20); do curl -sf -o /dev/null -I "$BASE/dtm.zip" && return; sleep 0.5; done
}

cleanup() {
  if [ -n "$api_pid" ]; then kill "$api_pid" 2>/dev/null; fi
  if [ -n "$http_pid" ]; then kill "$http_pid" 2>/dev/null; fi
  rm -rf "$work"
}
trap cleanup EXIT

fixture 123 "$work/srv/dtm.zip"
start_http

echo "preparation"
d="$work/d1"
run_prepare "$d" "$BASE/dtm.zip?v=1"
check "first run exits 0" test "$rc" -eq 0
check "writes dtm.tif and .ready" test -f "$d/svalbard/dtm.tif" -a -f "$d/svalbard/.ready"
info="$(gdalinfo -json "$d/svalbard/dtm.tif")"
check "raster is tiled 256x256" test "$(echo "$info" | jq -c '.bands[0].block')" = "[256,256]"
check "raster is ZSTD compressed" test "$(echo "$info" | jq -r '.metadata.IMAGE_STRUCTURE.COMPRESSION')" = "ZSTD"
check "raster keeps EPSG:25833" test "$(echo "$info" | jq -r '.stac["proj:epsg"]')" = "25833"
check "temporary files are removed" test ! -e "$d/.tmp/svalbard"

before="$(gets)"
run_prepare "$d" "$BASE/dtm.zip?v=1"
expect_out "second run skips" "Skipping (up to date)"
check "second run downloads nothing" test "$(gets)" = "$before"

fixture 200 "$work/srv/dtm.zip"; touch -d '+1 hour' "$work/srv/dtm.zip"
run_prepare "$d" "$BASE/dtm.zip?v=1"
expect_out "changed upstream file is rebuilt" "upstream file changed"
check "rebuilt data is the new data" test "$(gdalinfo -stats "$d/svalbard/dtm.tif" 2>/dev/null | sed -n 's/.*STATISTICS_MAXIMUM=//p')" = "200"

run_prepare "$d" "$BASE/dtm.zip?v=2"
expect_out "changed url is rebuilt" "configuration changed"

run_prepare "$d" "$BASE/dtm.zip?v=2" FORCE_REPREPARE=1
expect_out "FORCE_REPREPARE rebuilds" "svalbard: ready"

echo "concurrency"
fixture 123 "$work/srv/dtm.zip"
d="$work/d2"
before="$(gets)"
pids=()
for n in 1 2; do
  ( run_prepare "$d" "$BASE/dtm.zip?v=c"; echo "$rc" >"$work/rc$n"; echo "$out" >"$work/out$n" ) &
  pids+=($!)
done
wait "${pids[@]}"  # not a bare `wait`: that would also wait for the HTTP server
check "both runs exit 0" test "$(cat "$work/rc1")$(cat "$work/rc2")" = "00"
check "the archive is downloaded once" test "$(($(gets) - before))" -eq 1
check "exactly one run prepared the data" test "$(cat "$work/out1" "$work/out2" | grep -c 'svalbard: ready')" -eq 1

echo "failures"
d="$work/d3"
echo "not a zip" >"$work/srv/dtm.zip"
run_prepare "$d" "$BASE/dtm.zip?v=bad"
check "corrupt archive fails" test "$rc" -ne 0
check "corrupt archive leaves no dataset" test ! -e "$d/svalbard"

fixture 123 "$work/srv/dtm.zip" --two-rasters
run_prepare "$d" "$BASE/dtm.zip?v=two"
check "several rasters fail" test "$rc" -ne 0
expect_out "several rasters explain why" "expected one raster"
run_prepare "$d" "$BASE/dtm.zip?v=two" OTD_SOURCE_FILE_SVALBARD=S0_DTM20.tif
check "source_file selects one raster" test "$rc" -eq 0

echo "offline"
fixture 123 "$work/srv/dtm.zip"
d="$work/d4"
run_prepare "$d" "$BASE/dtm.zip?v=off"
kill "$http_pid"; wait "$http_pid" 2>/dev/null; http_pid=""
run_prepare "$d" "$BASE/dtm.zip?v=off"
expect_out "unreachable upstream keeps the data" "upstream unreachable"
check "data is still there" test -f "$d/svalbard/dtm.tif"

echo "api"
# The server reads /data (see config.yaml), so prepare the fixture there.
start_http
run_prepare /data "$BASE/dtm.zip"
check "prepares /data" test "$rc" -eq 0
sh /app/docker/run.sh >"$work/api.log" 2>&1 &
api_pid=$!
LOC="78.2232,15.6261"
for _ in $(seq 60); do curl -sf -o /dev/null "http://127.0.0.1:5000/v1/svalbard?locations=$LOC" && break; sleep 1; done
elev() { curl -sf "http://127.0.0.1:5000/$1?locations=$2" | jq -r '.results[0].elevation | if . == null then "null" else round | tostring end'; }
check "/v1/svalbard returns the elevation" test "$(elev v1/svalbard "$LOC")" = "123"
check "/api/v1/svalbard returns the elevation" test "$(elev api/v1/svalbard "$LOC")" = "123"
check "/api/v1/lookup (legacy) returns the elevation" test "$(elev api/v1/lookup "$LOC")" = "123"
check "legacy path keeps the query string" test "$(curl -sf 'http://127.0.0.1:5000/api/v1/lookup?locations=78.2232,15.6261|78.2233,15.6262' | jq '.results | length')" = "2"
check "outside the model is null" test "$(elev v1/svalbard 79.5,5.0)" = "null"
check "legacy POST is refused" test "$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:5000/api/v1/lookup)" = "405"
many="$(for _ in $(seq 101); do printf '78.2232,15.6261|'; done)78.2232,15.6261"
check "more than 100 locations is rejected" test "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:5000/v1/svalbard?locations=$many")" = "400"
check "no CORS header is sent (the proxy owns CORS)" test -z "$(curl -s -D - -o /dev/null -H 'Origin: https://example.com' "http://127.0.0.1:5000/v1/svalbard?locations=$LOC" | grep -i '^access-control-allow-origin')"

# uwsgi used to kill and respawn a worker after one or two requests (address space limit).
for _ in $(seq 60); do curl -s -o /dev/null "http://127.0.0.1:5000/v1/svalbard?locations=$LOC"; done
sleep 1
check "workers are not recycled by requests" test "$(grep -c 'Seeya' "$work/api.log")" -eq 0
check "no memcached/pylibmc errors in the log" test "$(grep -c -E 'pylibmc|PyMapping_HasKeyString' "$work/api.log")" -eq 0
check "no tracebacks in the log" test "$(grep -c 'Traceback' "$work/api.log")" -eq 0

echo
echo "$pass passed, $fail failed"
exit "$fail"
