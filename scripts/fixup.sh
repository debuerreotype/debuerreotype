#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
source "$thisDir/.constants.sh"
self="$(basename "$0")"

usage() {
	cat <<-EOU
		usage: $self <target-dir>
		   ie: $self test-jessie-1
	EOU
}
eusage() {
	echo >&2 "error: $1"
	usage >&2
	exit 1
}

targetDir="${1:-}"; shift || eusage 'missing target-dir'
[ -n "$targetDir" ]
epoch="$(< "$targetDir/docker-deboot-epoch")"
[ -n "$epoch" ]

# https://github.com/lamby/debootstrap/commit/66b15380814aa62ca4b5807270ac57a3c8a0558d#diff-de4eef4ab836e5c6c9c1f820a2f624baR709
rm -f \
	"$targetDir/var/log/dpkg.log" \
	"$targetDir/var/log/bootstrap.log" \
	"$targetDir/var/log/alternatives.log" \
	"$targetDir/var/cache/ldconfig/aux-cache"

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

find "$targetDir" \
	-newermt "@$epoch" \
	-exec touch --no-dereference --date="@$epoch" '{}' +
