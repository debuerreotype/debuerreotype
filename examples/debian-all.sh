#!/usr/bin/env bash
set -Eeuo pipefail

suites=(
	unstable
	testing
	stable
	oldstable
	oldoldstable

	# just in case (will no-op with "not supported on 'arch'" unless it exists)
	oldoldoldstable
)

debuerreotypeScriptsDir="$(which debuerreotype-init)"
debuerreotypeScriptsDir="$(readlink -f "$debuerreotypeScriptsDir")"
debuerreotypeScriptsDir="$(dirname "$debuerreotypeScriptsDir")"

source "$debuerreotypeScriptsDir/.constants.sh" \
	--flags 'arch:,qemu' \
	-- \
	'[--arch=<arch>] [--qemu] <output-dir> <timestamp>' \
	'output 2017-05-08T00:00:00Z'

eval "$dgetopt"
arch=
qemu=
while true; do
	flag="$1"; shift
	dgetopt-case "$flag"
	case "$flag" in
		--arch) arch="$1"; shift ;; # for adding "--arch" to debuerreotype-init
		--qemu) qemu=1 ;; # for using "qemu-debootstrap"
		--) break ;;
		*) eusage "unknown flag '$flag'" ;;
	esac
done

outputDir="${1:-}"; shift || eusage 'missing output-dir'
timestamp="${1:-}"; shift || eusage 'missing timestamp'

mirror="$("$debuerreotypeScriptsDir/.snapshot-url.sh" "$timestamp")"
secmirror="$("$debuerreotypeScriptsDir/.snapshot-url.sh" "$timestamp" 'debian-security')"

dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"
echo
echo "-- BUILDING TARBALLS FOR '$dpkgArch' FROM '$mirror/' --"
echo

thisDir="$(readlink -f "$BASH_SOURCE")"
thisDir="$(dirname "$thisDir")"

debianArgs=( --codename-copy )
if [ -n "$arch" ]; then
	debianArgs+=( --arch="$arch" )
fi
if [ -n "$qemu" ]; then
	debianArgs+=( --qemu )
fi

_check() {
	local host="$1"; shift # "$mirror", "$secmirror"
	local dist="$1"; shift # "$suite-security", "$suite/updates", "$suite"
	local comp="${1:-main}"

	if wget --quiet --spider "$host/dists/$dist/$comp/binary-$dpkgArch/Packages.xz"; then
		return 0
	fi

	if wget --quiet --spider "$host/dists/$dist/$comp/binary-$dpkgArch/Packages.gz"; then
		return 0
	fi

	return 1
}

for suite in "${suites[@]}"; do
	doSkip=
	case "$suite" in
		testing | unstable) ;;

		*)
			# https://lists.debian.org/debian-devel-announce/2019/07/msg00004.html
			if \
				! _check "$secmirror" "$suite-security" \
				&& ! _check "$secmirror" "$suite/updates" \
			; then
				doSkip=1
			fi
			;;
	esac
	if ! _check "$mirror" "$suite"; then
		doSkip=1
	fi
	if [ -n "$doSkip" ]; then
		echo >&2
		echo >&2 "warning: '$suite' not supported on '$dpkgArch' (at '$timestamp'); skipping"
		echo >&2
		continue
	fi
	"$thisDir/debian.sh" "${debianArgs[@]}" "$outputDir" "$suite" "$timestamp"
done
