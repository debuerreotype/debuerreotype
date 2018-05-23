#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
source "$thisDir/scripts/.constants.sh" \
	--flags 'no-build,codename-copy' \
	--flags 'eol,arch:,qemu' \
	-- \
	'[--no-build] [--codename-copy] [--eol] [--arch=<arch>] [--qemu] <output-dir> <suite> <timestamp>' \
	'output stretch 2017-05-08T00:00:00Z
--codename-copy output stable 2017-05-08T00:00:00Z
--eol output squeeze 2016-03-14T00:00:00Z
--eol --arch i386 output sarge 2016-03-14T00:00:00Z' \

eval "$dgetopt"
build=1
codenameCopy=
eol=
arch=
qemu=
while true; do
	flag="$1"; shift
	dgetopt-case "$flag"
	case "$flag" in
		--no-build) build= ;; # for skipping "docker build"
		--codename-copy) codenameCopy=1 ;; # for copying a "stable.tar.xz" to "stretch.tar.xz" with updated sources.list (saves a lot of extra building work)
		--eol) eol=1 ;; # for using "archive.debian.org"
		--arch) arch="$1"; shift ;; # for adding "--arch" to debuerreotype-init
		--qemu) qemu=1 ;; # for using "qemu-debootstrap"
		--) break ;;
		*) eusage "unknown flag '$flag'" ;;
	esac
done

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

if [ "$suite" = 'potato' ]; then
	# --debian-eol potato wants to run "chroot ... mount ... /proc" which gets blocked (i386, ancient binaries, blah blah blah)
	securityArgs+=(
		--security-opt seccomp=unconfined
	)
fi

ver="$("$thisDir/scripts/debuerreotype-version")"
ver="${ver%% *}"
dockerImage="debuerreotype/debuerreotype:$ver"
[ -z "$build" ] || docker build -t "$dockerImage" "$thisDir"
if [ -n "$qemu" ]; then
	[ -z "$build" ] || docker build -t "$dockerImage-qemu" - <<-EODF
		FROM $dockerImage
		RUN apt-get update && apt-get install -y --no-install-recommends qemu-user-static && rm -rf /var/lib/apt/lists/*
	EODF
	dockerImage="$dockerImage-qemu"
fi

docker run \
	--rm \
	"${securityArgs[@]}" \
	--tmpfs /tmp:dev,exec,suid,noatime \
	-w /tmp \
	-e suite="$suite" \
	-e timestamp="$timestamp" \
	-e codenameCopy="$codenameCopy" \
	-e eol="$eol" -e arch="$arch" -e qemu="$qemu" \
	-e TZ='UTC' -e LC_ALL='C' \
	--hostname debuerreotype \
	"$dockerImage" \
	bash -Eeuo pipefail -c '
		set -x

		epoch="$(date --date "$timestamp" +%s)"
		serial="$(date --date "@$epoch" +%Y%m%d)"
		dpkgArch="${arch:-$(dpkg --print-architecture | awk -F- "{ print \$NF }")}"

		exportDir="output"
		outputDir="$exportDir/$serial/$dpkgArch/$suite"

		touch_epoch() {
			while [ "$#" -gt 0 ]; do
				local f="$1"; shift
				touch --no-dereference --date="@$epoch" "$f"
			done
		}

		debuerreotypeScriptsDir="$(dirname "$(readlink -f "$(which debuerreotype-init)")")"

		for archive in "" security; do
			if [ -z "$eol" ]; then
				snapshotUrl="$("$debuerreotypeScriptsDir/.snapshot-url.sh" "@$epoch" "${archive:+debian-${archive}}")"
			else
				snapshotUrl="$("$debuerreotypeScriptsDir/.snapshot-url.sh" "@$epoch" "debian-archive")/debian${archive:+-${archive}}"
			fi
			snapshotUrlFile="$exportDir/$serial/$dpkgArch/snapshot-url${archive:+-${archive}}"
			mkdir -p "$(dirname "$snapshotUrlFile")"
			echo "$snapshotUrl" > "$snapshotUrlFile"
			touch_epoch "$snapshotUrlFile"
		done

		if [ -z "$eol" ]; then
			keyring=/usr/share/keyrings/debian-archive-keyring.gpg
		else
			keyring=/usr/share/keyrings/debian-archive-removed-keys.gpg

			if [ "$suite" = potato ]; then
				# src:debian-archive-keyring was created in 2006, thus does not include a key for potato
				export GNUPGHOME="$(mktemp -d)"
				keyring="$GNUPGHOME/debian-archive-$suite-keyring.gpg"
				gpg --no-default-keyring --keyring "$keyring" --keyserver ha.pool.sks-keyservers.net --recv-keys 8FD47FF1AA9372C37043DC28AA7DEB7B722F1AED
			fi
		fi

		snapshotUrl="$(< "$exportDir/$serial/$dpkgArch/snapshot-url")"
		mkdir -p "$outputDir"
		wget -O "$outputDir/Release.gpg" "$snapshotUrl/dists/$suite/Release.gpg"
		wget -O "$outputDir/Release" "$snapshotUrl/dists/$suite/Release"
		gpgv \
			--keyring "$keyring" \
			"$outputDir/Release.gpg" \
			"$outputDir/Release"

		codename="$(awk -F ": " "\$1 == \"Codename\" { print \$2; exit }" "$outputDir/Release")"
		if [ -n "$codenameCopy" ] && [ "$codename" = "$suite" ]; then
			# if codename already is the same as suite, then making a copy does not make any sense
			codenameCopy=
		fi
		if [ -n "$codenameCopy" ] && [ -z "$codename" ]; then
			echo >&2 "error: --codename-copy specified but we failed to get a Codename for $suite"
			exit 1
		fi

		{
			initArgs=( --arch="$dpkgArch" )
			if [ -z "$eol" ]; then
				initArgs+=( --debian )
			else
				initArgs+=( --debian-eol )
			fi
			initArgs+=( --keyring "$keyring" )

			releaseSuite="$(awk -F ": " "\$1 == \"Suite\" { print \$2; exit }" "$outputDir/Release")"
			case "$releaseSuite" in
				# see https://bugs.debian.org/src:usrmerge for why merged-usr should not be in stable yet (mostly "dpkg" related bugs)
				*oldstable|stable)
					initArgs+=( --no-merged-usr )
					;;
			esac

			if [ -n "$qemu" ]; then
				initArgs+=( --debootstrap="qemu-debootstrap" )
			fi

			debuerreotype-init "${initArgs[@]}" rootfs "$suite" "@$epoch"

			debuerreotype-minimizing-config rootfs
			debuerreotype-apt-get rootfs update -qq
			debuerreotype-apt-get rootfs dist-upgrade -yqq

			aptVersion="$("$debuerreotypeScriptsDir/.apt-version.sh" rootfs)"
			case "$aptVersion" in
				# --debian-eol etch and lower do not support --no-install-recommends
				0.6.*|0.5.*) noInstallRecommends="-o APT::Install-Recommends=0" ;;

				*) noInstallRecommends="--no-install-recommends" ;;
			esac

			# make a couple copies of rootfs so we can create other variants
			for variant in slim sbuild; do
				mkdir "rootfs-$variant"
				tar -cC rootfs . | tar -xC "rootfs-$variant"
			done

			# prefer iproute2 if it exists
			case "$aptVersion" in
				0.5.*) iproute=iproute ;; # --debian-eol woody and below have bad apt-cache which only warns for missing packages
				*)
					iproute=iproute2
					if ! debuerreotype-chroot rootfs apt-cache show iproute2 > /dev/null; then
						# poor wheezy
						iproute=iproute
					fi
					;;
			esac
			ping=iputils-ping
			if debuerreotype-chroot rootfs bash -c "command -v ping > /dev/null"; then
				# if we already have "ping" (as in --debian-eol potato), skip installing any extra ping package
				ping=
			fi
			debuerreotype-apt-get rootfs install -y $noInstallRecommends $ping $iproute

			debuerreotype-slimify rootfs-slim

			# this should match the list added to the "buildd" variant in debootstrap and the list installed by sbuild
			# https://anonscm.debian.org/cgit/d-i/debootstrap.git/tree/scripts/sid?id=706a45681c5bba5e062a9b02e19f079cacf2a3e8#n26
			# https://anonscm.debian.org/cgit/buildd-tools/sbuild.git/tree/bin/sbuild-createchroot?id=eace3d3e59e48d26eaf069d9b63a6a4c868640e6#n194
			debuerreotype-apt-get rootfs-sbuild install -y $noInstallRecommends build-essential fakeroot

			create_artifacts() {
				local targetBase="$1"; shift
				local rootfs="$1"; shift
				local suite="$1"; shift
				local variant="$1"; shift

				# make a copy of the snapshot-facing sources.list file before we overwrite it
				cp "$rootfs/etc/apt/sources.list" "$targetBase.sources-list-snapshot"
				touch_epoch "$targetBase.sources-list-snapshot"

				local mirror secmirror
				if [ -z "$eol" ]; then
					mirror="http://deb.debian.org/debian"
					secmirror="http://security.debian.org/debian-security"
				else
					mirror="http://archive.debian.org/debian"
					secmirror="http://archive.debian.org/debian-security"
				fi

				local tarArgs=()
				if [ -n "$qemu" ]; then
					tarArgs+=( --exclude="./usr/bin/qemu-*-static" )
				fi

				if [ "$variant" != "sbuild" ]; then
					debuerreotype-gen-sources-list "$rootfs" "$suite" "$mirror" "$secmirror"
				else
					# sbuild needs "deb-src" entries
					debuerreotype-gen-sources-list --deb-src "$rootfs" "$suite" "$mirror" "$secmirror"

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

				debuerreotype-tar "${tarArgs[@]}" "$rootfs" "$targetBase.tar.xz"
				du -hsx "$targetBase.tar.xz"

				sha256sum "$targetBase.tar.xz" | cut -d" " -f1 > "$targetBase.tar.xz.sha256"
				touch_epoch "$targetBase.tar.xz.sha256"

				debuerreotype-chroot "$rootfs" bash -c "
					if ! dpkg-query -W; then
						# --debian-eol woody has no dpkg-query
						dpkg -l
					fi
				" > "$targetBase.manifest"
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

			for rootfs in rootfs*/; do
				rootfs="${rootfs%/}" # "rootfs", "rootfs-slim", ...

				du -hsx "$rootfs"

				variant="${rootfs#rootfs}" # "", "-slim", ...
				variant="${variant#-}" # "", "slim", ...

				variantDir="$outputDir/$variant"
				mkdir -p "$variantDir"

				targetBase="$variantDir/rootfs"

				create_artifacts "$targetBase" "$rootfs" "$suite" "$variant"
			done

			if [ -n "$codenameCopy" ]; then
				codenameDir="$exportDir/$serial/$dpkgArch/$codename"
				mkdir -p "$codenameDir"
				tar -cC "$outputDir" --exclude="**/rootfs.*" . | tar -xC "$codenameDir"

				for rootfs in rootfs*/; do
					rootfs="${rootfs%/}" # "rootfs", "rootfs-slim", ...

					variant="${rootfs#rootfs}" # "", "-slim", ...
					variant="${variant#-}" # "", "slim", ...

					variantDir="$codenameDir/$variant"
					targetBase="$variantDir/rootfs"

					# point sources.list back at snapshot.debian.org temporarily (but this time pointing at $codename instead of $suite)
					debuerreotype-gen-sources-list "$rootfs" "$codename" "$(< "$exportDir/$serial/$dpkgArch/snapshot-url")" "$(< "$exportDir/$serial/$dpkgArch/snapshot-url-security")"

					create_artifacts "$targetBase" "$rootfs" "$codename" "$variant"
				done
			fi
		} >&2

		tar -cC "$exportDir" .
	' | tar -xvC "$outputDir"
