#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p validate/readme

./docker-run.sh --pull bash -Eeuo pipefail -c '
	export SUITE="$1" TIMESTAMP="$2"
	dir="validate/readme"
	user="$(stat --format "%u" "$dir")"
	group="$(stat --format "%g" "$dir")"

	debuerreotype-init --keyring /usr/share/keyrings/debian-archive-removed-keys.pgp --no-merged-usr /tmp/rootfs "$SUITE" "$TIMESTAMP"

	debuerreotype-minimizing-config /tmp/rootfs

	debuerreotype-apt-get /tmp/rootfs update -qq

	debuerreotype-apt-get /tmp/rootfs dist-upgrade -yqq

	debuerreotype-apt-get /tmp/rootfs install -yqq --no-install-recommends inetutils-ping iproute2

	debuerreotype-debian-sources-list /tmp/rootfs "$SUITE"

	debuerreotype-tar /tmp/rootfs "$dir/$SUITE.tar.xz"

	chown "$user:$group" "$dir/$SUITE.tar.xz"
' -- "$SUITE" "$TIMESTAMP"

xz --threads=0 --decompress < "validate/readme/$SUITE.tar.xz" | sha256sum | cut -d' ' -f1 > "validate/readme/$SUITE.tar.sha256"
