#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

_defaults() {
	export ARCH= TIMESTAMP='2017-01-01T00:00:00Z' SHA256=
	unset DISTRO
}

combos=(
	'SUITE=stable    CODENAME=jessie  '
	'SUITE=jessie    CODENAME=""      '
	'SUITE=testing   CODENAME=stretch '
	'SUITE=stretch   CODENAME=""      '
	'SUITE=unstable  CODENAME=sid     '
	'SUITE=sid       CODENAME=""      '
	'SUITE=oldstable CODENAME=wheezy  '
	'SUITE=wheezy    CODENAME=""      '
	''
	'# unstable debootstrap testing'
	'SUITE=sid DISTRO=debian-unstable '
	'# TODO figure out what to do when this breaks / how to disambiguate it from the sid above cleanly'
	''
	'# EOL suites testing'
	# these are broken thanks to snapshot doing redirects now (and old APT not following those)
	#'SUITE=eol CODENAME=etch  '
	#'SUITE=eol CODENAME=lenny '
	#'SUITE=eol CODENAME=woody ARCH=i386 '
	# TODO fix this by updating squignix to detect old APT versions transparently somehow and handle the redirects in the reverse proxy
	'SUITE=eol CODENAME=jessie TIMESTAMP="2021-03-01T00:00:00Z" '
	''
	'# deb822 / usr-is-merged testing'
	# unstable keys at this timestamp are expired but it's not easy for debuerreotype to know that (TODO we should work harder to fix this)
	#'SUITE=unstable CODENAME="" TIMESTAMP="2022-09-30T00:00:00Z" '
	'SUITE=bookworm CODENAME="" TIMESTAMP="2022-09-30T00:00:00Z" '
	'SUITE=bullseye CODENAME="" TIMESTAMP="2022-09-30T00:00:00Z" '
	''
	'# qemu-debootstrap testing'
	'ARCH=arm64   SUITE=jessie   CODENAME="" '
	# at this timestamp, these are both ports, and ports keys expire too quickly to be realistic to actually support in CI
	#'ARCH=sh4     SUITE=unstable CODENAME="" TIMESTAMP="2022-02-01T00:00:00Z" '
	#'ARCH=riscv64 SUITE=unstable CODENAME="" TIMESTAMP="2022-02-01T00:00:00Z" '
	''
	'# a few entries for "today" to try and catch issues like https://github.com/debuerreotype/debuerreotype/issues/41 sooner'
	'SUITE=unstable  CODENAME="" TIMESTAMP="today 00:00:00" SHA256=""'
	'SUITE=stable    CODENAME="" TIMESTAMP="today 00:00:00" SHA256=""'
	'SUITE=oldstable CODENAME="" TIMESTAMP="today 00:00:00" SHA256=""'
	''
	'# smoke test Ubuntu 24.04 and 22.04'
	'DISTRO=ubuntu SUITE=noble'
	'DISTRO=ubuntu SUITE=jammy'
)

githubEnv=
for combo in "${combos[@]}"; do
	_defaults
	githubEnv+=$'\n'"$combo"
	case "$combo" in
		'' | '#'* | *' SHA256='* | 'DISTRO=ubuntu'*)
			# leave blank lines, comment lines, lines with SHA256=, and lines starting with VALIDATE= unchanged
			continue
			;;
	esac
	vars="$(
		grep -oE1 'ARCH=[^ ]+' <<<"$combo" || :
		grep -oE1 'SUITE=[^ ]+' <<<"$combo" || :
		grep -oE1 'CODENAME=[^ ]*' <<<"$combo" || :
		grep -oE1 'TIMESTAMP=[^ ]*' <<<"$combo" || :
		grep -oE1 'DISTRO=[^ ]*' <<<"$combo" || :
	)"
	eval "$vars"
	[ -n "$SUITE" ]
	serial="$(TZ=UTC date --date="$TIMESTAMP" '+%Y%m%d')"
	rootfs="validate/$serial/${ARCH:-amd64}/${CODENAME:-$SUITE}/rootfs.tar.xz"
	if [ ! -e "$rootfs" ]; then
		( set -x; eval "$combo ./.validate-${DISTRO:-debian}.sh" )
	fi
	sha256="$(< "$rootfs.sha256")"
	if ! grep -qF 'TIMESTAMP=' <<<"$combo"; then
		githubEnv+="TIMESTAMP=\"$TIMESTAMP\" "
	fi
	githubEnv+="SHA256=$sha256"
done

gawk '{
	# leave text comments and blank lines alone!
	if (!/^$|^#[[:space:]]+/) {
		$0 = gensub(/([[:space:]]+[A-Z])/, ",\\1", "g")
		$0 = gensub(/=/, ": ", "g")
		$0 = gensub(/^(#)?/, "\\1- { ", 1)
		$0 = gensub(/$/, " }", 1)
	}
	if (!/^$/) {
		$0 = gensub(/^/, "          ", 1)
	}
	print
}' <<<"$githubEnv"$'\n'
