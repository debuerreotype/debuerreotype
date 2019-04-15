#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
source "$thisDir/.constants.sh" \
	'<apt-version> <file> [file ...]' \
	'0.7.22 rootfs/etc/apt/apt.conf.d/example'

eval "$dgetopt"
while true; do
	flag="$1"; shift
	dgetopt-case "$flag"
	case "$flag" in
		--) break ;;
		*) eusage "unknown flag '$flag'" ;;
	esac
done

aptVersion="${1:-}"; shift || eusage 'missing apt-version'
[ "$#" -gt 0 ] || eusage 'missing file(s)'

# support for "apt.conf" comments of the style "# xxx" was added in 0.7.22
# (https://salsa.debian.org/apt-team/apt/commit/81e9789b12374073e848c73c79e235f82c14df44)
if dpkg --compare-versions "$aptVersion" '>=' '0.7.22~'; then
	exit
fi

sed -ri -e 's!^#!//!' "$@"
