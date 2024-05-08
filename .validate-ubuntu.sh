#!/usr/bin/env bash
set -Eeuo pipefail

buildArgs=()
if [ -n "${ARCH:-}" ]; then
	buildArgs+=( "--arch=${ARCH}" )
fi
buildArgs+=( validate "$SUITE" )

mkdir -p validate

set -x

./scripts/debuerreotype-version
./docker-run.sh --pull ./examples/ubuntu.sh "${buildArgs[@]}"
