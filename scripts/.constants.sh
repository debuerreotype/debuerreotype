#!/usr/bin/env bash

# constants of the universe
export TZ='UTC' LC_ALL='C'
umask 0002

usageStr="$1"
usageEx="$2"
self="$(basename "$0")"
usage() {
	cat <<-EOU
		usage: $self $usageStr
		   ie: $self $usageEx
	EOU
}
eusage() {
	echo >&2 "error: $1"
	usage >&2
	exit 1
}
