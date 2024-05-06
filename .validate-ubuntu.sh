#!/usr/bin/env bash
set -Eeuo pipefail

buildArgs=()
if [ "$SUITE" = 'eol' ]; then
	buildArgs+=( '--eol' )
	SUITE="$CODENAME"
fi
if [ -n "${ARCH:-}" ]; then
	buildArgs+=( "--arch=${ARCH}" )
fi
buildArgs+=( validate "$SUITE" )

dockerRunArgs=()
if [ -z "${IMAGE}" ]; then
	dockerRunArgs+=(--pull)
else
	dockerRunArgs+=(--no-build --image "${IMAGE}")
fi

mkdir -p validate

set -x

./scripts/debuerreotype-version
./docker-run.sh "${dockerRunArgs[@]}" ./examples/ubuntu.sh "${buildArgs[@]}"
