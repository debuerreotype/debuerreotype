# docker run --cap-add SYS_ADMIN --tmpfs /tmp:dev,exec,suid,noatime ...

# bootstrapping a new architecture?
#   ./scripts/debuerreotype-init /tmp/docker-rootfs stretch now
#   ./scripts/debuerreotype-minimizing-config /tmp/docker-rootfs
#   ./scripts/debuerreotype-gen-sources-list /tmp/docker-rootfs stretch http://deb.debian.org/debian http://security.debian.org/debian-security
#   ./scripts/debuerreotype-tar /tmp/docker-rootfs - | docker import - debian:stretch-slim
# alternate:
#   debootstrap --variant=minbase stretch /tmp/docker-rootfs
#   tar -cC /tmp/docker-rootfs . | docker import - debian:stretch-slim
# (or your own favorite set of "debootstrap" commands to create a base image for building this one FROM)
FROM debian:stretch-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
		debootstrap \
		wget ca-certificates \
		xz-utils \
		\
		gnupg dirmngr \
	&& rm -rf /var/lib/apt/lists/*

# see ".dockerignore"
COPY . /opt/debuerreotype
RUN set -ex; \
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
#   6f965e84837215ac0aa375e3391392db

# debuerreotype-init test-jessie jessie 2017-05-08T00:00:00Z
# debuerreotype-tar test-jessie test-jessie.tar
# md5sum test-jessie.tar
#   93ad9886b0e0da17aae584d3a0236d0c
