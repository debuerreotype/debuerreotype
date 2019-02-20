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

# scrape our APT version so we can do some basic feature detection (especially to remove unsupported settings on --debian-eol)
"$thisDir/debuerreotype-chroot" "$targetDir" bash -c '
	if command -v dpkg-query &> /dev/null; then
		dpkg-query --show --showformat "\${Version}\n" apt
	else
		# if dpkg-query does not exist, we must be on woody or potato, so just assume something ancient like 0.5.4 (since that is what woody includes and is old enough to cover all our features being excluded)
		echo 0.5.4
	fi
'
