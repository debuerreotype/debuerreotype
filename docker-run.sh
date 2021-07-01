#!/usr/bin/env bash
set -Eeuo pipefail

# usage: mkdir -p output && ./run-script.sh ./examples/debian.sh output ...

thisDir="$(readlink -vf "$BASH_SOURCE")"
thisDir="$(dirname "$thisDir")"

source "$thisDir/scripts/.constants.sh" \
	--flags 'image:' \
	--flags 'no-bind' \
	--flags 'no-build' \
	--flags 'pull' \
	-- \
	'[--image=foo/bar:baz] [--no-build] [--no-bind] [--pull] [script/command]' \
	'./examples/debian.sh output stretch 2017-05-08T00:00:00Z
--no-build --image=debuerreotype:ubuntu ./examples/ubuntu.sh output xenial'

eval "$dgetopt"
image=
build=1
bindMount=1
pull=
while true; do
	flag="$1"; shift
	dgetopt-case "$flag"
	case "$flag" in
		--image) image="$1"; shift ;;
		--no-bind) bindMount= ;;
		--no-build) build= ;;
		--pull) pull=1 ;;
		--) break ;;
		*) eusage "unknown flag '$flag'" ;;
	esac
done

if [ -z "$image" ]; then
	image="$("$thisDir/.docker-image.sh")"
fi
if [ -n "$build" ]; then
	docker build ${pull:+--pull} --tag "$image" "$thisDir"
elif [ -n "$pull" ]; then
	docker pull "$image"
else
	# make sure "docker run" doesn't pull (we have `--no-build` and no explicit `--pull`)
	docker image inspect "$image" > /dev/null
fi

args=(
	--hostname debuerreotype
	--init
	--interactive
	--rm

	# we ought to be able to mount/unshare
	--cap-add SYS_ADMIN
	# make sure we don't get extended attributes
	--cap-drop SETFCAP

	# AppArmor also blocks mount/unshare :)
	--security-opt apparmor=unconfined

	# --debian-eol potato wants to run "chroot ... mount ... /proc" which gets blocked (i386, ancient binaries, blah blah blah)
	--security-opt seccomp=unconfined
	# (other arches see this occasionally too)

	--tmpfs /tmp:dev,exec,suid,noatime
	--env TMPDIR=/tmp

	--workdir /workdir
)
if [ -n "$bindMount" ]; then
	args+=( --mount "type=bind,src=$PWD,dst=/workdir" )
else
	args+=( --volume /workdir )
fi

if [ -t 0 ] && [ -t 1 ]; then
	args+=( --tty )
fi

exec docker run "${args[@]}" "$image" "$@"
