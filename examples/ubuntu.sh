#!/usr/bin/env bash
set -Eeuo pipefail

# RUN apt-get update \
# 	&& apt-get install -y ubuntu-keyring \
# 	&& rm -rf /var/lib/apt/lists/*

debuerreotypeScriptsDir="$(which debuerreotype-init)"
debuerreotypeScriptsDir="$(readlink -vf "$debuerreotypeScriptsDir")"
debuerreotypeScriptsDir="$(dirname "$debuerreotypeScriptsDir")"

source "$debuerreotypeScriptsDir/.constants.sh" \
	--flags 'eol' \
	--flags 'arch:' \
	-- \
	'[--eol] [--arch=<arch>] <output-dir> <suite>' \
	'output xenial
--eol --arch armhf output cosmic
--arch arm64 output bionic'

eval "$dgetopt"
eol=
arch=
while true; do
	flag="$1"; shift
	dgetopt-case "$flag"
	case "$flag" in
		--eol) eol=1 ;; # for using "old-releases.ubuntu.com"
		--arch) arch="$1"; shift ;; # for adding "--arch" to debuerreotype-init
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

dpkgArch="${arch:-$(dpkg --print-architecture | awk -F- '{ print $NF }')}"

exportDir="$tmpDir/output"
archDir="$exportDir/ubuntu/$dpkgArch"
tmpOutputDir="$archDir/$suite"

if [ -z "$eol" ]; then
	case "$dpkgArch" in
		amd64 | i386)
			mirror='http://archive.ubuntu.com/ubuntu'
			secmirror='http://security.ubuntu.com/ubuntu'
			;;

		*)
			mirror='http://ports.ubuntu.com/ubuntu-ports'
			secmirror="$mirror" # no separate security mirror for ports
			;;
	esac
else
	mirror='http://old-releases.ubuntu.com/ubuntu'
	secmirror="$mirror" # no separate security mirror for old releases
fi

initArgs=(
	--arch "$dpkgArch"
	--non-debian
)

export GNUPGHOME="$tmpDir/gnupg"
mkdir -p "$GNUPGHOME"
keyring="$tmpDir/ubuntu-archive-$suite-keyring.gpg"
# check against all releases (ie, combine both "ubuntu-archive-keyring.gpg" and "ubuntu-archive-removed-keys.gpg"), since we cannot really know whether the target release became EOL later than the snapshot date we are targeting
gpg --batch --no-default-keyring --keyring "$keyring" --import \
	/usr/share/keyrings/ubuntu-archive-keyring.gpg \
	/usr/share/keyrings/ubuntu-archive-removed-keys.gpg
initArgs+=( --keyring "$keyring" )

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
	echo >&2 "error: failed to fetch either InRelease or Release.gpg+Release for '$suite' (from '$mirror')"
	exit 1
fi

initArgs+=(
	# disable merged-usr (for now?) due to the following compelling arguments:
	#  - https://bugs.debian.org/src:usrmerge ("dpkg-query" breaks, etc)
	#  - https://bugs.debian.org/914208 ("buildd" variant disables merged-usr still)
	#  - https://github.com/debuerreotype/docker-debian-artifacts/issues/60#issuecomment-461426406
	--no-merged-usr
)

# Debian may not support the latest Ubuntu release yet.
script="${DEBOOTSTRAP_DIR:-/usr/share/debootstrap}/scripts/$suite"
if [ ! -e "$script" ]; then
	initArgs+=(--debootstrap-script "${script%/*}/gutsy")
fi

rootfsDir="$tmpDir/rootfs"
debuerreotype-init "${initArgs[@]}" "$rootfsDir" "$suite" "$mirror"

debuerreotype-minimizing-config "$rootfsDir"

# setup "proper" sources.list
tee "$rootfsDir/etc/apt/sources.list" <<-EOS
	deb $mirror $suite main restricted universe multiverse
	deb $mirror $suite-updates main restricted universe multiverse
	deb $mirror $suite-backports main restricted universe multiverse
	deb $secmirror $suite-security main restricted universe multiverse
EOS
# TODO make components list a script flag?  backports?
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

aptVersion="$("$debuerreotypeScriptsDir/.apt-version.sh" "$rootfsDir")"
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
ping=iputils-ping
if ! (debuerreotype-chroot "$rootfsDir" apt-cache policy iputils-ping 2>/dev/null | grep -E '^ [ *]{3} [0-9].*'); then
	# iputils-ping:i386 became unavailable since Focal.
	ping=
fi
debuerreotype-apt-get "$rootfsDir" install -y --no-install-recommends $ping $iproute

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
