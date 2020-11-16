#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(readlink -f "$BASH_SOURCE")"
thisDir="$(dirname "$thisDir")"

ver="$("$thisDir/scripts/debuerreotype-version")"
ver="${ver%% *}"
dockerImage="debuerreotype/debuerreotype:$ver"

echo "$dockerImage"
