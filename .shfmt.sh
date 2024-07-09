#!/usr/bin/env bash
set -Eeuo pipefail

# https://github.com/mvdan/sh/releases
# https://hub.docker.com/r/mvdan/shfmt/tags
shfmtVersion='3.6.0'
shfmtImage="mvdan/shfmt:v$shfmtVersion"

user="$(id -u):$(id -g)"
args=(
	--interactive
	--name shfmt-debuerreotype
	--rm

	--mount type=bind,src="$PWD",dst="$PWD"
	--user "$user"
	--workdir "$PWD"

	--entrypoint shfmt
)

if [ -t 0 ] && [ -t 1 ]; then
	args+=(--tty)
fi

set -- --binary-next-line --case-indent --space-redirects "$@"

docker pull "$shfmtImage" > /dev/null
exec docker run "${args[@]}" "$shfmtImage" "$@"
