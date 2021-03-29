#!/usr/bin/env bash
set -Eeuo pipefail

debuerreotypeScriptsDir="$(which debuerreotype-init)"
debuerreotypeScriptsDir="$(readlink -f "$debuerreotypeScriptsDir")"
debuerreotypeScriptsDir="$(dirname "$debuerreotypeScriptsDir")"

source "$debuerreotypeScriptsDir/.constants.sh" \
	--flags 'codename-copy,sbuild' \
	--flags 'eol,ports' \
	--flags 'arch:,qemu' \
	--flags 'include:,exclude:' \
	-- \
	'[--codename-copy] [--sbuild] [--eol] [--ports] [--arch=<arch>] [--qemu] <output-dir> <suite> <timestamp>' \
	'output stretch 2017-05-08T00:00:00Z
--codename-copy output stable 2017-05-08T00:00:00Z
--eol output squeeze 2016-03-14T00:00:00Z
--eol --arch i386 output sarge 2016-03-14T00:00:00Z'

eval "$dgetopt"
codenameCopy=
eol=
ports=
sbuild=
include=
exclude=
arch=
qemu=
while true; do
	flag="$1"; shift
	dgetopt-case "$flag"
	case "$flag" in
		--codename-copy) codenameCopy=1 ;; # for copying a "stable.tar.xz" to "stretch.tar.xz" with updated sources.list (saves a lot of extra building work)
		--sbuild) sbuild=1 ;; # for building "sbuild" compatible tarballs as well
		--eol) eol=1 ;; # for using "archive.debian.org"
		--ports) ports=1 ;; # for using "debian-ports"
		--arch) arch="$1"; shift ;; # for adding "--arch" to debuerreotype-init
		--qemu) qemu=1 ;; # for using "qemu-debootstrap"
		--include) include="${include:+$include,}$1"; shift ;;
		--exclude) exclude="${exclude:+$exclude,}$1"; shift ;;
		--) break ;;
		*) eusage "unknown flag '$flag'" ;;
	esac
done

outputDir="${1:-}"; shift || eusage 'missing output-dir'
suite="${1:-}"; shift || eusage 'missing suite'
timestamp="${1:-}"; shift || eusage 'missing timestamp'

set -x

outputDir="$(readlink -e "$outputDir")"

tmpDir="$(mktemp --directory --tmpdir "debuerreotype.$suite.XXXXXXXXXX")"
trap "$(printf 'rm -rf %q' "$tmpDir")" EXIT

export TZ='UTC' LC_ALL='C'

epoch="$(date --date "$timestamp" +%s)"
serial="$(date --date "@$epoch" +%Y%m%d)"
dpkgArch="${arch:-$(dpkg --print-architecture | awk -F- '{ print $NF }')}"

exportDir="$tmpDir/output"
archDir="$exportDir/$serial/$dpkgArch"
tmpOutputDir="$archDir/$suite"

touch_epoch() {
	while [ "$#" -gt 0 ]; do
		local f="$1"; shift
		touch --no-dereference --date="@$epoch" "$f"
	done
}

for archive in '' security; do
	snapshotUrlFile="$archDir/snapshot-url${archive:+-${archive}}"
	mirrorArgs=()
	if [ -n "$ports" ]; then
		mirrorArgs+=( --ports )
	fi
	if [ -n "$eol" ]; then
		mirrorArgs+=( --eol )
	fi
	mirrorArgs+=( "@$epoch" "$suite${archive:+-$archive}" "$dpkgArch" main )
	if ! mirrors="$("$debuerreotypeScriptsDir/.debian-mirror.sh" "${mirrorArgs[@]}")"; then
		if [ "$archive" = 'security' ]; then
			# if we fail to find the security mirror, we're probably not security supported (which is ~fine)
			continue
		else
			exit 1
		fi
	fi
	eval "$mirrors"
	[ -n "$snapshotMirror" ]
	snapshotUrlDir="$(dirname "$snapshotUrlFile")"
	mkdir -p "$snapshotUrlDir"
	echo "$snapshotMirror" > "$snapshotUrlFile"
	touch_epoch "$snapshotUrlFile"
done

export GNUPGHOME="$tmpDir/gnupg"
mkdir -p "$GNUPGHOME"
keyring="$tmpDir/debian-archive-$suite-keyring.gpg"
if [ "$suite" = potato ]; then
	# src:debian-archive-keyring was created in 2006, thus does not include a key for potato
	gpg --batch --no-default-keyring --keyring "$keyring" \
		--keyserver ha.pool.sks-keyservers.net \
		--recv-keys 8FD47FF1AA9372C37043DC28AA7DEB7B722F1AED
else
	# check against all releases (ie, combine both "debian-archive-keyring.gpg" and "debian-archive-removed-keys.gpg"), since we cannot really know whether the target release became EOL later than the snapshot date we are targeting
	gpg --batch --no-default-keyring --keyring "$keyring" --import \
		/usr/share/keyrings/debian-archive-keyring.gpg \
		/usr/share/keyrings/debian-archive-removed-keys.gpg

	if [ -n "$ports" ]; then
		gpg --batch --no-default-keyring --keyring "$keyring" --import \
			/usr/share/keyrings/debian-ports-archive-keyring.gpg \
			/usr/share/keyrings/debian-ports-archive-keyring-removed.gpg
	fi
fi

snapshotUrl="$(< "$archDir/snapshot-url")"
mkdir -p "$tmpOutputDir"
if wget -O "$tmpOutputDir/InRelease" "$snapshotUrl/dists/$suite/InRelease"; then
	gpgv \
		--keyring "$keyring" \
		--output "$tmpOutputDir/Release" \
		"$tmpOutputDir/InRelease"
else
	rm -f "$tmpOutputDir/InRelease" # remove wget leftovers
	wget -O "$tmpOutputDir/Release.gpg" "$snapshotUrl/dists/$suite/Release.gpg"
	wget -O "$tmpOutputDir/Release" "$snapshotUrl/dists/$suite/Release"
	gpgv \
		--keyring "$keyring" \
		"$tmpOutputDir/Release.gpg" \
		"$tmpOutputDir/Release"
fi

codename="$(awk -F ': ' '$1 == "Codename" { print $2; exit }' "$tmpOutputDir/Release")"
if [ -n "$codenameCopy" ] && [ "$codename" = "$suite" ]; then
	# if codename already is the same as suite, then making a copy does not make any sense
	codenameCopy=
fi
if [ -n "$codenameCopy" ] && [ -z "$codename" ]; then
	echo >&2 "error: --codename-copy specified but we failed to get a Codename for $suite"
	exit 1
fi

initArgs=(
	--arch "$dpkgArch"
)
if [ -z "$eol" ]; then
	initArgs+=( --debian )
else
	initArgs+=( --debian-eol )
fi
if [ -n "$ports" ]; then
	initArgs+=(
		--debian-ports
		--include=debian-ports-archive-keyring
	)
fi
initArgs+=(
	--keyring "$keyring"

	# disable merged-usr (for now?) due to the following compelling arguments:
	#  - https://bugs.debian.org/src:usrmerge ("dpkg-query" breaks, etc)
	#  - https://bugs.debian.org/914208 ("buildd" variant disables merged-usr still)
	#  - https://github.com/debuerreotype/docker-debian-artifacts/issues/60#issuecomment-461426406
	--no-merged-usr
)

if [ -n "$qemu" ]; then
	initArgs+=( --debootstrap=qemu-debootstrap )
fi

if [ -n "$include" ]; then
	initArgs+=( --include="$include" )
fi
if [ -n "$exclude" ]; then
	initArgs+=( --exclude="$exclude" )
fi

rootfsDir="$tmpDir/rootfs"
debuerreotype-init "${initArgs[@]}" "$rootfsDir" "$suite" "@$epoch"

if [ -n "$eol" ]; then
	debuerreotype-gpgv-ignore-expiration-config "$rootfsDir"
fi

debuerreotype-minimizing-config "$rootfsDir"
debuerreotype-apt-get "$rootfsDir" update -qq
debuerreotype-apt-get "$rootfsDir" dist-upgrade -yqq

aptVersion="$("$debuerreotypeScriptsDir/.apt-version.sh" "$rootfsDir")"
if dpkg --compare-versions "$aptVersion" '>=' '0.7.14~'; then
	# https://salsa.debian.org/apt-team/apt/commit/06d79436542ccf3e9664306da05ba4c34fba4882
	noInstallRecommends='--no-install-recommends'
else
	# --debian-eol etch and lower do not support --no-install-recommends
	noInstallRecommends='-o APT::Install-Recommends=0'
fi

if [ -n "$eol" ] && dpkg --compare-versions "$aptVersion" '>=' '0.7.26~'; then
	# https://salsa.debian.org/apt-team/apt/commit/1ddb859611d2e0f3d9ea12085001810f689e8c99
	echo 'Acquire::Check-Valid-Until "false";' > "$rootfsDir"/etc/apt/apt.conf.d/check-valid-until.conf
	# TODO make this a real script so it can have a nice comment explaining why we do it for EOL releases?
fi

# make a couple copies of rootfs so we can create other variants
mkdir "$rootfsDir"-slim
tar -cC "$rootfsDir" . | tar -xC "$rootfsDir"-slim
if [ -n "$sbuild" ]; then
	mkdir "$rootfsDir"-sbuild
	tar -cC "$rootfsDir" . | tar -xC "$rootfsDir"-sbuild
fi

# for historical reasons (related to their usefulness in debugging non-working container networking in container early days before "--network container:xxx"), Debian 10 and older non-slim images included both "ping" and "ip" above "minbase", but in 11+ (Bullseye), that will no longer be the case and we will instead be a faithful minbase again :D
epoch2021="$(date --date '2021-01-01 00:00:00' +%s)"
if [ "$epoch" -lt "$epoch2021" ] || { isDebianBusterOrOlder="$([ -f "$rootfsDir/etc/os-release" ] && source "$rootfsDir/etc/os-release" && [ -n "${VERSION_ID:-}" ] && [ "${VERSION_ID%%.*}" -le 10 ] && echo 1)" && [ -n "$isDebianBusterOrOlder" ]; }; then
	# prefer iproute2 if it exists
	iproute=iproute2
	if ! debuerreotype-apt-get "$rootfsDir" install -qq -s iproute2 &> /dev/null; then
		# poor wheezy
		iproute=iproute
	fi
	ping=iputils-ping
	if debuerreotype-chroot "$rootfsDir" bash -c 'command -v ping > /dev/null'; then
		# if we already have "ping" (as in --debian-eol potato), skip installing any extra ping package
		ping=
	fi
	debuerreotype-apt-get "$rootfsDir" install -y $noInstallRecommends $ping $iproute
fi

debuerreotype-slimify "$rootfsDir"-slim

if [ -n "$sbuild" ]; then
	# this should match the list added to the "buildd" variant in debootstrap and the list installed by sbuild
	# https://salsa.debian.org/installer-team/debootstrap/blob/da5f17904de373cd7a9224ad7cd69c80b3e7e234/scripts/debian-common#L20
	# https://salsa.debian.org/debian/sbuild/blob/fc306f4be0d2c57702c5e234273cd94b1dba094d/bin/sbuild-createchroot#L257-260
	debuerreotype-apt-get "$rootfsDir"-sbuild install -y $noInstallRecommends build-essential fakeroot
fi

sourcesListArgs=()
[ -z "$eol" ] || sourcesListArgs+=( --eol )
[ -z "$ports" ] || sourcesListArgs+=( --ports )

create_artifacts() {
	local targetBase="$1"; shift
	local rootfs="$1"; shift
	local suite="$1"; shift
	local variant="$1"; shift

	# make a copy of the snapshot-facing sources.list file before we overwrite it
	cp "$rootfs/etc/apt/sources.list" "$targetBase.sources-list-snapshot"
	touch_epoch "$targetBase.sources-list-snapshot"

	local tarArgs=()
	if [ -n "$qemu" ]; then
		tarArgs+=( --exclude='./usr/bin/qemu-*-static' )
	fi

	if [ "$variant" != 'sbuild' ]; then
		debuerreotype-debian-sources-list "${sourcesListArgs[@]}" "$rootfs" "$suite"
	else
		# sbuild needs "deb-src" entries
		debuerreotype-debian-sources-list --deb-src "${sourcesListArgs[@]}" "$rootfs" "$suite"

		# APT has odd issues with "Acquire::GzipIndexes=false" + "file://..." sources sometimes
		# (which are used in sbuild for "--extra-package")
		#   Could not open file /var/lib/apt/lists/partial/_tmp_tmp.ODWljpQfkE_._Packages - open (13: Permission denied)
		#   ...
		#   E: Failed to fetch store:/var/lib/apt/lists/partial/_tmp_tmp.ODWljpQfkE_._Packages  Could not open file /var/lib/apt/lists/partial/_tmp_tmp.ODWljpQfkE_._Packages - open (13: Permission denied)
		rm -f "$rootfs/etc/apt/apt.conf.d/docker-gzip-indexes"
		# TODO figure out the bug and fix it in APT instead /o\

		# schroot is picky about "/dev" (which is excluded by default in "debuerreotype-tar")
		# see https://github.com/debuerreotype/debuerreotype/pull/8#issuecomment-305855521
		tarArgs+=( --include-dev )
	fi

	case "$suite" in
		sarge)
			# for some reason, sarge creates "/var/cache/man/index.db" with some obvious embedded unix timestamps (but if we exclude it, "man" still works properly, so *shrug*)
			tarArgs+=( --exclude ./var/cache/man/index.db )
			;;

		woody)
			# woody not only contains "exim", but launches it during our build process and tries to email "root@debuerreotype" (which fails and creates non-reproducibility)
			tarArgs+=( --exclude ./var/spool/exim --exclude ./var/log/exim )
			;;

		potato)
			tarArgs+=(
				# for some reason, pototo leaves a core dump (TODO figure out why??)
				--exclude './core'
				--exclude './qemu*.core'
				# also, it leaves some junk in /tmp (/tmp/fdmount.conf.tmp.XXX)
				--exclude './tmp/fdmount.conf.tmp.*'
			)
			;;
	esac

	debuerreotype-tar "${tarArgs[@]}" "$rootfs" "$targetBase.tar.xz"
	du -hsx "$targetBase.tar.xz"

	sha256sum "$targetBase.tar.xz" | cut -d' ' -f1 > "$targetBase.tar.xz.sha256"
	touch_epoch "$targetBase.tar.xz.sha256"

	debuerreotype-chroot "$rootfs" bash -c '
		if ! dpkg-query -W 2> /dev/null; then
			# --debian-eol woody has no dpkg-query
			dpkg -l
		fi
	' > "$targetBase.manifest"
	echo "$epoch" > "$targetBase.debuerreotype-epoch"
	debuerreotype-version > "$targetBase.debuerreotype-version"
	touch_epoch "$targetBase.manifest" "$targetBase.debuerreotype-epoch" "$targetBase.debuerreotype-version"

	for f in debian_version os-release apt/sources.list; do
		targetFile="$targetBase.$(basename "$f" | sed -r "s/[^a-zA-Z0-9_-]+/-/g")"
		if [ -e "$rootfs/etc/$f" ]; then
			# /etc/os-release does not exist in --debian-eol squeeze, for example (hence the existence check)
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

if [ -n "$codenameCopy" ]; then
	codenameDir="$archDir/$codename"
	mkdir -p "$codenameDir"
	tar -cC "$tmpOutputDir" --exclude='**/rootfs.*' . | tar -xC "$codenameDir"

	for rootfs in "$rootfsDir"*/; do
		rootfs="${rootfs%/}" # "../rootfs", "../rootfs-slim", ...

		variant="$(basename "$rootfs")" # "rootfs", "rootfs-slim", ...
		variant="${variant#rootfs}" # "", "-slim", ...
		variant="${variant#-}" # "", "slim", ...

		variantDir="$codenameDir/$variant"
		targetBase="$variantDir/rootfs"

		# point sources.list back at snapshot.debian.org temporarily (but this time pointing at $codename instead of $suite)
		debuerreotype-debian-sources-list --snapshot "${sourcesListArgs[@]}" "$rootfs" "$codename"

		create_artifacts "$targetBase" "$rootfs" "$codename" "$variant"
	done
fi

user="$(stat --format '%u' "$outputDir")"
group="$(stat --format '%g' "$outputDir")"
tar --create --directory="$exportDir" --owner="$user" --group="$group" . | tar --extract --verbose --directory="$outputDir"
