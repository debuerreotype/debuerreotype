#!/usr/bin/env bash
set -Eeuo pipefail

# # http://repo.steampowered.com/steamos/pool/main/v/valve-archive-keyring/?C=M&O=D
# RUN wget -O valve.deb 'http://repo.steampowered.com/steamos/pool/main/v/valve-archive-keyring/valve-archive-keyring_0.6+bsosc2_all.deb' \
# 	&& apt-get install -y ./valve.deb \
# 	&& rm valve.deb

debuerreotypeScriptsDir="$(which debuerreotype-init)"
debuerreotypeScriptsDir="$(readlink -vf "$debuerreotypeScriptsDir")"
debuerreotypeScriptsDir="$(dirname "$debuerreotypeScriptsDir")"

source "$debuerreotypeScriptsDir/.constants.sh" \
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

mirror='http://repo.steampowered.com/steamos'

exportDir="$tmpDir/output"
archDir="$exportDir/steamos/$dpkgArch"
tmpOutputDir="$archDir/$suite"

keyring='/usr/share/keyrings/valve-archive-keyring.gpg'

mkdir -p "$tmpOutputDir"
if wget -O "$tmpOutputDir/InRelease" "$mirror/dists/$suite/InRelease" && [ -f "$keyring" ]; then
	gpgv \
		--keyring "$keyring" \
		--output "$tmpOutputDir/Release" \
		"$tmpOutputDir/InRelease"
else
	rm -f "$tmpOutputDir/InRelease" # remove wget leftovers
	wget -O "$tmpOutputDir/Release.gpg" "$mirror/dists/$suite/Release.gpg"
	wget -O "$tmpOutputDir/Release" "$mirror/dists/$suite/Release"
	if [ -f "$keyring" ]; then
		gpgv \
			--keyring "$keyring" \
			"$tmpOutputDir/Release.gpg" \
			"$tmpOutputDir/Release"
	fi
fi

initArgs=(
	--arch "$dpkgArch"
	--non-debian
)
if [ -f "$keyring" ]; then
	initArgs+=( --keyring "$keyring" )
else
	initArgs+=( --no-check-gpg )
fi
initArgs+=(
	# disable merged-usr (for now?) due to the following compelling arguments:
	#  - https://bugs.debian.org/src:usrmerge ("dpkg-query" breaks, etc)
	#  - https://bugs.debian.org/914208 ("buildd" variant disables merged-usr still)
	#  - https://github.com/debuerreotype/docker-debian-artifacts/issues/60#issuecomment-461426406
	--no-merged-usr

	--debootstrap-script /usr/share/debootstrap/scripts/jessie
	--include valve-archive-keyring
	--exclude debian-archive-keyring
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
