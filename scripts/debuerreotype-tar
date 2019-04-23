#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
source "$thisDir/.constants.sh" \
	--flags 'exclude:' \
	--flags 'include-dev' \
	-- \
	'[--include-dev] <target-dir> <target-tar>' \
	'rootfs rootfs.tar'

eval "$dgetopt"
excludes=()
includeDev=
while true; do
	flag="$1"; shift
	dgetopt-case "$flag"
	case "$flag" in
		--exclude) excludes+=( "$1" ); shift ;;
		--include-dev) includeDev=1 ;;
		--) break ;;
		*) eusage "unknown flag '$flag'" ;;
	esac
done

targetDir="${1:-}"; shift || eusage 'missing target-dir'
[ -n "$targetDir" ]
targetTar="${1:-}"; shift || eusage 'missing target-tar'
[ -n "$targetTar" ]

epoch="$(< "$targetDir/debuerreotype-epoch")"
[ -n "$epoch" ]

aptVersion="$("$thisDir/.apt-version.sh" "$targetDir")"
if dpkg --compare-versions "$aptVersion" '>=' '0.8~'; then
	# if APT is new enough to auto-recreate "partial" directories, let it
	# (https://salsa.debian.org/apt-team/apt/commit/1cd1c398d18b78f4aa9d882a5de5385f4538e0be)
	excludes+=(
		'./var/cache/apt/**'
		'./var/lib/apt/lists/**'
		'./var/state/apt/lists/**'
	)
	# (see also the targeted exclusions in ".tar-exclude" that these are overriding)
fi

"$thisDir/debuerreotype-fixup" "$targetDir"

tarArgs=(
	--create
	--file "$targetTar"
	--auto-compress
	--directory "$targetDir"
	--exclude-from "$thisDir/.tar-exclude"
)
if [ -z "$includeDev" ]; then
	excludes+=( './dev/**' )
fi
for exclude in "${excludes[@]}"; do
	tarArgs+=( --exclude "$exclude" )
done
tarArgs+=(
	--numeric-owner
	--transform 's,^./,,'
	--sort name
	.
)

tar "${tarArgs[@]}"

touch --no-dereference --date="@$epoch" "$targetTar"
