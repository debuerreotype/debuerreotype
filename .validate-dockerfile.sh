#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p validate/dockerfile

./docker-run.sh --pull bash -Eeuo pipefail -c '
	export SUITE="$1" TIMESTAMP="$2"
	dir="validate/dockerfile"
	user="$(stat --format "%u" "$dir")"
	group="$(stat --format "%g" "$dir")"

	debuerreotype-init --keyring /usr/share/keyrings/debian-archive-removed-keys.pgp --no-merged-usr /tmp/rootfs "$SUITE" "$TIMESTAMP"

	debuerreotype-tar /tmp/rootfs "$dir/$SUITE.tar.xz"

	chown "$user:$group" "$dir/$SUITE.tar.xz"
' -- "$SUITE" "$TIMESTAMP"

xz --threads=0 --decompress < "validate/dockerfile/$SUITE.tar.xz" | sha256sum | cut -d' ' -f1 > "validate/dockerfile/$SUITE.tar.sha256"
