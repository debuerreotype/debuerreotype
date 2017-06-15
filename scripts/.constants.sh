#!/usr/bin/env bash

# constants of the universe
export TZ='UTC' LC_ALL='C'
umask 0002
scriptsDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"

_version() {
	local v
	if [ -r "$scriptsDir/../VERSION" ]; then
		v="$(< "$scriptsDir/../VERSION")"
	else
		v='unknown'
	fi
	if [ -d "$scriptsDir/../.git" ] && command -v git > /dev/null; then
		local commit="$(git -C "$scriptsDir" rev-parse --short 'HEAD^{commit}')"
		v="$v commit $commit"
	fi
	echo "$v"
}

usageStr="$1"
usageEx="$2"
self="$(basename "$0")"
usage() {
	local v="$(_version)"
	cat <<-EOU
		usage: $self $usageStr
		   ie: $self $usageEx

		debuerreotype version $v
	EOU
}
eusage() {
	if [ "$#" -gt 0 ]; then
		echo >&2 "error: $*"
	fi
	usage >&2
	exit 1
}
