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
		\
# used in oci-image.sh
		jq pigz \
	; \
	rm -rf /var/lib/apt/lists/*

# fight the tyrrany of HSTS (which destroys our ability to transparently cache snapshot.debian.org responses)
ENV WGETRC /.wgetrc
RUN echo 'hsts=0' >> "$WGETRC"

# https://github.com/debuerreotype/debuerreotype/issues/100
# https://tracker.debian.org/pkg/distro-info-data
# http://snapshot.debian.org/package/distro-info-data/
# http://snapshot.debian.org/package/distro-info-data/0.68/
RUN set -eux; \
	wget -O distro-info-data.deb 'http://snapshot.debian.org/archive/debian/20251018T202603Z/pool/main/d/distro-info-data/distro-info-data_0.68_all.deb'; \
	echo 'e9ae181a26235a46ff852cb3445752686b96ea83 *distro-info-data.deb' | sha1sum --strict --check -; \
	\
	versionEx="$(dpkg-query --show --showformat '${Version}\n' distro-info-data || :)"; \
	versionDl="$(dpkg-deb --field distro-info-data.deb Version)"; \
	if dpkg --compare-versions "$versionDl" '>>' "$versionEx"; then \
# only install the version we just downloaded if it's actually newer than the version already installed (it gets frequent backports/stable updates and is installed as a dependency)
		apt-get install -y ./distro-info-data.deb; \
	fi; \
	rm distro-info-data.deb; \
	\
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
	rm debootstrap-download-main.patch

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


# a few example sha256sum values for amd64:

# debuerreotype-init --keyring /usr/share/keyrings/debian-archive-removed-keys.pgp --no-merged-usr test-stretch stretch 2017-05-08T00:00:00Z
# debuerreotype-tar test-stretch test-stretch.tar
# sha256sum test-stretch.tar
#   7b295f07692e13e3aaec0709e38f5fbfe3b7153d024c556430be70fd845fc174
# ./docker-run.sh sh -euxc 'debuerreotype-init --keyring /usr/share/keyrings/debian-archive-removed-keys.pgp --no-merged-usr /tmp/rootfs stretch 2017-05-08T00:00:00Z; debuerreotype-tar /tmp/rootfs - | sha256sum'

# debuerreotype-init --keyring /usr/share/keyrings/debian-archive-removed-keys.pgp --no-merged-usr test-jessie jessie 2017-05-08T00:00:00Z
# debuerreotype-tar test-jessie test-jessie.tar
# sha256sum test-jessie.tar
#   5d1daeb8e817a56d28b65b4fa5eb09ebb1963299a0ccfd2a37c07560779653cd
# ./docker-run.sh sh -euxc 'debuerreotype-init --keyring /usr/share/keyrings/debian-archive-removed-keys.pgp --no-merged-usr /tmp/rootfs jessie 2017-05-08T00:00:00Z; debuerreotype-tar /tmp/rootfs - | sha256sum'
