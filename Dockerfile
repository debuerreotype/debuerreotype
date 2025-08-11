# docker run --cap-add SYS_ADMIN --cap-drop SETFCAP --tmpfs /tmp:dev,exec,suid,noatime ...

# bootstrapping a new architecture?
#   ./scripts/debuerreotype-init /tmp/docker-rootfs trixie now
#   ./scripts/debuerreotype-minimizing-config /tmp/docker-rootfs
#   ./scripts/debuerreotype-debian-sources-list /tmp/docker-rootfs trixie
#   ./scripts/debuerreotype-tar /tmp/docker-rootfs - | docker import - debian:trixie-slim
# alternate:
#   debootstrap --variant=minbase trixie /tmp/docker-rootfs
#   tar -cC /tmp/docker-rootfs . | docker import - debian:trixie-slim
# (or your own favorite set of "debootstrap" commands to create a base image for building this one FROM)
FROM debian:trixie-slim

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		debian-ports-archive-keyring \
		debootstrap \
		wget ca-certificates \
		xz-utils \
		\
		gnupg dirmngr \
# add "gpgv" explicitly (for now) since it's transitively-essential in bookworm and gone in trixie+
		gpgv \
	; \
	rm -rf /var/lib/apt/lists/*

# fight the tyrrany of HSTS (which destroys our ability to transparently cache snapshot.debian.org responses)
ENV WGETRC /.wgetrc
RUN echo 'hsts=0' >> "$WGETRC"

# https://github.com/debuerreotype/debuerreotype/issues/100
# https://tracker.debian.org/pkg/distro-info-data
# http://snapshot.debian.org/package/distro-info-data/
# http://snapshot.debian.org/package/distro-info-data/0.66/
RUN set -eux; \
	wget -O distro-info-data.deb 'http://snapshot.debian.org/archive/debian/20250721T022532Z/pool/main/d/distro-info-data/distro-info-data_0.66_all.deb'; \
	echo '2d083730bd927b1ccb452d93d5d01f31e69d8682 *distro-info-data.deb' | sha1sum --strict --check -; \
	apt-get install -y ./distro-info-data.deb; \
	rm distro-info-data.deb; \
	[ -s /usr/share/distro-info/debian.csv ]

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends patch; \
	rm -rf /var/lib/apt/lists/*; \
	\
# https://bugs.debian.org/973852
# https://salsa.debian.org/installer-team/debootstrap/-/merge_requests/63
# https://people.debian.org/~tianon/debootstrap-mr-63--download_main.patch
	wget -O debootstrap-download-main.patch 'https://people.debian.org/~tianon/debootstrap-mr-63--download_main.patch'; \
	echo 'ceae8f508a9b49236fa4519a44a584e6c774aa0e4446eb1551f3b69874a4cde5 *debootstrap-download-main.patch' | sha256sum --strict --check -; \
	patch --input=debootstrap-download-main.patch /usr/share/debootstrap/functions; \
	rm debootstrap-download-main.patch; \
	\
# https://salsa.debian.org/installer-team/debootstrap/-/merge_requests/70
	if grep 'mkdir.*/proc' /usr/share/debootstrap/functions; then \
		wget -O debootstrap-no-proc-symlink.patch 'https://people.debian.org/~tianon/debootstrap-mr-70--no-proc-symlink.patch'; \
		echo 'd8e19c05ca4a7471f00a50801c3cffd87cc810f9ad1173c82fc0d24596bf63bf *debootstrap-no-proc-symlink.patch' | sha256sum --strict --check -; \
		patch -p1 --input="$PWD/debootstrap-no-proc-symlink.patch" --directory=/usr/share/debootstrap; \
		rm debootstrap-no-proc-symlink.patch; \
	fi

# this env is a defined interface used by other scripts
ENV DEBUERREOTYPE_DIRECTORY /opt/debuerreotype

# see ".dockerignore"
COPY . $DEBUERREOTYPE_DIRECTORY
RUN set -eux; \
	cd "$DEBUERREOTYPE_DIRECTORY/scripts"; \
	for f in debuerreotype-*; do \
		ln -svL "$PWD/$f" "/usr/local/bin/$f"; \
	done; \
	version="$(debuerreotype-version)"; \
	[ "$version" != 'unknown' ]; \
	echo "debuerreotype version $version"

WORKDIR /tmp

# a few example md5sum values for amd64:

# TODO update these examples, because they don't actually work anymore 😭

# debuerreotype-init --keyring /usr/share/keyrings/debian-archive-removed-keys.gpg test-stretch stretch 2017-05-08T00:00:00Z
# debuerreotype-tar test-stretch test-stretch.tar
# md5sum test-stretch.tar
#   694f02c53651673ebe094cae3bcbb06d
# ./docker-run.sh sh -euxc 'debuerreotype-init --keyring /usr/share/keyrings/debian-archive-removed-keys.gpg /tmp/rootfs stretch 2017-05-08T00:00:00Z; debuerreotype-tar /tmp/rootfs - | md5sum'

# debuerreotype-init --keyring /usr/share/keyrings/debian-archive-removed-keys.gpg test-jessie jessie 2017-05-08T00:00:00Z
# debuerreotype-tar test-jessie test-jessie.tar
# md5sum test-jessie.tar
#   354cedd99c08d213d3493a7cf0aaaad6
# ./docker-run.sh sh -euxc 'debuerreotype-init --keyring /usr/share/keyrings/debian-archive-removed-keys.gpg /tmp/rootfs jessie 2017-05-08T00:00:00Z; debuerreotype-tar /tmp/rootfs - | md5sum'
