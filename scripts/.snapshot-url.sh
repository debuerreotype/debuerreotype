#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
source "$thisDir/.constants.sh" \
	'<timestamp> [archive]' \
	'2017-05-08T00:00:00Z debian-security'

eval "$dgetopt"
while true; do
	flag="$1"; shift
	dgetopt-case "$flag"
	case "$flag" in
		--) break ;;
		*) eusage "unknown flag '$flag'" ;;
	esac
done

timestamp="${1:-}"; shift || eusage 'missing timestamp'
archive="${1:-debian}"

t="$(date --date "$timestamp" '+%Y%m%dT%H%M%SZ')"
echo "http://snapshot.debian.org/archive/$archive/$t"
