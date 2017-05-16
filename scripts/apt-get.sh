#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
source "$thisDir/.constants.sh"
self="$(basename "$0")"

usage() {
	cat <<-EOU
		usage: $self <target-dir> arguments
		   ie: $self test-jessie-1 update
	EOU
}
eusage() {
	echo >&2 "error: $1"
	usage >&2
	exit 1
}

targetDir="${1:-}"; shift || eusage 'missing target-dir'
[ -n "$targetDir" ]

"$thisDir/chroot.sh" "$targetDir" apt-get -o Acquire::Check-Valid-Until=false "$@"
