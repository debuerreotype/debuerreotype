#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
source "$thisDir/.constants.sh"
self="$(basename "$0")"

usage() {
	cat <<-EOU
		usage: $self <target-dir> <command> [args...]
		   ie: $self test-jessie-1 apt-get update
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

export targetDir
unshare --mount bash -Eeuo pipefail -c '
	[ -n "$targetDir" ] # just to be safe
	for dir in dev proc sys; do
		mount --rbind "/$dir" "$targetDir/$dir"
	done
	exec chroot "$targetDir" "$@"
' -- "$cmd" "$@"
