#!/usr/bin/env bash
set -Eeuo pipefail

source "$DEBUERREOTYPE_DIRECTORY/scripts/.constants.sh" \
	--flags 'codename-copy' \
	--flags 'eol,ports' \
	--flags 'arch:' \
	--flags 'include:,exclude:' \
	-- \
	'[--codename-copy] [--eol] [--ports] [--arch=<arch>] <output-dir> <suite> <timestamp>' \
	'output stretch 2017-05-08T00:00:00Z
--codename-copy output stable 2017-05-08T00:00:00Z
--eol output squeeze 2016-03-14T00:00:00Z
--eol --arch i386 output sarge 2016-03-14T00:00:00Z'

eval "$dgetopt"
codenameCopy=
eol=
ports=
include=
exclude=
arch=
while true; do
	flag="$1"; shift
	dgetopt-case "$flag"
	case "$flag" in
		--codename-copy) codenameCopy=1 ;; # for copying a "stable.tar.xz" to "stretch.tar.xz" with updated sources.list (saves a lot of extra building work)
		--eol) eol=1 ;; # for using "archive.debian.org"
		--ports) ports=1 ;; # for using "debian-ports"
		--arch) arch="$1"; shift ;; # for adding "--arch" to debuerreotype-init
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

outputDir="$(readlink -ve "$outputDir")"

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
	if ! mirrors="$("$DEBUERREOTYPE_DIRECTORY/scripts/.debian-mirror.sh" "${mirrorArgs[@]}")"; then
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

# TODO decouple this from GnuPG 🙈 (does "sop" have everything we need?)
export GNUPGHOME="$tmpDir/gnupg"
mkdir -p "$GNUPGHOME"
keyring="$tmpDir/debian-archive-$suite-keyring.pgp"
if [ "$suite" = 'slink' ]; then
	# slink (2.1) introduced apt, but without PGP 😅
	initArgs+=( --no-check-gpg )
elif [ "$suite" = 'potato' ]; then
	# src:debian-archive-keyring was created in 2006, thus does not include a key for potato (2.2; EOL in 2003)
	gpg --batch --no-default-keyring --keyring "$keyring" \
		--keyserver keyserver.ubuntu.com \
		--recv-keys 8FD47FF1AA9372C37043DC28AA7DEB7B722F1AED
	initArgs+=( --keyring "$keyring" )
else
	# https://salsa.debian.org/release-team/debian-archive-keyring/-/commit/17c653ad964a3e81519f83e1d3a0704be737e4f6
	if [ -s /usr/share/keyrings/debian-archive-keyring.pgp ]; then
		ext='pgp'
	else
		ext='gpg'
	fi
	# check against all releases (ie, combine both "debian-archive-keyring.pgp" and "debian-archive-removed-keys.pgp"), since we cannot really know whether the target release became EOL later than the snapshot date we are targeting
	gpg --batch --no-default-keyring --keyring "$keyring" --import \
		"/usr/share/keyrings/debian-archive-keyring.$ext" \
		"/usr/share/keyrings/debian-archive-removed-keys.$ext"
	if [ -n "$ports" ]; then
		gpg --batch --no-default-keyring --keyring "$keyring" --import \
			"/usr/share/keyrings/debian-ports-archive-keyring.$ext" \
			"/usr/share/keyrings/debian-ports-archive-keyring-removed.$ext"
	fi
	initArgs+=( --keyring "$keyring" )
fi

mkdir -p "$tmpOutputDir"

# TODO decouple this from gpgv (perhaps lean on sopv so the underlying implementation matters less?)
mirror="$(< "$archDir/snapshot-url")"
if [ -f "$keyring" ] && wget -O "$tmpOutputDir/InRelease" "$mirror/dists/$suite/InRelease"; then
	gpgv \
		3>"$tmpDir/gpgv-status.txt" \
		--status-fd 3 \
		--keyring "$keyring" \
		--output "$tmpOutputDir/Release" \
		"$tmpOutputDir/InRelease"
	[ -s "$tmpOutputDir/Release" ]
elif [ -f "$keyring" ] && wget -O "$tmpOutputDir/Release.gpg" "$mirror/dists/$suite/Release.gpg" && wget -O "$tmpOutputDir/Release" "$mirror/dists/$suite/Release"; then
	rm -f "$tmpOutputDir/InRelease" # remove wget leftovers
	gpgv \
		3>"$tmpDir/gpgv-status.txt" \
		--status-fd 3 \
		--keyring "$keyring" \
		"$tmpOutputDir/Release.gpg" \
		"$tmpOutputDir/Release"
	[ -s "$tmpOutputDir/Release" ]
elif [ "$suite" = 'slink' ]; then
	# "Release" files were introduced in potato (2.2+)
	rm -f "$tmpOutputDir/InRelease" "$tmpOutputDir/Release.gpg" "$tmpOutputDir/Release" # remove wget leftovers
else
	echo >&2 "error: failed to fetch either InRelease or Release.gpg+Release for '$suite' (from '$mirror')"
	exit 1
fi
codename=
if [ -f "$tmpOutputDir/Release" ]; then
	codename="$(awk -F ': ' '$1 == "Codename" { print $2; exit }' "$tmpOutputDir/Release")"
fi
if [ -n "$codenameCopy" ] && [ "$codename" = "$suite" ]; then
	# if codename already is the same as suite, then making a copy does not make any sense
	codenameCopy=
fi
if [ -n "$codenameCopy" ] && [ -z "$codename" ]; then
	echo >&2 "error: --codename-copy specified but we failed to get a Codename for $suite"
	exit 1
fi

if [ "${codename:-$suite}" = 'jessie' ]; then
	# https://bugs.debian.org/764204 "apt-cache calls fcntl() on 65536 FDs"
	# https://bugs.launchpad.net/bugs/1332440 "apt-get update very slow when ulimit -n is big"
	ulimit -n 1024
	# I contemplated/played with adding this to "debuerreotype-apt-get" instead with a test on aptVersion >= 1.0.9.2 and < 1.1~exp9 (for safety), but it's really needed during debootstrap too ("Configuring apt" / "Setting up apt" hangs), and jessie is the only Debian release affected, so this is a simpler/cleaner test anyhow
fi

# apply merged-/usr (for bookworm+)
# https://lists.debian.org/debian-ctte/2022/07/msg00034.html
# https://github.com/debuerreotype/docker-debian-artifacts/issues/131#issuecomment-1190233249
case "${codename:-$suite}" in
	# this has to be a full codename list because we don't have aptVersion available yet because there's no APT yet 🙈
	slink | potato | woody | sarge | etch | lenny | squeeze | wheezy | jessie | stretch | buster | bullseye)
		initArgs+=( --no-merged-usr )
		;;

	*)
		epochUsrIsMerged="$(date --date '2022-07-24 00:00:00' +%s)" # https://tracker.debian.org/news/1348264/usrmerge-29-migrated-to-testing/ ("usr-is-merged" binary package exists in bookworm+)
		if [ "$epoch" -lt "$epochUsrIsMerged" ]; then
			initArgs+=( --no-merged-usr --exclude=usr-is-merged )
			# explicit --exclude for https://github.com/debuerreotype/debuerreotype/issues/140
		else
			initArgs+=( --merged-usr )
			debootstrap="$(command -v debootstrap)"
			if ! grep -q EXCLUDE_DEPENDENCY "$debootstrap" || ! grep -q EXCLUDE_DEPENDENCY "${DEBOOTSTRAP_DIR:-/usr/share/debootstrap}/functions"; then
				cat >&2 <<-'EOERR'
					error: debootstrap missing necessary patches; see:
					  - https://salsa.debian.org/installer-team/debootstrap/-/merge_requests/76
					  - https://salsa.debian.org/installer-team/debootstrap/-/merge_requests/81
				EOERR
				exit 1
			fi
		fi
		;;
esac

if [ -n "$include" ]; then
	initArgs+=( --include="$include" )
fi
if [ -n "$exclude" ]; then
	initArgs+=( --exclude="$exclude" )
fi

rootfsDir="$tmpDir/rootfs"
debuerreotype-init "${initArgs[@]}" "$rootfsDir" "$suite" "@$epoch"

aptVersion="$("$DEBUERREOTYPE_DIRECTORY/scripts/.apt-version.sh" "$rootfsDir")"

# regenerate sources.list to make the deb822/line-based opinion explicit
# https://lists.debian.org/debian-devel/2021/11/msg00026.html
sourcesListArgs=()
[ -z "$eol" ] || sourcesListArgs+=( --eol )
[ -z "$ports" ] || sourcesListArgs+=( --ports )
if dpkg --compare-versions "$aptVersion" '>=' '2.3~'; then
	sourcesListArgs+=( --deb822 )
	sourcesListFile='/etc/apt/sources.list.d/debian.sources'
else
	sourcesListArgs+=( --no-deb822 )
	sourcesListFile='/etc/apt/sources.list'
fi
debuerreotype-debian-sources-list "${sourcesListArgs[@]}" --snapshot "$rootfsDir" "$suite"
[ -s "$rootfsDir$sourcesListFile" ] # trust, but verify

addGpgvIgnore= # whether to invoke "debuerreotype-gpgv-ignore-expiration-config"
excludeGpgvIgnore= # whether to let the "gpgv-ignore-expiration" script/config stay in the final image
if [ -n "$eol" ]; then
	# if we're building this rootfs *expecting* it to be EOL, we should always include the gpgv hacks in the final output
	addGpgvIgnore=1
elif [ -s "$tmpDir/gpgv-status.txt" ] && grep -F '[GNUPG:] EXPKEYSIG ' "$tmpDir/gpgv-status.txt"; then
	# if we are *not* expecting this rootfs to be EOL but the key is expired, we need to include the gpgv hacks to build it successfully, but then want to *not* include them in the final output
	addGpgvIgnore=1
	excludeGpgvIgnore=1
fi

if [ -n "$addGpgvIgnore" ]; then
	# TODO in order for this to work, we *also* need to explicitly install "gpgv" (it's transitively-essential in bookworm and gone in trixie+)
	debuerreotype-gpgv-ignore-expiration-config "$rootfsDir"
fi

debuerreotype-minimizing-config "$rootfsDir"

debuerreotype-apt-get "$rootfsDir" update -qq

if dpkg --compare-versions "$aptVersion" '>=' '1.1~'; then
	debuerreotype-apt-get "$rootfsDir" full-upgrade -yqq
else
	debuerreotype-apt-get "$rootfsDir" dist-upgrade -yqq
fi

if dpkg --compare-versions "$aptVersion" '>=' '0.7.14~'; then
	# https://salsa.debian.org/apt-team/apt/commit/06d79436542ccf3e9664306da05ba4c34fba4882
	noInstallRecommends='--no-install-recommends'
else
	# etch (4.0) and lower do not support --no-install-recommends
	noInstallRecommends='-o APT::Install-Recommends=0'
fi

if [ -n "$eol" ] && dpkg --compare-versions "$aptVersion" '>=' '0.7.26~'; then
	# https://salsa.debian.org/apt-team/apt/commit/1ddb859611d2e0f3d9ea12085001810f689e8c99
	echo 'Acquire::Check-Valid-Until "false";' > "$rootfsDir"/etc/apt/apt.conf.d/check-valid-until.conf
	# TODO make this a real script so it can have a nice comment explaining why we do it for EOL releases?
fi

# copy the rootfs to create other variants
mkdir "$rootfsDir"-slim
tar -cC "$rootfsDir" . | tar -xC "$rootfsDir"-slim

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
		# if we already have "ping" (as in potato, 2.2), skip installing any extra ping package
		ping=
	fi
	debuerreotype-apt-get "$rootfsDir" install -y $noInstallRecommends $ping $iproute
fi

debuerreotype-slimify "$rootfsDir"-slim

_sanitize_basename() {
	local f="$1"; shift

	f="$(basename "$f")"
	f="$(sed -r -e 's/[^a-zA-Z0-9_-]+/-/g' <<<"$f")"

	echo "$f"
}
sourcesListBase="$(_sanitize_basename "$sourcesListFile")"

create_artifacts() {
	local targetBase="$1"; shift
	local rootfs="$1"; shift
	local suite="$1"; shift
	local variant="$1"; shift

	# make a copy of the snapshot-facing sources.list file before we overwrite it
	cp "$rootfs$sourcesListFile" "$targetBase.$sourcesListBase-snapshot"
	touch_epoch "$targetBase.$sourcesListBase-snapshot"

	debuerreotype-debian-sources-list "${sourcesListArgs[@]}" "$rootfs" "$suite"

	local tarArgs=(
		# https://www.freedesktop.org/software/systemd/man/machine-id.html
		--exclude ./etc/machine-id
		# "debuerreotype-fixup" will make this an empty file for reproducibility, but for our Docker images it seems more appropriate for it to not exist (since they've never actually been "booted" so having the "first boot" logic trigger if someone were to run systemd in them conceptually makes sense)
	)

	case "$suite" in
		sarge) # 3.1
			# for some reason, sarge creates "/var/cache/man/index.db" with some obvious embedded unix timestamps (but if we exclude it, "man" still works properly, so *shrug*)
			tarArgs+=( --exclude ./var/cache/man/index.db )
			;;

		woody) # 3.0
			# woody not only contains "exim", but launches it during our build process and tries to email "root@debuerreotype" (which fails and creates non-reproducibility)
			tarArgs+=( --exclude ./var/spool/exim --exclude ./var/log/exim )
			;;

		potato) # 2.2
			tarArgs+=(
				# for some reason, pototo leaves a core dump (TODO figure out why??)
				--exclude './core'
				# also, it leaves some junk in /tmp (/tmp/fdmount.conf.tmp.XXX)
				--exclude './tmp/fdmount.conf.tmp.*'
			)
			;;

		slink) # 2.1
			tarArgs+=(
				# same as potato :(
				--exclude './tmp/fdmount.conf.tmp.*'
			)
			;;
	esac

	if [ ! -e "$rootfs/usr/share/doc/usr-is-merged/copyright" ] && [ -e "$rootfs/etc/unsupported-skip-usrmerge-conversion" ]; then
		# if we have the "/etc/unsupported-skip-usrmerge-conversion" file but not the "usr-is-merged" package, we should be safe to remove the "unsupported configuration" flag file (see "epochUsrIsMerged" section above, specifically the "--exclude=usr-is-merged" case)
		tarArgs+=( --exclude './etc/unsupported-skip-usrmerge-conversion' )
	fi

	if [ -n "$excludeGpgvIgnore" ]; then
		# this list needs to stay in sync with "scripts/debuerreotype-gpgv-ignore-expiration-config"
		tarArgs+=(
			--exclude './usr/local/bin/.debuerreotype-gpgv-ignore-expiration'
			--exclude './etc/apt/apt.conf.d/debuerreotype-gpgv-ignore-expiration'
		)
	fi

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
	echo "$suite" > "$targetBase.apt-dist"
	echo "$dpkgArch" > "$targetBase.dpkg-arch"
	echo "$epoch" > "$targetBase.debuerreotype-epoch"
	echo "$variant" > "$targetBase.debuerreotype-variant"
	debuerreotype-version > "$targetBase.debuerreotype-version"
	debootstrapVersion="$(debootstrap --version)"
	debootstrapVersion="${debootstrapVersion#debootstrap }" # "debootstrap X.Y.Z" -> "X.Y.Z"
	echo "$debootstrapVersion" > "$targetBase.debootstrap-version"
	touch_epoch "$targetBase".{manifest,apt-dist,dpkg-arch,debuerreotype-*,debootstrap-version}

	for f in /etc/debian_version /etc/os-release "$sourcesListFile"; do
		targetFile="$(_sanitize_basename "$f")"
		targetFile="$targetBase.$targetFile"
		if [ -e "$rootfs$f" ]; then
			# /etc/os-release does not exist in --debian-eol squeeze, for example (hence the existence check)
			cp "$rootfs$f" "$targetFile"
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
