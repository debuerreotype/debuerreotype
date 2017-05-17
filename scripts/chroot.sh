#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
source "$thisDir/.constants.sh"
self="$(basename "$0")"

usage() {
	cat <<-EOU
		usage: $self <target-dir> <command> [args...]
		   ie: $self rootfs apt-get update
	EOU
}
eusage() {
	echo >&2 "error: $1"
	usage >&2
	exit 1
}

targetDir="${1:-}"; shift || eusage 'missing target-dir'
cmd="${1:-}"; shift || eusage 'missing command'
[ -n "$targetDir" ]
epoch="$(< "$targetDir/docker-deboot-epoch")"
[ -n "$epoch" ]

export targetDir epoch
unshare --mount bash -Eeuo pipefail -c '
	[ -n "$targetDir" ] # just to be safe
	for dir in dev proc sys; do
		mount --rbind "/$dir" "$targetDir/$dir"
	done
	exec chroot "$targetDir" /usr/bin/env -i PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" TZ="$TZ" LC_ALL="$LC_ALL" SOURCE_DATE_EPOCH="$epoch" "$@"
' -- "$cmd" "$@"
