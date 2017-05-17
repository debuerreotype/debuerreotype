#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
self="$(basename "$0")"

usage() {
	cat <<-EOU
		usage: $self <output-dir> <suite> <timestamp>
		   ie: $self output stretch 2017-05-08T00:00:00Z
	EOU
}
eusage() {
	echo >&2 "error: $1"
	usage >&2
	exit 1
}

outputDir="${1:-}"; shift || eusage 'missing output-dir'
suite="${1:-}"; shift || eusage 'missing suite'
timestamp="${1:-}"; shift || eusage 'missing timestamp'

mkdir -p "$outputDir"
outputDir="$(readlink -f "$outputDir")"

docker build -t docker-deboot -f "$thisDir/Dockerfile.builder" "$thisDir"
docker run \
	--rm \
	--cap-add SYS_ADMIN \
	--tmpfs /tmp:dev,exec,suid,noatime \
	-w /tmp \
	-e suite="$suite" \
	-e timestamp="$timestamp" \
	docker-deboot \
	bash -Eeuo pipefail -c '
		set -x

		epoch="$(date --date "$timestamp" +%s)"
		serial="$(date --date "@$epoch" +%Y%m%d)"
		exportDir="output"
		outputDir="$exportDir/$serial"
		dpkgArch="$(dpkg --print-architecture)"

		{
			docker-deboot-init rootfs "$suite" "@$epoch"

			docker-deboot-minimizing-config rootfs
			docker-deboot-apt-get rootfs update -qq
			docker-deboot-apt-get rootfs dist-upgrade -yqq

			mkdir -p rootfs-slim
			tar -cC rootfs . | tar -xC rootfs-slim

			docker-deboot-apt-get rootfs install -y --no-install-recommends inetutils-ping iproute2

			docker-deboot-slimify rootfs-slim

			du -hs rootfs rootfs-slim

			mkdir -p "$outputDir"
			for variant in "" -slim; do
				docker-deboot-gen-sources-list "rootfs$variant" "$suite" http://deb.debian.org/debian http://security.debian.org
				docker-deboot-tar "rootfs$variant" "$outputDir/$dpkgArch-$suite$variant.tar.xz"
			done
		} >&2

		tar -cC "$exportDir" .
	' | tar -xvC "$outputDir"
