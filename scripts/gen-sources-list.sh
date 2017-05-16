#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
source "$thisDir/.constants.sh"
self="$(basename "$0")"

usage() {
	cat <<-EOU
		usage: $self <target-dir> <suite> <mirror> <secmirror>
		   ie: $self test-jessie-1 jessie http://deb.debian.org/debian http://security.debian.org
	EOU
}
eusage() {
	echo >&2 "error: $1"
	usage >&2
	exit 1
}

targetDir="${1:-}"; shift || eusage 'missing target-dir'
suite="${1:-}"; shift || eusage 'missing suite'
mirror="${1:-}"; shift || eusage 'missing mirror'
secmirror="${1:-}"; shift || eusage 'missing secmirror'
[ -n "$targetDir" ]

comp='main'

# https://github.com/tianon/go-aptsources/blob/e066ed9cd8cd9eef7198765bd00ec99679e6d0be/target.go#L16-L58
{
	case "$suite" in
		sid|unstable|testing)
			echo "deb $mirror $suite $comp"
			;;

		experimental|rc-buggy)
			echo "deb $mirror sid $comp"
			echo "deb $mirror $suite $comp"
			;;

		*)
			echo "deb $mirror $suite $comp"
			echo "deb $mirror $suite-updates $comp"
			echo "deb $secmirror $suite/updates $comp"
			;;
	esac
} > "$targetDir/etc/apt/sources.list"
chmod 0644 "$targetDir/etc/apt/sources.list"
