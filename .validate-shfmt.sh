#!/usr/bin/env bash
set -Eeuo pipefail

shopt -s dotglob globstar

thisDir="$(dirname "$(readlink -f "$BASH_SOURCE")")"
exec "$thisDir/.shfmt.sh" -d **/*.sh scripts/debuerreotype-*
