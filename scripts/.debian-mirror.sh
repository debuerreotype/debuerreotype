#!/usr/bin/env bash
set -Eeuo pipefail

thisDir="$(dirname "$(readlink -vf "$BASH_SOURCE")")"
source "$thisDir/.constants.sh" \
	--flags 'eol,ports' \
	-- \
	'[--eol] [--ports] <timestamp> <suite> <arch> <component>' \
	'--eol 2021-03-01T00:00:00Z jessie amd64 main
2021-03-01T00:00:00Z buster-security arm64 main
--ports 2021-03-01T00:00:00Z sid riscv64 main'

eval "$dgetopt"
eol=
ports=
while true; do
	flag="$1"; shift
	dgetopt-case "$flag"
	case "$flag" in
		--eol) eol=1 ;;
		--ports) ports=1 ;;
		--) break ;;
		*) eusage "unknown flag '$flag'" ;;
	esac
done

timestamp="${1:-}"; shift || eusage 'missing timestamp'
suite="${1:-}"; shift || eusage 'missing suite'
arch="${1:-}"; shift || eusage 'missing arch'
component="${1:-}"; shift || eusage 'missing component'

if [[ "$suite" == *-security ]]; then
	target='security'
else
	target='standard'
fi

epoch="$(date --date "$timestamp" '+%s')"

if [ -z "$ports" ]; then
	standardMirrors=( 'http://deb.debian.org/debian' )
	snapshotStandardMirrors=( "$("$thisDir/.snapshot-url.sh" "@$epoch")" )
else
	standardMirrors=( 'http://deb.debian.org/debian-ports' )
	snapshotStandardMirrors=( "$("$thisDir/.snapshot-url.sh" "@$epoch" 'debian-ports')" )
fi

securityMirrors=( 'http://deb.debian.org/debian-security' )
snapshotSecurityMirrors=( "$("$thisDir/.snapshot-url.sh" "@$epoch" 'debian-security')" )

if [ -n "$eol" ]; then
	# https://bugs.debian.org/986207 - snapshot.debian.org is not currently actually supporting archive.debian.org (and archive.debian.org really is effectively a snapshot in itself), so for EOL releases we should prefer archive.debian.org directly (and fixup timestamps/debuerreotype-recalculate-epoch afterwards)
	archiveSnapshotMirror="$("$thisDir/.snapshot-url.sh" "@$epoch" 'debian-archive')"

	standardMirrors=( 'http://archive.debian.org/debian' "${standardMirrors[@]}" )
	snapshotStandardMirrors=( 'http://archive.debian.org/debian' "$archiveSnapshotMirror/debian" "${snapshotStandardMirrors[@]}" )

	securityMirrors=( 'http://archive.debian.org/debian-security' "${securityMirrors[@]}" )
	snapshotSecurityMirrors=( 'http://archive.debian.org/debian-security' "$archiveSnapshotMirror/debian-security" "${snapshotSecurityMirrors[@]}" )
fi

case "$target" in
	standard)
		nonSnapshotMirrors=( "${standardMirrors[@]}" )
		snapshotMirrors=( "${snapshotStandardMirrors[@]}" )
		;;
	security)
		nonSnapshotMirrors=( "${securityMirrors[@]}" )
		snapshotMirrors=( "${snapshotSecurityMirrors[@]}" )
		;;
	*) echo >&2 "error: unknown target: '$target'"; exit 1 ;;
esac

_find() {
	local findSuite="${1:-$suite}"
	local i
	for i in "${!snapshotMirrors[@]}"; do
		local mirror="${nonSnapshotMirrors[$i]}" snapshotMirror="${snapshotMirrors[$i]}"
		# http://snapshot.debian.org/archive/debian-archive/20160314T000000Z/debian/dists/squeeze-updates/main/binary-amd64/Packages.gz
		if \
			wget --quiet --spider -O /dev/null -o /dev/null "$snapshotMirror/dists/$findSuite/$component/binary-$arch/Packages.xz" \
			|| wget --quiet --spider -O /dev/null -o /dev/null "$snapshotMirror/dists/$findSuite/$component/binary-$arch/Packages.gz" \
		; then
			declare -g mirror="$mirror" snapshotMirror="$snapshotMirror" suite="$findSuite"
			return 0
		fi
	done
	if [ "$target" = 'security' ] && [[ "$findSuite" == *-security ]]; then
		if _find "${suite%-security}/updates"; then
			return 0
		fi
	fi
	return 1
}
if ! _find; then
	echo >&2 "warning: no apparent '$suite/$component' for '$arch' on any of the following"
	for mirror in "${snapshotMirrors[@]}"; do echo >&2 "  - $mirror"; done
	exit 1
fi
printf 'mirror=%q\nsnapshotMirror=%q\nfoundSuite=%q\n' "$mirror" "$snapshotMirror" "$suite"
