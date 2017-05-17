# docker run --cap-add SYS_ADMIN --tmpfs /tmp:dev,exec,suid,noatime ...

FROM debian:stretch-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
		debootstrap \
		xz-utils \
	&& rm -rf /var/lib/apt/lists/*

COPY scripts /opt/docker-deboot
RUN set -ex; \
	cd /opt/docker-deboot; \
	for f in *.sh; do \
		ln -svL "$PWD/$f" "/usr/local/bin/docker-deboot-$(basename "$f" '.sh')"; \
	done

WORKDIR /tmp

# docker-deboot-init test-stretch stretch 2017-05-08T00:00:00Z
# docker-deboot-tar test-stretch test-stretch.tar
# md5sum test-stretch.tar
#   b58e1c32013c9815d83b8bed3db189a4

# docker-deboot-init test-jessie jessie 2017-05-08T00:00:00Z
# docker-deboot-tar test-jessie test-jessie.tar
# md5sum test-jessie.tar
#   d40354bf29cb69a0359e828f2cb533ba
