#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(readlink -vf "$BASH_SOURCE")"
thisDir="$(dirname "$thisDir")"

ver="$("$thisDir/scripts/debuerreotype-version")"
ver="${ver%% *}"
dockerImage="debuerreotype/debuerreotype:$ver"

echo "$dockerImage"
