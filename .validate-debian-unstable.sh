#!/usr/bin/env bash
set -Eeuo pipefail

dockerImage="$(./.docker-image.sh)"
dockerImage+='-unstable'
sed -re 's/^(FROM[[:space:]]+[^:]+):[^[:space:]]+/\1:unstable-slim/' Dockerfile | docker build --pull --tag "$dockerImage" --file - .

# trust, but verify
docker run --rm "$dockerImage" sh -c 'exec grep -rn unstable /etc/apt/sources.list*'

exec ./.validate-debian.sh --image="$dockerImage" --no-build "$@"
