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

source "$DEBUERREOTYPE_DIRECTORY/scripts/.constants.sh" \
	--flags 'arch:' \
	--flags 'dry-run' \
	-- \
	'[--arch=<arch>] [--dry-run] <output-dir> <timestamp>' \
	'output 2017-05-08T00:00:00Z'

eval "$dgetopt"
arch=
dryRun=
while true; do
	flag="$1"; shift
	dgetopt-case "$flag"
	case "$flag" in
		--arch) arch="$1"; shift ;;
		--dry-run) dryRun=1 ;;
		--) break ;;
		*) eusage "unknown flag '$flag'" ;;
	esac
done

outputDir="${1:-}"; shift || eusage 'missing output-dir'
timestamp="${1:-}"; shift || eusage 'missing timestamp'

debianArgs=( --codename-copy )

mirror="$("$DEBUERREOTYPE_DIRECTORY/scripts/.snapshot-url.sh" "$timestamp")"
secmirror="$("$DEBUERREOTYPE_DIRECTORY/scripts/.snapshot-url.sh" "$timestamp" 'debian-security')"

dpkgArch="${arch:-$(dpkg --print-architecture | awk -F- '{ print $NF }')}"
echo
echo "-- BUILDING TARBALLS FOR '$dpkgArch' FROM '$mirror/' --"
echo
debianArgs+=( --arch="$dpkgArch" )

_eol-date() {
	local codename="$1"; shift # "bullseye", "buster", etc.
	if [ ! -s /usr/share/distro-info/debian.csv ]; then
		echo >&2 "warning: looks like we are missing 'distro-info-data' (/usr/share/distro-info/debian.csv); cannot calculate EOL dates accurately!"
		exit 1
	fi
	awk -F, -v codename="$codename" '
		NR == 1 {
			headers = NF
			for (i = 1; i <= headers; i++) {
				header[i] = $i
			}
			next
		}
		{
			delete row
			for (i = 1; i <= NF && i <= headers; i++) {
				row[header[i]] = $i
			}
		}
		row["series"] == codename {
			if (row["eol-lts"] != "") {
				eol = row["eol-lts"]
				exit 0
			}
			if (row["eol"] != "") {
				eol = row["eol"]
				exit 0
			}
			exit 1
		}
		END {
			if (eol != "") {
				print eol
				exit 0
			}
			exit 1
		}
	' /usr/share/distro-info/debian.csv
}

_codename() {
	local dist="$1"; shift

	local release
	if release="$(wget --quiet --output-document=- "$mirror/dists/$dist/InRelease")"; then
		:
	elif release="$(wget --quiet --output-document=- "$mirror/dists/$dist/Release")"; then
		:
	else
		return 1
	fi

	local codename
	codename="$(awk '$1 == "Codename:" { print $2 }' <<<"$release")"
	[ -n "$codename" ] || return 1
	echo "$codename"
}

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
			if [ -z "$doSkip" ] && codename="$(_codename "$suite")" && eol="$(_eol-date "$codename")"; then
				epoch="$(date --date "$timestamp" '+%s')"
				eolEpoch="$(date --date "$eol" '+%s')"
				if [ "$epoch" -ge "$eolEpoch" ]; then
					echo >&2
					echo >&2 "warning: '$suite' ('$codename') is EOL at '$timestamp' ('$eol'); skipping"
					echo >&2
					continue
				fi
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
	cmd=( "$DEBUERREOTYPE_DIRECTORY/examples/debian.sh" "${debianArgs[@]}" "$outputDir" "$suite" "$timestamp" )
	if [ -n "$dryRun" ]; then
		printf 'DRY-RUN: $'
		printf ' %q' "${cmd[@]}"
		printf '\n'
	else
		"${cmd[@]}"
	fi
done
