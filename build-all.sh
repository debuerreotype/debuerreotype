#!/usr/bin/env bash
set -Eeuo pipefail

suites=(
	oldstable
	stable
	testing
	unstable

	wheezy
	jessie
	stretch
	sid
)

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
self="$(basename "$0")"

usage() {
	cat <<-EOU
		usage: $self <output-dir> <timestamp>
		   ie: $self output 2017-05-08T00:00:00Z
	EOU
}
eusage() {
	echo >&2 "error: $1"
	usage >&2
	exit 1
}

# a silly flag to skip "docker build" (for giggles/debugging)
build=1
if [ "${1:-}" = '--no-build' ]; then
	shift
	build=
fi

outputDir="${1:-}"; shift || eusage 'missing output-dir'
timestamp="${1:-}"; shift || eusage 'missing timestamp'

mkdir -p "$outputDir"
outputDir="$(readlink -f "$outputDir")"

dockerImage='tianon/debuerreotype'
[ -z "$build" ] || docker build -t "$dockerImage" "$thisDir"

mirror="$("$thisDir/scripts/.snapshot-url.sh" "$timestamp")"
secmirror="$("$thisDir/scripts/.snapshot-url.sh" "$timestamp" 'debian-security')"

dpkgArch="$(docker run --rm "$dockerImage" dpkg --print-architecture)"
echo
echo "-- BUILDING TARBALLS FOR '$dpkgArch' FROM '$mirror/' --"
echo

fetch_codename() {
	local suite="$1"; shift
	wget -qO- "$mirror/dists/$suite/Release" \
		| tac|tac \
		| awk -F ': ' 'tolower($1) == "codename" { print $2; exit }'
}
declare -A codenames=(
	[testing]="$(fetch_codename 'testing')"
	[unstable]="$(fetch_codename 'unstable')"
)

for suite in "${suites[@]}"; do
	testUrl="$secmirror/dists/$suite/updates/main/binary-$dpkgArch/Packages.gz"
	case "$suite" in
		testing|unstable|"${codenames[testing]}"|"${codenames[unstable]}")
			testUrl="$mirror/dists/$suite/main/binary-$dpkgArch/Packages.gz"
			;;
	esac
	if ! wget --quiet --spider "$testUrl"; then
		echo >&2
		echo >&2 "warning: '$suite' not supported on '$dpkgArch' (at '$timestamp'); skipping"
		echo >&2
		continue
	fi
	"$thisDir/build.sh" --no-build "$outputDir" "$suite" "$timestamp"
done
