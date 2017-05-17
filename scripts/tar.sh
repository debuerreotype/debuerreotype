#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
source "$thisDir/.constants.sh"
self="$(basename "$0")"

usage() {
	cat <<-EOU
		usage: $self <target-dir> <target-tar>
		   ie: $self rootfs rootfs.tar
	EOU
}
eusage() {
	echo >&2 "error: $1"
	usage >&2
	exit 1
}

targetDir="${1:-}"; shift || eusage 'missing target-dir'
[ -n "$targetDir" ]
targetTar="${1:-}"; shift || eusage 'missing target-tar'
[ -n "$targetTar" ]

epoch="$(< "$targetDir/docker-deboot-epoch")"
[ -n "$epoch" ]

"$thisDir/fixup.sh" "$targetDir"
tar --create \
	--file "$targetTar" \
	--auto-compress \
	--directory "$targetDir" \
	--exclude-from "$thisDir/.tar-exclude" \
	--numeric-owner \
	--transform 's,^./,,' \
	--sort name \
	.
touch --no-dereference --date="@$epoch" "$targetTar"
