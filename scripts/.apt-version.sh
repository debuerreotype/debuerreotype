#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(dirname "$(readlink -vf "$BASH_SOURCE")")"
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

package="${1:-apt}"

# if dpkg-query does not exist, we must be on woody or older, so just assume something ancient (suggested version is the one in woody, since it should be old enough for any "fancy" features we're using this to exclude)
fallback=
case "$package" in
	apt) fallback='0.5.4' ;; # woody
	dpkg) fallback='1.9.21' ;; # woody
esac

# scrape package versions so we can do some basic feature detection (especially to remove unsupported settings on --debian-eol)
"$thisDir/debuerreotype-chroot" "$targetDir" bash -c '
	package="$1"; shift
	fallback="$1"; shift
	if command -v dpkg-query &> /dev/null; then
		dpkg-query --show --showformat "\${Version}\n" "$package"
	elif [ -n "$fallback" ]; then
		# if dpkg-query does not exist, we must be on woody or older
		echo "$fallback"
	else
		echo >&2 "error: missing dpkg-query and no fallback defined in debuerreotype for $package"
		exit 1
	fi
' -- "$package" "$fallback"
