# docker run --cap-add SYS_ADMIN --tmpfs /tmp:dev,exec,suid,noatime ...

# bootstrapping a new architecture?
#   ./scripts/docker-deboot-init /tmp/docker-rootfs stretch now
#   ./scripts/docker-deboot-minimizing-config /tmp/docker-rootfs
#   ./scripts/docker-deboot-gen-sources-list /tmp/docker-rootfs stretch http://deb.debian.org/debian http://security.debian.org
#   ./scripts/docker-deboot-tar /tmp/docker-rootfs - | docker import - debian:stretch-slim
# alternate:
#   debootstrap --variant=minbase stretch /tmp/docker-rootfs
#   tar -cC /tmp/docker-rootfs . | docker import - debian:stretch-slim
# (or your own favorite set of "debootstrap" commands to create a base image for building this one FROM)
FROM debian:stretch-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
		debootstrap \
		xz-utils \
	&& rm -rf /var/lib/apt/lists/*

COPY scripts /opt/docker-deboot/scripts
RUN set -ex; \
	cd /opt/docker-deboot/scripts; \
	for f in docker-deboot-*; do \
		ln -svL "$PWD/$f" "/usr/local/bin/$f"; \
	done

WORKDIR /tmp

# a few example md5sum values for amd64:

# docker-deboot-init test-stretch stretch 2017-05-08T00:00:00Z
# docker-deboot-tar test-stretch test-stretch.tar
# md5sum test-stretch.tar
#   b58e1c32013c9815d83b8bed3db189a4

# docker-deboot-init test-jessie jessie 2017-05-08T00:00:00Z
# docker-deboot-tar test-jessie test-jessie.tar
# md5sum test-jessie.tar
#   d40354bf29cb69a0359e828f2cb533ba
