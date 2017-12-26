#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
source "$thisDir/.constants.sh" \
	'<target-dir>' \
	'rootfs'

eval "$dgetopt"
while true; do
	flag="$1"; shift
	dgetopt-case "$flag"
	case "$flag" in
		--) break ;;
		*) eusage "unknown flag '$flag'" ;;
	esac
done

targetDir="${1:-}"; shift || eusage 'missing target-dir'
[ -n "$targetDir" ]

arch="$("$thisDir/debuerreotype-chroot" "$targetDir" dpkg --print-architecture)"

# --debian-eol woody likes to give us "i386-none"
arch="${arch%-none}"

echo "$arch" | awk -F- '{ print $NF }'
