#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
source "$thisDir/.constants.sh"
self="$(basename "$0")"

usage() {
	cat <<-EOU
		usage: $self <target-dir> <suite> <timestamp>
		   ie: $self rootfs stretch 2017-05-08T00:00:00Z
	EOU
}
eusage() {
	echo >&2 "error: $1"
	usage >&2
	exit 1
}

targetDir="${1:-}"; shift || eusage 'missing target-dir'
suite="${1:-}"; shift || eusage 'missing suite'
timestamp="${1:-}"; shift || eusage 'missing timestamp'
[ -n "$targetDir" ] # must be non-empty

if [ -e "$targetDir" ] && [ -z "$(find "$targetDir" -maxdepth 0 -empty)" ]; then
	echo >&2 "error: '$targetDir' already exists (and isn't empty)!"
	exit 1
fi

epoch="$(date --date "$timestamp" '+%s')"
export SOURCE_DATE_EPOCH="$epoch"

timestamp="$(date --date "@$epoch" '+%Y%m%dT%H%M%SZ')"
mirror="http://snapshot.debian.org/archive/debian/$timestamp"
secmirror="http://snapshot.debian.org/archive/debian-security/$timestamp"

debootstrap \
	--force-check-gpg \
	--merged-usr \
	--variant=minbase \
	"$suite" "$targetDir" "$mirror"
echo "$epoch" > "$targetDir/docker-deboot-epoch"

"$thisDir/gen-sources-list.sh" "$targetDir" "$suite" "$mirror" "$secmirror"

# since we're minbase, we know everything included is either essential, or a dependency of essential, so let's get clean "apt-mark showmanual" output
"$thisDir/chroot.sh" "$targetDir" apt-mark auto '.*' > /dev/null

echo 'docker-deboot' > "$targetDir/etc/hostname"
echo "$epoch" \
	| md5sum \
	| cut -f1 -d' ' \
	> "$targetDir/etc/machine-id"
{
	echo 'nameserver 8.8.8.8'
	echo 'nameserver 8.8.4.4'
} > "$targetDir/etc/resolv.conf"
chmod 0644 \
	"$targetDir/etc/hostname" \
	"$targetDir/etc/machine-id" \
	"$targetDir/etc/resolv.conf"
