# docker run --cap-add SYS_ADMIN --cap-drop SETFCAP --tmpfs /tmp:dev,exec,suid,noatime ...

# bootstrapping a new architecture?
#   ./scripts/debuerreotype-init /tmp/docker-rootfs buster now
#   ./scripts/debuerreotype-minimizing-config /tmp/docker-rootfs
#   ./scripts/debuerreotype-debian-sources-list /tmp/docker-rootfs buster
#   ./scripts/debuerreotype-tar /tmp/docker-rootfs - | docker import - debian:buster-slim
# alternate:
#   debootstrap --variant=minbase buster /tmp/docker-rootfs
#   tar -cC /tmp/docker-rootfs . | docker import - debian:buster-slim
# (or your own favorite set of "debootstrap" commands to create a base image for building this one FROM)
FROM debian:buster-slim

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		debian-ports-archive-keyring \
		debootstrap \
		wget ca-certificates \
		xz-utils \
		\
		gnupg dirmngr \
	; \
	rm -rf /var/lib/apt/lists/*

# https://github.com/debuerreotype/debuerreotype/issues/100
# http://snapshot.debian.org/package/distro-info-data/
# http://snapshot.debian.org/package/distro-info-data/0.46/
RUN set -eux; \
	wget -O distro-info-data.deb 'http://snapshot.debian.org/archive/debian/20210130T024253Z/pool/main/d/distro-info-data/distro-info-data_0.46_all.deb'; \
	echo '9f06132ddd508802ee0272ecac8b1f301426ffea *distro-info-data.deb' | sha1sum --strict --check -; \
	apt-get install -y ./distro-info-data.deb; \
	rm distro-info-data.deb; \
	[ -s /usr/share/distro-info/debian.csv ]

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

# debuerreotype-init test-stretch stretch 2017-05-08T00:00:00Z
# debuerreotype-tar test-stretch test-stretch.tar
# md5sum test-stretch.tar
#   14206d5b9b2991e98f5214c3d310e4fa
# ./docker-run.sh sh -euxc 'debuerreotype-init /tmp/rootfs stretch 2017-05-08T00:00:00Z; debuerreotype-tar /tmp/rootfs - | md5sum'

# debuerreotype-init test-jessie jessie 2017-05-08T00:00:00Z
# debuerreotype-tar test-jessie test-jessie.tar
# md5sum test-jessie.tar
#   a5b38410ca3f519117966a33474f1267
# ./docker-run.sh sh -euxc 'debuerreotype-init /tmp/rootfs jessie 2017-05-08T00:00:00Z; debuerreotype-tar /tmp/rootfs - | md5sum'
