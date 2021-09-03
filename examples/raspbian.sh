#!/usr/bin/env bash
set -Eeuo pipefail

# # https://archive.raspbian.org/raspbian/pool/main/r/raspbian-archive-keyring/
# RUN wget -O raspbian.deb 'https://archive.raspbian.org/raspbian/pool/main/r/raspbian-archive-keyring/raspbian-archive-keyring-udeb_20120528.2_all.udeb' \
# 	&& apt-get install -y ./raspbian.deb \
# 	&& rm raspbian.deb

debuerreotypeScriptsDir="$(which debuerreotype-init)"
debuerreotypeScriptsDir="$(readlink -vf "$debuerreotypeScriptsDir")"
debuerreotypeScriptsDir="$(dirname "$debuerreotypeScriptsDir")"

source "$debuerreotypeScriptsDir/.constants.sh" \
	-- \
	'<output-dir> <suite>' \
	'output stretch'

eval "$dgetopt"
while true; do
	flag="$1"; shift
	dgetopt-case "$flag"
	case "$flag" in
		--) break ;;
		*) eusage "unknown flag '$flag'" ;;
	esac
done

outputDir="${1:-}"; shift || eusage 'missing output-dir'
suite="${1:-}"; shift || eusage 'missing suite'

set -x

outputDir="$(readlink -ve "$outputDir")"

tmpDir="$(mktemp --directory --tmpdir "debuerreotype.$suite.XXXXXXXXXX")"
trap "$(printf 'rm -rf %q' "$tmpDir")" EXIT

export TZ='UTC' LC_ALL='C'

dpkgArch='armhf'

#mirror='http://archive.raspbian.org/raspbian'
mirror='http://mirrordirector.raspbian.org/raspbian'
# (https://www.raspbian.org/RaspbianMirrors#The_mirror_redirection_system)

exportDir="$tmpDir/output"
archDir="$exportDir/raspbian/$dpkgArch"
tmpOutputDir="$archDir/$suite"

keyring='/usr/share/keyrings/raspbian-archive-keyring.gpg'
if [ ! -s "$keyring" ]; then
	# since we're using mirrors, we ought to be more explicit about download verification
	keyUrl='https://archive.raspbian.org/raspbian.public.key'
	(
		set +x
		echo >&2
		echo >&2 "WARNING: missing '$keyring' (from 'raspbian-archive-keyring' package)"
		echo >&2 "  downloading '$keyUrl' (without verification)!"
		echo >&2
	)
	sleep 5
	keyring="$tmpDir/raspbian-archive-keyring.gpg"
	wget -O "$keyring.asc" "$keyUrl"
	gpg --batch --no-default-keyring --keyring "$keyring" --import "$keyring.asc"
	rm -f "$keyring.asc"
fi

mkdir -p "$tmpOutputDir"
if wget -O "$tmpOutputDir/InRelease" "$mirror/dists/$suite/InRelease"; then
	gpgv \
		--keyring "$keyring" \
		--output "$tmpOutputDir/Release" \
		"$tmpOutputDir/InRelease"
else
	rm -f "$tmpOutputDir/InRelease" # remove wget leftovers
	wget -O "$tmpOutputDir/Release.gpg" "$mirror/dists/$suite/Release.gpg"
	wget -O "$tmpOutputDir/Release" "$mirror/dists/$suite/Release"
	gpgv \
		--keyring "$keyring" \
		"$tmpOutputDir/Release.gpg" \
		"$tmpOutputDir/Release"
fi

initArgs=(
	--arch "$dpkgArch"

	--non-debian

	--keyring "$keyring"

	# disable merged-usr (for now?) due to the following compelling arguments:
	#  - https://bugs.debian.org/src:usrmerge ("dpkg-query" breaks, etc)
	#  - https://bugs.debian.org/914208 ("buildd" variant disables merged-usr still)
	#  - https://github.com/debuerreotype/docker-debian-artifacts/issues/60#issuecomment-461426406
	--no-merged-usr
)

rootfsDir="$tmpDir/rootfs"
debuerreotype-init "${initArgs[@]}" "$rootfsDir" "$suite" "$mirror"

debuerreotype-minimizing-config "$rootfsDir"

# TODO do we need to update sources.list here? (security?)
debuerreotype-apt-get "$rootfsDir" update -qq

debuerreotype-recalculate-epoch "$rootfsDir"
epoch="$(< "$rootfsDir/debuerreotype-epoch")"
touch_epoch() {
	while [ "$#" -gt 0 ]; do
		local f="$1"; shift
		touch --no-dereference --date="@$epoch" "$f"
	done
}

debuerreotype-apt-get "$rootfsDir" dist-upgrade -yqq

# copy the rootfs to create other variants
mkdir "$rootfsDir"-slim
tar -cC "$rootfsDir" . | tar -xC "$rootfsDir"-slim

# prefer iproute2 if it exists
iproute=iproute2
if ! debuerreotype-apt-get "$rootfsDir" install -qq -s iproute2 &> /dev/null; then
	# poor wheezy
	iproute=iproute
fi
debuerreotype-apt-get "$rootfsDir" install -y --no-install-recommends iputils-ping $iproute

debuerreotype-slimify "$rootfsDir"-slim

create_artifacts() {
	local targetBase="$1"; shift
	local rootfs="$1"; shift
	local suite="$1"; shift
	local variant="$1"; shift

	local tarArgs=()

	debuerreotype-tar "${tarArgs[@]}" "$rootfs" "$targetBase.tar.xz"
	du -hsx "$targetBase.tar.xz"

	sha256sum "$targetBase.tar.xz" | cut -d' ' -f1 > "$targetBase.tar.xz.sha256"
	touch_epoch "$targetBase.tar.xz.sha256"

	debuerreotype-chroot "$rootfs" dpkg-query -W > "$targetBase.manifest"
	echo "$suite" > "$targetBase.apt-dist"
	echo "$dpkgArch" > "$targetBase.dpkg-arch"
	echo "$epoch" > "$targetBase.debuerreotype-epoch"
	echo "$variant" > "$targetBase.debuerreotype-variant"
	debuerreotype-version > "$targetBase.debuerreotype-version"
	touch_epoch "$targetBase".{manifest,apt-dist,dpkg-arch,debuerreotype-*}

	for f in debian_version os-release apt/sources.list; do
		targetFile="$targetBase.$(basename "$f" | sed -r "s/[^a-zA-Z0-9_-]+/-/g")"
		cp "$rootfs/etc/$f" "$targetFile"
		touch_epoch "$targetFile"
	done
}

for rootfs in "$rootfsDir"*/; do
	rootfs="${rootfs%/}" # "../rootfs", "../rootfs-slim", ...

	du -hsx "$rootfs"

	variant="$(basename "$rootfs")" # "rootfs", "rootfs-slim", ...
	variant="${variant#rootfs}" # "", "-slim", ...
	variant="${variant#-}" # "", "slim", ...

	variantDir="$tmpOutputDir/$variant"
	mkdir -p "$variantDir"

	targetBase="$variantDir/rootfs"

	create_artifacts "$targetBase" "$rootfs" "$suite" "$variant"
done

user="$(stat --format '%u' "$outputDir")"
group="$(stat --format '%g' "$outputDir")"
tar --create --directory="$exportDir" --owner="$user" --group="$group" . | tar --extract --verbose --directory="$outputDir"
