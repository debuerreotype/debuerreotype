#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
source "$thisDir/.constants.sh"
self="$(basename "$0")"

usage() {
	cat <<-EOU
		usage: $self <suite> <timestamp> <target-dir>
		   ie: $self jessie 2017-05-08T00:00:00Z test-jessie-1
	EOU
}
eusage() {
	echo >&2 "error: $1"
	usage >&2
	exit 1
}

timestamp_to() {
	date --date "$1" '+%s'
}

suite="${1:-}"; shift || eusage 'missing suite'
timestamp="${1:-}"; shift || eusage 'missing timestamp'
targetDir="${1:-}"; shift || eusage 'missing target-dir'
[ -n "$targetDir" ] # must be non-empty

if [ -e "$targetDir" ] && [ -z "$(find "$targetDir" -maxdepth 0 -empty)" ]; then
	echo >&2 "error: '$targetDir' already exists (and isn't empty)!"
	exit 1
fi

epoch="$(date --date "$timestamp" '+%s')"
timestamp="$(date --date "@$epoch" '+%Y%m%dT%H%M%SZ')"
mirror="http://snapshot.debian.org/archive/debian/$timestamp"

debootstrap \
	--force-check-gpg \
	--merged-usr \
	--variant=minbase \
	"$suite" "$targetDir" "$mirror"

echo "$epoch" > "$targetDir/docker-deboot-epoch"

"$thisDir/fixup.sh" "$targetDir"
