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

securityArgs=(
	--cap-add SYS_ADMIN
)
if docker info | grep -q apparmor; then
	# AppArmor blocks mount :)
	securityArgs+=(
		--security-opt apparmor=unconfined
	)
fi

dockerImage='tianon/docker-deboot'
docker build -t "$dockerImage" -f "$thisDir/Dockerfile.builder" "$thisDir"
docker run \
	--rm \
	"${securityArgs[@]}" \
	--tmpfs /tmp:dev,exec,suid,noatime \
	-w /tmp \
	-e suite="$suite" \
	-e timestamp="$timestamp" \
	-e TZ='UTC' -e LC_ALL='C' \
	"$dockerImage" \
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

			# prefer iproute2 if it exists
			iproute=iproute2
			if ! docker-deboot-chroot rootfs apt-cache show iproute2 > /dev/null; then
				# poor wheezy
				iproute=iproute
			fi

			docker-deboot-apt-get rootfs install -y --no-install-recommends inetutils-ping $iproute

			docker-deboot-slimify rootfs-slim

			du -hs rootfs rootfs-slim

			for rootfs in rootfs*/; do
				docker-deboot-gen-sources-list "$rootfs" "$suite" http://deb.debian.org/debian http://security.debian.org
			done

			mkdir -p "$outputDir"
			for variant in "" -slim; do
				targetBase="$outputDir/$suite$variant-$dpkgArch"
				docker-deboot-tar "rootfs$variant" "$targetBase.tar.xz"
				docker-deboot-chroot "rootfs$variant" dpkg-query -W > "$targetBase.manifest"
				touch --no-dereference --date="@$epoch" "$targetBase.manifest"
			done
		} >&2

		tar -cC "$exportDir" .
	' | tar -xvC "$outputDir"
