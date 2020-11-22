#!/usr/bin/env bash
set -Eeuo pipefail

dockerImage="$(./.docker-image.sh)"
dockerImage+='-ubuntu'
{
	cat Dockerfile
	echo 'RUN apt-get update && apt-get install -y --no-install-recommends ubuntu-keyring && rm -rf /var/lib/apt/lists/*'
} | docker build --tag "$dockerImage" --file - .

mkdir -p validate

set -x

./scripts/debuerreotype-version
./docker-run.sh --image="$dockerImage" --no-build ./examples/ubuntu.sh validate "$SUITE"
