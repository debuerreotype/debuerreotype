#!/usr/bin/env bash
set -Eeuo pipefail

epoch="$(TZ=UTC date --date "$TIMESTAMP" +%s)"
serial="$(TZ=UTC date --date "@$epoch" +%Y%m%d)"

buildArgs=()
if [ -n "${CODENAME:-}" ]; then
	buildArgs+=( '--codename-copy' )
fi
if [ -n "${ARCH:-}" ]; then
	buildArgs+=( "--dpkg-arch=${ARCH}" )
fi
buildArgs+=( travis "$SUITE" "@$epoch" )

checkFile="travis/$serial/${ARCH:=amd64}/${CODENAME:-$SUITE}/rootfs.tar.xz"

set -x

./scripts/debuerreotype-version
./build.sh "${buildArgs[@]}"

real="$(sha256sum "$checkFile" | cut -d' ' -f1)"
[ -z "$SHA256" ] || [ "$SHA256" = "$real" ]
