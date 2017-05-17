#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
source "$thisDir/.constants.sh"
self="$(basename "$0")"

usage() {
	cat <<-EOU
		usage: $self <target-dir>
		   ie: $self rootfs
	EOU
}
eusage() {
	echo >&2 "error: $1"
	usage >&2
	exit 1
}

targetDir="${1:-}"; shift || eusage 'missing target-dir'
[ -n "$targetDir" ]

IFS=$'\n'; set -o noglob
slimExcludes=( $(grep -vE '^#|^$' "$thisDir/.slimify-excludes" | sort -u) )
set +o noglob; unset IFS

dpkgCfgFile="$targetDir/etc/dpkg/dpkg.cfg.d/docker"
mkdir -p "$(dirname "$dpkgCfgFile")"
{
	echo '# This is the "slim" variant of the Debian base image.'
	echo '# Many files which are normally unnecessary in containers are excluded,'
	echo '# and this configuration file keeps them that way.'
} > "$dpkgCfgFile"

neverExclude='/usr/share/doc/*/copyright'
for slimExclude in "${slimExcludes[@]}"; do
	{
		echo
		echo "# dpkg -S '$slimExclude'"
		if dpkgOutput="$("$thisDir/chroot.sh" "$targetDir" dpkg -S "$slimExclude" 2>&1)"; then
			echo "$dpkgOutput" | sed 's/: .*//g; s/, /\n/g' | sort -u | xargs
		else
			echo "$dpkgOutput"
		fi | fold -w 76 -s | sed 's/^/#  /'
		echo "path-exclude $slimExclude"
	} >> "$dpkgCfgFile"

	if [[ "$slimExclude" == *'/*' ]]; then
		if [ -d "$targetDir/$(dirname "$slimExclude")" ]; then
			# use two passes so that we don't fail trying to remove directories from $neverExclude
			"$thisDir/chroot.sh" "$targetDir" \
				find "$(dirname "$slimExclude")" \
					-mindepth 1 \
					-not -path "$neverExclude" \
					-not -type d \
					-delete
			"$thisDir/chroot.sh" "$targetDir" \
				find "$(dirname "$slimExclude")" \
					-mindepth 1 \
					-empty \
					-delete
		fi
	else
		"$thisDir/chroot.sh" "$targetDir" rm -f "$slimExclude"
	fi
done
{
	echo
	echo '# always include these files, especially for license compliance'
	echo "path-include $neverExclude"
} >> "$dpkgCfgFile"
chmod 0644 "$dpkgCfgFile"
