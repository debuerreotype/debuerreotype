#!/usr/bin/env bash
set -Eeuo pipefail

# # https://repo.steampowered.com/steamos/pool/main/v/valve-archive-keyring/?C=M&O=D
# RUN wget -O valve.deb 'https://repo.steampowered.com/steamos/pool/main/v/valve-archive-keyring/valve-archive-keyring_0.6+bsosc2_all.deb' \
# 	&& apt-get install -y ./valve.deb \
# 	&& rm valve.deb

source "$DEBUERREOTYPE_DIRECTORY/scripts/.constants.sh" \
	--flags 'arch:' \
	-- \
	'[--arch=<arch>] <output-dir> <suite>' \
	'output'

eval "$dgetopt"
arch=
while true; do
	flag="$1"; shift
	dgetopt-case "$flag"
	case "$flag" in
		--arch) arch="$1"; shift ;; # for adding "--arch" to debuerreotype-init
		--) break ;;
		*) eusage "unknown flag '$flag'" ;;
	esac
done

outputDir="${1:-}"; shift || eusage 'missing output-dir'
suite="${1:-brewmaster}" # http://repo.steampowered.com/steamos/dists/

set -x

outputDir="$(readlink -ve "$outputDir")"

tmpDir="$(mktemp --directory --tmpdir "debuerreotype.$suite.XXXXXXXXXX")"
trap "$(printf 'rm -rf %q' "$tmpDir")" EXIT

export TZ='UTC' LC_ALL='C'

dpkgArch="${arch:-$(dpkg --print-architecture | awk -F- '{ print $NF }')}"

exportDir="$tmpDir/output"
archDir="$exportDir/steamos/$dpkgArch"
tmpOutputDir="$archDir/$suite"

mirror='http://repo.steampowered.com/steamos'

initArgs=(
	--arch "$dpkgArch"
	--non-debian

	--debootstrap-script jessie
	--include valve-archive-keyring
	--exclude debian-archive-keyring
)

if [ -s /usr/share/keyrings/valve-archive-keyring.pgp ]; then
	# https://salsa.debian.org/release-team/debian-archive-keyring/-/commit/17c653ad964a3e81519f83e1d3a0704be737e4f6
	# (which will hopefully happen for valve-archive-keyring eventually too 😭)
	keyring='/usr/share/keyrings/valve-archive-keyring.pgp'
else
	keyring='/usr/share/keyrings/valve-archive-keyring.gpg'
fi
if [ -f "$keyring" ]; then
	initArgs+=( --keyring "$keyring" )
else
	initArgs+=( --no-check-gpg )
fi

mkdir -p "$tmpOutputDir"

if [ -f "$keyring" ] && wget -O "$tmpOutputDir/InRelease" "$mirror/dists/$suite/InRelease"; then
	gpgv \
		--keyring "$keyring" \
		--output "$tmpOutputDir/Release" \
		"$tmpOutputDir/InRelease"
	[ -s "$tmpOutputDir/Release" ]
elif [ -f "$keyring" ] && wget -O "$tmpOutputDir/Release.gpg" "$mirror/dists/$suite/Release.gpg" && wget -O "$tmpOutputDir/Release" "$mirror/dists/$suite/Release"; then
	rm -f "$tmpOutputDir/InRelease" # remove wget leftovers
	gpgv \
		--keyring "$keyring" \
		"$tmpOutputDir/Release.gpg" \
		"$tmpOutputDir/Release"
	[ -s "$tmpOutputDir/Release" ]
else
	rm -f "$tmpOutputDir/InRelease" "$tmpOutputDir/Release.gpg" "$tmpOutputDir/Release" # remove wget leftovers
	echo >&2 "warning: failed to fetch either InRelease or Release.gpg+Release for '$suite' (from '$mirror')"
fi

initArgs+=(
	# disable merged-usr (for now?) due to the following compelling arguments:
	#  - https://bugs.debian.org/src:usrmerge ("dpkg-query" breaks, etc)
	#  - https://bugs.debian.org/914208 ("buildd" variant disables merged-usr still)
	#  - https://github.com/debuerreotype/docker-debian-artifacts/issues/60#issuecomment-461426406
	--no-merged-usr
)

rootfsDir="$tmpDir/rootfs"
debuerreotype-init "${initArgs[@]}" "$rootfsDir" "$suite" "$mirror"

debuerreotype-minimizing-config "$rootfsDir"

echo "deb $mirror $suite main contrib non-free" | tee "$rootfsDir/etc/apt/sources.list"
debuerreotype-apt-get "$rootfsDir" update -qq

debuerreotype-recalculate-epoch "$rootfsDir"
epoch="$(< "$rootfsDir/debuerreotype-epoch")"
touch_epoch() {
	while [ "$#" -gt 0 ]; do
		local f="$1"; shift
		touch --no-dereference --date="@$epoch" "$f"
	done
}
touch_epoch "$rootfsDir/etc/apt/sources.list"

aptVersion="$("$DEBUERREOTYPE_DIRECTORY/scripts/.apt-version.sh" "$rootfsDir")"
if dpkg --compare-versions "$aptVersion" '>=' '1.1~'; then
	debuerreotype-apt-get "$rootfsDir" full-upgrade -yqq
else
	debuerreotype-apt-get "$rootfsDir" dist-upgrade -yqq
fi

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
	debootstrapVersion="$(debootstrap --version)"
	debootstrapVersion="${debootstrapVersion#debootstrap }" # "debootstrap X.Y.Z" -> "X.Y.Z"
	echo "$debootstrapVersion" > "$targetBase.debootstrap-version"
	touch_epoch "$targetBase".{manifest,apt-dist,dpkg-arch,debuerreotype-*,debootstrap-version}

	for f in debian_version os-release apt/sources.list; do
		targetFile="$targetBase.$(basename "$f" | sed -r "s/[^a-zA-Z0-9_-]+/-/g")"
		if [ -e "$rootfs/etc/$f" ]; then
			cp "$rootfs/etc/$f" "$targetFile"
			touch_epoch "$targetFile"
		fi
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
