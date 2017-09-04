#!/usr/bin/env bash

# constants of the universe
export TZ='UTC' LC_ALL='C'
umask 0002
scriptsDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
self="$(basename "$0")"

options="$(getopt -n "$BASH_SOURCE" -o '+' --long 'flags:,flags-short:' -- "$@")"
dFlags='help,version'
dFlagsShort='h?'
usageStr=
__cgetopt() {
	eval "set -- $options" # in a function since otherwise "set" will overwrite the parent script's positional args too
	unset options

	while true; do
		local flag="$1"; shift
		case "$flag" in
			--flags) dFlags="${dFlags:+$dFlags,}$1"; shift ;;
			--flags-short) dFlagsShort="${dFlagsShort}$1"; shift ;;
			--) break ;;
			*) echo >&2 "error: unexpected $BASH_SOURCE flag '$flag'"; exit 1 ;;
		esac
	done

	while [ "$#" -gt 0 ]; do
		local IFS=$'\n'
		local usagePrefix='usage:' usageLine=
		for usageLine in $1; do
			usageStr+="$usagePrefix $self${usageLine:+ $usageLine}"$'\n'
			usagePrefix='      '
		done
		usagePrefix='   ie:'
		for usageLine in $2; do
			usageStr+="$usagePrefix $self${usageLine:+ $usageLine}"$'\n'
			usagePrefix='      '
		done
		usageStr+=$'\n'
		shift 2
	done
}
__cgetopt

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

usage() {
	echo -n "$usageStr"

	local v="$(_version)"
	echo "debuerreotype version $v"
}
eusage() {
	if [ "$#" -gt 0 ]; then
		echo >&2 "error: $*"$'\n'
	fi
	usage >&2
	exit 1
}
_dgetopt() {
	getopt -n "$self" \
		-o "+$dFlagsShort" \
		--long "$dFlags" \
		-- "$@" \
		|| eusage 'getopt failed'
}
dgetopt='options="$(_dgetopt "$@")"; eval "set -- $options"; unset options'
dgetopt-case() {
	local flag="$1"; shift

	case "$flag" in
		-h|'-?'|--help) usage; exit 0 ;;
		--version) _version; exit 0 ;;
	esac
}
