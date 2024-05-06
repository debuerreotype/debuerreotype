#!/usr/bin/env bash
set -Eeuo pipefail

buildArgs=()
if [ -n "${ARCH:-}" ]; then
	buildArgs+=( "--arch=${ARCH}" )
fi
buildArgs+=( validate "$SUITE" )

dockerImage="$(./.docker-image.sh)"
dockerImage+='-ubuntu'
{
	cat Dockerfile - <<-'EODF'
		RUN set -eux; \
# https://bugs.debian.org/929165 :(
# http://snapshot.debian.org/package/ubuntu-keyring/
# http://snapshot.debian.org/package/ubuntu-keyring/2020.06.17.1-1/
			wget -O ubuntu-keyring.deb 'http://snapshot.debian.org/archive/debian/20210307T083530Z/pool/main/u/ubuntu-keyring/ubuntu-keyring_2020.06.17.1-1_all.deb'; \
			echo 'c2d8c4a9be6244bbea80c2e0e7624cbd3a2006a2 *ubuntu-keyring.deb' | sha1sum --strict --check -; \
			apt-get install -y --no-install-recommends ./ubuntu-keyring.deb; \
			rm ubuntu-keyring.deb
	EODF
} | docker build --pull --tag "$dockerImage" --file - .

mkdir -p validate

set -x

./scripts/debuerreotype-version
./docker-run.sh --image="$dockerImage" --no-build ./examples/ubuntu.sh "${buildArgs[@]}"
