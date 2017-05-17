#!/usr/bin/env bash
set -Eeuo pipefail

epoch="$(TZ=UTC date --date "$TIMESTAMP" +%s)"
serial="$(TZ=UTC date --date "@$epoch" +%Y%m%d)"

set -x

./build.sh travis "$SUITE" "@$epoch"

real="$(sha256sum "travis/$serial/$SUITE-amd64.tar.xz" | cut -d' ' -f1)"
[ -z "$SHA256" ] || [ "$SHA256" = "$real" ]
