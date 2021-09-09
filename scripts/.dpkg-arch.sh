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

if [ -s "$targetDir/etc/debian_version" ] && debVer="$(< "$targetDir/etc/debian_version")" && [ "$debVer" = '2.1' ]; then
	# must be slink, where invoking "dpkg --print-architecture" leads to:
	#   dpkg (subprocess): failed to exec C compiler `gcc': No such file or directory
	#   dpkg: subprocess gcc --print-libgcc-file-name returned error exit status 2
	echo 'i386'
	# (we don't support any of "alpha", "m68k", or "sparc"; see http://archive.debian.org/debian/dists/slink/ -- if we ever do, "apt-get --version" is a good candidate for scraping: "apt 0.3.11 for i386 compiled on Aug  8 1999  10:12:36")
	exit
fi

arch="$("$thisDir/debuerreotype-chroot" "$targetDir" dpkg --print-architecture)"

# --debian-eol woody likes to give us "i386-none"
arch="${arch%-none}"

echo "$arch" | awk -F- '{ print $NF }'
