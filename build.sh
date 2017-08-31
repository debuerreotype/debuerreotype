#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
self="$(basename "$0")"

usage() {
	cat <<-EOU
		usage: $self <output-dir> <suite> <timestamp>
		   ie: $self output stretch 2017-05-08T00:00:00Z
		       $self --codename-copy output stable 2017-05-08T00:00:00Z
	EOU
}
eusage() {
	if [ "$#" -gt 0 ]; then
		echo >&2 "error: $*"
	fi
	usage >&2
	exit 1
}

options="$(getopt -n "$self" -o '' --long 'no-build,codename-copy' -- "$@")" || eusage
eval "set -- $options"
build=1
codenameCopy=
while true; do
	flag="$1"; shift
	case "$flag" in
		--no-build) build= ;; # for skipping "docker build"
		--codename-copy) codenameCopy=1 ;; # for copying a "stable.tar.xz" to "stretch.tar.xz" with updated sources.list (saves a lot of extra building work)
		--) break ;;
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
	-e codenameCopy="$codenameCopy" \
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

		debuerreotypeScriptsDir="$(dirname "$(readlink -f "$(which debuerreotype-init)")")"

		for archive in "" security; do
			snapshotUrl="$("$debuerreotypeScriptsDir/.snapshot-url.sh" "@$epoch" "${archive:+debian-${archive}}")"
			snapshotUrlFile="$exportDir/$serial/$dpkgArch/snapshot-url${archive:+-${archive}}"
			mkdir -p "$(dirname "$snapshotUrlFile")"
			echo "$snapshotUrl" > "$snapshotUrlFile"
			touch_epoch "$snapshotUrlFile"
		done

		snapshotUrl="$(< "$exportDir/$serial/$dpkgArch/snapshot-url")"
		mkdir -p "$outputDir"
		wget -O "$outputDir/Release.gpg" "$snapshotUrl/dists/$suite/Release.gpg"
		wget -O "$outputDir/Release" "$snapshotUrl/dists/$suite/Release"
		gpgv \
			--keyring /usr/share/keyrings/debian-archive-keyring.gpg \
			--keyring /usr/share/keyrings/debian-archive-removed-keys.gpg \
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

			create_artifacts() {
				local targetBase="$1"; shift
				local rootfs="$1"; shift
				local suite="$1"; shift
				local variant="$1"; shift

				# make a copy of the snapshot-facing sources.list file before we overwrite it
				cp "$rootfs/etc/apt/sources.list" "$targetBase.sources-list-snapshot"
				touch_epoch "$targetBase.sources-list-snapshot"

				if [ "$variant" != "sbuild" ]; then
					debuerreotype-gen-sources-list "$rootfs" "$suite" http://deb.debian.org/debian http://security.debian.org
					debuerreotype-tar "$rootfs" "$targetBase.tar.xz"
				else
					# sbuild needs "deb-src" entries
					debuerreotype-gen-sources-list --deb-src "$rootfs" "$suite" http://deb.debian.org/debian http://security.debian.org

					# APT has odd issues with "Acquire::GzipIndexes=false" + "file://..." sources sometimes
					# (which are used in sbuild for "--extra-package")
					#   Could not open file /var/lib/apt/lists/partial/_tmp_tmp.ODWljpQfkE_._Packages - open (13: Permission denied)
					#   ...
					#   E: Failed to fetch store:/var/lib/apt/lists/partial/_tmp_tmp.ODWljpQfkE_._Packages  Could not open file /var/lib/apt/lists/partial/_tmp_tmp.ODWljpQfkE_._Packages - open (13: Permission denied)
					rm -f "$rootfs/etc/apt/apt.conf.d/docker-gzip-indexes"
					# TODO figure out the bug and fix it in APT instead /o\

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
