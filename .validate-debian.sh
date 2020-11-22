#!/usr/bin/env bash
set -Eeuo pipefail

epoch="$(TZ=UTC date --date "$TIMESTAMP" +%s)"
serial="$(TZ=UTC date --date "@$epoch" +%Y%m%d)"

buildArgs=()
if [ "$SUITE" = 'eol' ]; then
	buildArgs+=( '--eol' )
	SUITE="$CODENAME"
elif [ -n "${CODENAME:-}" ]; then
	buildArgs+=( '--codename-copy' )
fi
if [ -n "${ARCH:-}" ]; then
	buildArgs+=( "--arch=${ARCH}" )
	if [ "$ARCH" != 'i386' ]; then
		if [ "$ARCH" != 'arm64' ]; then
			buildArgs+=( '--ports' )
		fi
	fi
fi
buildArgs+=( validate "$SUITE" "@$epoch" )

checkFile="validate/$serial/${ARCH:-amd64}/${CODENAME:-$SUITE}/rootfs.tar.xz"
mkdir -p validate

set -x

./scripts/debuerreotype-version
./docker-run.sh ./examples/debian.sh "${buildArgs[@]}"

real="$(sha256sum "$checkFile" | cut -d' ' -f1)"
[ -z "$SHA256" ] || [ "$SHA256" = "$real" ]
