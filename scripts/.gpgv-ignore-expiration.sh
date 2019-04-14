#!/usr/bin/env bash
set -Eeu

# For the sake of EOL releases (whose archive keys have often expired), we need a fake "gpgv" substitute that will essentially ignore *just* key expiration.
# (So we get *some* signature validation instead of using something like "--allow-unauthenticated" or "--force-yes" which disable security entirely instead.)

# Intended usage (APT >= 1.1):
#   apt-get -o Apt::Key::gpgvcommand=/.../.debuerreotype-gpgv-ignore-expiration ...
# or (APT < 1.1):
#   apt-get -o Dir::Bin::gpg=/.../.debuerreotype-gpgv-ignore-expiration ...
# (https://salsa.debian.org/apt-team/apt/commit/12841e8320aa499554ac50b102b222900bb1b879)

# Functionally, this script will scrape "--status-fd" (which is the only way a user of "gpgv" can care about / process expired key metadata) and MITM "gpgv" to replace EXPKEYSIG with GOODSIG instead.

_status_fd() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--status-fd)
				echo "$2"
				return 0
				;;
		esac
		shift
	done
	return 1
}

if fd="$(_status_fd "$@")" && [ -n "$fd" ]; then
	# older bash (3.2, lenny) doesn't support variable file descriptors (hence "eval")
	# (bash: syntax error near unexpected token `$fd')
	eval 'exec gpgv "$@" '"$fd"'> >(sed "s/EXPKEYSIG/GOODSIG/" >&'"$fd"')'
fi

# no "--status-fd"? no worries! ("gpgv" without "--status-fd" doesn't seem to care about expired keys, so we don't have to either)
exec gpgv "$@"
