# docker run --cap-add SYS_ADMIN --cap-drop SETFCAP --tmpfs /tmp:dev,exec,suid,noatime ...

# bootstrapping a new architecture?
#   ./scripts/debuerreotype-init /tmp/docker-rootfs bullseye now
#   ./scripts/debuerreotype-minimizing-config /tmp/docker-rootfs
#   ./scripts/debuerreotype-debian-sources-list /tmp/docker-rootfs bullseye
#   ./scripts/debuerreotype-tar /tmp/docker-rootfs - | docker import - debian:bullseye-slim
# alternate:
#   debootstrap --variant=minbase bullseye /tmp/docker-rootfs
#   tar -cC /tmp/docker-rootfs . | docker import - debian:bullseye-slim
# (or your own favorite set of "debootstrap" commands to create a base image for building this one FROM)
FROM debian:bullseye-slim

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
# http://snapshot.debian.org/package/distro-info-data/0.64/
RUN set -eux; \
	wget -O distro-info-data.deb 'http://snapshot.debian.org/archive/debian/20250415T025012Z/pool/main/d/distro-info-data/distro-info-data_0.64_all.deb'; \
	echo '9ba9c7b3b8a033c8624a97c956136f5ab7c9b73b *distro-info-data.deb' | sha1sum --strict --check -; \
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
# https://salsa.debian.org/installer-team/debootstrap/-/merge_requests/76
	if ! grep EXCLUDE_DEPENDENCY /usr/sbin/debootstrap; then \
		wget -O debootstrap-exclude-usrmerge.patch 'https://people.debian.org/~tianon/debootstrap-mr-76--exclude-usrmerge.patch'; \
		echo '4aae49edcd562d8f38bcbc00b26ae485f4e65dd36bd4a250a16cdb912398df7e *debootstrap-exclude-usrmerge.patch' | sha256sum --strict --check -; \
		sed -ri \
			-e 's!([ab])/debootstrap!\1/usr/sbin/debootstrap!g' \
			-e 's!([ab])/scripts/debian-common!\1/usr/share/debootstrap/scripts/debian-common!g' \
			debootstrap-exclude-usrmerge.patch \
		; \
		patch -p1 --input="$PWD/debootstrap-exclude-usrmerge.patch" --directory=/; \
		rm debootstrap-exclude-usrmerge.patch; \
	fi; \
	\
# https://salsa.debian.org/installer-team/debootstrap/-/merge_requests/81
	if ! grep EXCLUDE_DEPENDENCY /usr/share/debootstrap/functions; then \
		wget -O debootstrap-exclude-usrmerge-harder.patch 'https://people.debian.org/~tianon/debootstrap-mr-81--exclude-usrmerge-harder.patch'; \
		echo 'ed65c633dd3128405193eef92355a27a3302dc0c558adf956f04af4500a004c9 *debootstrap-exclude-usrmerge-harder.patch' | sha256sum --strict --check -; \
		sed -ri \
			-e 's!([ab])/debootstrap!\1/usr/sbin/debootstrap!g' \
			-e 's!([ab])/functions!\1/usr/share/debootstrap/functions!g' \
			debootstrap-exclude-usrmerge-harder.patch \
		; \
		patch -p1 --input="$PWD/debootstrap-exclude-usrmerge-harder.patch" --directory=/; \
		rm debootstrap-exclude-usrmerge-harder.patch; \
	fi

# see ".dockerignore"
COPY . /opt/debuerreotype
RUN set -eux; \
	cd /opt/debuerreotype/scripts; \
	for f in debuerreotype-*; do \
		ln -svL "$PWD/$f" "/usr/local/bin/$f"; \
	done; \
	version="$(debuerreotype-version)"; \
	[ "$version" != 'unknown' ]; \
	echo "debuerreotype version $version"

WORKDIR /tmp

# a few example md5sum values for amd64:

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
