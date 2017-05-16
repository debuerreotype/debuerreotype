# docker run --cap-add SYS_ADMIN --tmpfs /tmp:dev,exec,suid,noatime ...

FROM debian:stretch-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
		debootstrap \
	&& rm -rf /var/lib/apt/lists/*

COPY scripts /opt/docker-deboot
RUN set -ex; \
	cd /opt/docker-deboot; \
	for f in *.sh; do \
		ln -svL "$PWD/$f" "/usr/local/bin/docker-deboot-$(basename "$f" '.sh')"; \
	done

WORKDIR /tmp

# docker-deboot-init stretch 2017-05-08T00:00:00Z test-stretch
# docker-deboot-tar test-stretch test-stretch.tar
# md5sum test-stretch.tar
#   93db8c96db59bc6023177a845d1c8263

# docker-deboot-init jessie 2017-05-08T00:00:00Z test-jessie
# docker-deboot-tar test-jessie test-jessie.tar
# md5sum test-jessie.tar
#   9b60134210c0c848f796e7642c1f75f4
