#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
source "$thisDir/.constants.sh"
self="$(basename "$0")"

usage() {
	cat <<-EOU
		usage: $self <target-dir>
		   ie: $self rootfs
	EOU
}
eusage() {
	echo >&2 "error: $1"
	usage >&2
	exit 1
}

targetDir="${1:-}"; shift || eusage 'missing target-dir'
[ -n "$targetDir" ]
epoch="$(< "$targetDir/docker-deboot-epoch")"
[ -n "$epoch" ]

# https://github.com/lamby/debootstrap/commit/66b15380814aa62ca4b5807270ac57a3c8a0558d#diff-de4eef4ab836e5c6c9c1f820a2f624baR709
rm -f \
	"$targetDir/var/log/dpkg.log" \
	"$targetDir/var/log/bootstrap.log" \
	"$targetDir/var/log/alternatives.log" \
	"$targetDir/var/cache/ldconfig/aux-cache"

find "$targetDir" \
	-newermt "@$epoch" \
	-exec touch --no-dereference --date="@$epoch" '{}' +
