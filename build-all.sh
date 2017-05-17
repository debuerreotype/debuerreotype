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

dockerImage='tianon/docker-deboot'
[ -z "$build" ] || docker build -t "$dockerImage" -f "$thisDir/Dockerfile.builder" "$thisDir"

dpkgArch="$(docker run --rm "$dockerImage" dpkg --print-architecture)"
echo
echo "-- BUILDING TARBALLS FOR '$dpkgArch' --"
echo

for suite in "${suites[@]}"; do
	if ! wget --quiet --spider "http://deb.debian.org/debian/dists/$suite/main/binary-$dpkgArch/Release"; then
		echo >&2
		echo >&2 "warning: '$suite' not supported on '$dpkgArch'; skipping"
		echo >&2
		continue
	fi
	"$thisDir/build.sh" --no-build "$outputDir" "$suite" "$timestamp"
done
