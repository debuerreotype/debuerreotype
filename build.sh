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

# a silly flag to skip "docker build" (for "build-all.sh")
build=1
if [ "${1:-}" = '--no-build' ]; then
	shift
	build=
fi

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

ver="$("$thisDir/scripts/debuerreotype-version")"
ver="${ver%% *}"
dockerImage="debuerreotype/debuerreotype:$ver"
[ -z "$build" ] || docker build -t "$dockerImage" "$thisDir"

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
		dpkgArch="$(dpkg --print-architecture)"

		exportDir="output"
		outputDir="$exportDir/$serial/$dpkgArch/$suite"

		touch_epoch() {
			while [ "$#" -gt 0 ]; do
				local f="$1"; shift
				touch --no-dereference --date="@$epoch" "$f"
			done
		}

		{
			debuerreotype-init rootfs "$suite" "@$epoch"

			debuerreotype-minimizing-config rootfs
			debuerreotype-apt-get rootfs update -qq
			debuerreotype-apt-get rootfs dist-upgrade -yqq

			# make a couple copies of rootfs so we can create other variants
			for variant in slim sbuild; do
				mkdir "rootfs-$variant"
				tar -cC rootfs . | tar -xC "rootfs-$variant"
			done

			# prefer iproute2 if it exists
			iproute=iproute2
			if ! debuerreotype-chroot rootfs apt-cache show iproute2 > /dev/null; then
				# poor wheezy
				iproute=iproute
			fi
			debuerreotype-apt-get rootfs install -y --no-install-recommends inetutils-ping $iproute

			debuerreotype-slimify rootfs-slim

			# this should match the list added to the "buildd" variant in debootstrap and the list installed by sbuild
			# https://anonscm.debian.org/cgit/d-i/debootstrap.git/tree/scripts/sid?id=706a45681c5bba5e062a9b02e19f079cacf2a3e8#n26
			# https://anonscm.debian.org/cgit/buildd-tools/sbuild.git/tree/bin/sbuild-createchroot?id=eace3d3e59e48d26eaf069d9b63a6a4c868640e6#n194
			debuerreotype-apt-get rootfs-sbuild install -y --no-install-recommends build-essential fakeroot

			for rootfs in rootfs*/; do
				rootfs="${rootfs%/}" # "rootfs", "rootfs-slim", ...

				du -hsx "$rootfs"

				variant="${rootfs#rootfs}" # "", "-slim", ...
				variant="${variant#-}" # "", "slim", ...

				variantDir="$outputDir/$variant"
				mkdir -p "$variantDir"

				targetBase="$variantDir/rootfs"

				if [ "$variant" != "sbuild" ]; then
					debuerreotype-gen-sources-list "$rootfs" "$suite" http://deb.debian.org/debian http://security.debian.org
					debuerreotype-tar "$rootfs" "$targetBase.tar.xz"
				else
					# sbuild needs "deb-src" entries
					debuerreotype-gen-sources-list --deb-src "$rootfs" "$suite" http://deb.debian.org/debian http://security.debian.org

					# schroot is picky about "/dev" (which is excluded by default in "debuerreotype-tar")
					# see https://github.com/debuerreotype/debuerreotype/pull/8#issuecomment-305855521
					debuerreotype-tar --include-dev "$rootfs" "$targetBase.tar.xz"
				fi
				du -hsx "$targetBase.tar.xz"

				sha256sum "$targetBase.tar.xz" | cut -d" " -f1 > "$targetBase.tar.xz.sha256"
				touch_epoch "$targetBase.tar.xz.sha256"

				debuerreotype-chroot "$rootfs" dpkg-query -W > "$targetBase.manifest"
				echo "$epoch" > "$targetBase.debuerreotype-epoch"
				touch_epoch "$targetBase.manifest" "$targetBase.debuerreotype-epoch"

				for f in debian_version os-release apt/sources.list; do
					targetFile="$targetBase.$(basename "$f" | sed -r "s/[^a-zA-Z0-9_-]+/-/g")"
					cp "$rootfs/etc/$f" "$targetFile"
					touch_epoch "$targetFile"
				done
			done
		} >&2

		tar -cC "$exportDir" .
	' | tar -xvC "$outputDir"
