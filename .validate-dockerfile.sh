#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p validate/dockerfile

./docker-run.sh --pull bash -Eeuo pipefail -c '
	export SUITE="$1" TIMESTAMP="$2"
	dir="validate/dockerfile"
	user="$(stat --format "%u" "$dir")"
	group="$(stat --format "%g" "$dir")"

	if [ "$SUITE" = jessie ]; then
		# https://bugs.debian.org/764204 "apt-cache calls fcntl() on 65536 FDs"
		# https://bugs.launchpad.net/bugs/1332440 "apt-get update very slow when ulimit -n is big"
		ulimit -n 1024
		# (see also "examples/debian.sh")
	fi

	debuerreotype-init --keyring /usr/share/keyrings/debian-archive-removed-keys.pgp --no-merged-usr /tmp/rootfs "$SUITE" "$TIMESTAMP"

	debuerreotype-tar /tmp/rootfs "$dir/$SUITE.tar.xz"

	chown "$user:$group" "$dir/$SUITE.tar.xz"
' -- "$SUITE" "$TIMESTAMP"

xz --threads=0 --decompress < "validate/dockerfile/$SUITE.tar.xz" | sha256sum | cut -d' ' -f1 > "validate/dockerfile/$SUITE.tar.sha256"
