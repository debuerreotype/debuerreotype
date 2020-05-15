#!/usr/bin/env bash
set -Eeuo pipefail

set -x

./scripts/debuerreotype-version
./ubuntu.sh validate "$SUITE"
