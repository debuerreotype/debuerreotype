#!/usr/bin/env bash
set -Eeuo pipefail

suites=(
	unstable
	testing
	stable
	oldstable
	oldoldstable

	# just in case (will no-op with "not supported on 'arch'" unless it exists)
	oldoldoldstable
)

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
source "$thisDir/scripts/.constants.sh" \
	--flags 'no-build' \
	-- \
	'[--no-build] <output-dir> <timestamp>' \
	'output 2017-05-08T00:00:00Z'

eval "$dgetopt"
build=1
while true; do
	flag="$1"; shift
	dgetopt-case "$flag"
	case "$flag" in
		--no-build) build= ;; # for skipping "docker build"
		--) break ;;
		*) eusage "unknown flag '$flag'" ;;
	esac
done

outputDir="${1:-}"; shift || eusage 'missing output-dir'
timestamp="${1:-}"; shift || eusage 'missing timestamp'

mkdir -p "$outputDir"
outputDir="$(readlink -f "$outputDir")"

ver="$("$thisDir/scripts/debuerreotype-version")"
ver="${ver%% *}"
dockerImage="debuerreotype/debuerreotype:$ver"
[ -z "$build" ] || docker build -t "$dockerImage" "$thisDir"

mirror="$("$thisDir/scripts/.snapshot-url.sh" "$timestamp")"
secmirror="$("$thisDir/scripts/.snapshot-url.sh" "$timestamp" 'debian-security')"

dpkgArch="$(docker run --rm "$dockerImage" dpkg --print-architecture | awk -F- '{ print $NF }')"
echo
echo "-- BUILDING TARBALLS FOR '$dpkgArch' FROM '$mirror/' --"
echo

for suite in "${suites[@]}"; do
	doSkip=
	case "$suite" in
		testing|unstable) ;;
		*)
			# https://lists.debian.org/debian-devel-announce/2019/07/msg00004.html
			if \
				! wget --quiet --spider "$secmirror/dists/$suite-security/main/binary-$dpkgArch/Packages.xz" \
				&& ! wget --quiet --spider "$secmirror/dists/$suite-security/main/binary-$dpkgArch/Packages.gz" \
				&& ! wget --quiet --spider "$secmirror/dists/$suite/updates/main/binary-$dpkgArch/Packages.xz" \
				&& ! wget --quiet --spider "$secmirror/dists/$suite/updates/main/binary-$dpkgArch/Packages.gz" \
			; then
				doSkip=1
			fi
			;;
	esac
	if \
		! wget --quiet --spider "$mirror/dists/$suite/main/binary-$dpkgArch/Packages.xz" \
		&& ! wget --quiet --spider "$mirror/dists/$suite/main/binary-$dpkgArch/Packages.gz" \
	; then
		doSkip=1
	fi
	if [ -n "$doSkip" ]; then
		echo >&2
		echo >&2 "warning: '$suite' not supported on '$dpkgArch' (at '$timestamp'); skipping"
		echo >&2
		continue
	fi
	"$thisDir/build.sh" --no-build --codename-copy "$outputDir" "$suite" "$timestamp"
done
