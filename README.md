# Notice
This fork is to ensure that we have an audited copy of debuerreotype to use for our builds. For the original, see [debuerreotype/debuerreotype](https://github.com/debuerreotype/debuerreotype)

# Debuerreotype

Reproducible, [snapshot](http://snapshot.debian.org)-based Debian rootfs builds (especially for Docker).

This is based on [lamby](https://github.com/lamby)'s work for reproducible `debootstrap`:

- https://github.com/lamby/debootstrap/commit/66b15380814aa62ca4b5807270ac57a3c8a0558d
- https://wiki.debian.org/ReproducibleInstalls

### "Debuerreotype"?

The name is an attempt at riffing off the photography basis of the word "snapshot".  The [daguerreotype](https://en.wikipedia.org/wiki/Daguerreotype) process was an early method for taking photographs, and this is a method for taking "photographs" of Debian at a given point in time.

## Why?

The goal is to create an auditable, reproducible process for creating rootfs tarballs (especially for use in Docker) of Debian releases, based on point-in-time snapshots from [snapshot.debian.org](http://snapshot.debian.org).

However, as noted below, the only strictly Docker-specific script is `debuerreotype-minimizing-config`, which applies many configuration tweaks which are useful for Docker users and may or may not be useful outside of that context.

## Usage

The usage of the scripts here center around a "rootfs" directory, which is both the working directory for building the target rootfs, and contains the `debuerreotype-epoch` file, which records our snapshot.debian.org epoch value (so we can adjust timestamps using it, as it is the basis for our reproducibility).

Available scripts:

| *script* | *purpose* |
| --- | --- |
| `debuerreotype-init` | create the initial "rootfs", given a suite and a timestamp (in some format `date(1)` can parse); `sources.list` will be pointing at snapshot.debian.org |
| `debuerreotype-chroot` | run a command in the given "rootfs" (using `unshare` to mount `/dev`, `/proc`, and `/sys` from the parent environment in a simple, safe way) |
| `debuerreotype-apt-get` | run `apt-get` via `debuerreotype-chroot`, including `-o Acquire::Check-Valid-Until=false` to account for older snapshots with (now) invalid `Valid-Until` values |
| `debuerreotype-minimizing-config` | apply configuration tweaks to make the rootfs minimal and keep it minimal (especially targeted at Docker images, with comments explicitly describing Docker use cases) |
| `debuerreotype-slimify` | remove files such as documentation to create an even smaller rootfs (used for creating `slim` variants of the Docker images, for example) |
| `debuerreotype-gen-sources-list` | generate an appropriate `sources.list` in the rootfs given a suite, mirror, and secmirror (especially for updating `sources.list` to point at deb.debian.org before generating outputs) |
| `debuerreotype-fixup` | invoked by `debuerreotype-tar` to fixup timestamps and remove known-bad log files for determinism |
| `debuerreotype-tar` | deterministically create a tar file of the rootfs |
| `debuerreotype-version` | print out the version of the current `debuerreotype` installation |

Full example:

```console
$ debuerreotype-init rootfs stretch 2017-01-01T00:00:00Z
I: Retrieving InRelease
I: Checking Release signature
I: Valid Release signature (key id 126C0D24BD8A2942CC7DF8AC7638D0442B90D010)
...
I: Checking component main on http://snapshot.debian.org/archive/debian/20170101T000000Z...
...
I: Base system installed successfully.

$ cat rootfs/debuerreotype-epoch
1483228800

$ debuerreotype-minimizing-config rootfs

$ debuerreotype-apt-get rootfs update -qq
$ debuerreotype-apt-get rootfs dist-upgrade -yqq
$ debuerreotype-apt-get rootfs install -yqq --no-install-recommends inetutils-ping iproute2
debconf: delaying package configuration, since apt-utils is not installed
Selecting previously unselected package libelf1:amd64.
(Reading database ... 6299 files and directories currently installed.)
Preparing to unpack .../0-libelf1_0.166-2.2_amd64.deb ...
Unpacking libelf1:amd64 (0.166-2.2) ...
Selecting previously unselected package libmnl0:amd64.
Preparing to unpack .../1-libmnl0_1.0.4-2_amd64.deb ...
Unpacking libmnl0:amd64 (1.0.4-2) ...
Selecting previously unselected package iproute2.
Preparing to unpack .../2-iproute2_4.9.0-1_amd64.deb ...
Unpacking iproute2 (4.9.0-1) ...
Selecting previously unselected package netbase.
Preparing to unpack .../3-netbase_5.3_all.deb ...
Unpacking netbase (5.3) ...
Selecting previously unselected package inetutils-ping.
Preparing to unpack .../4-inetutils-ping_2%3a1.9.4-2+b1_amd64.deb ...
Unpacking inetutils-ping (2:1.9.4-2+b1) ...
Setting up libelf1:amd64 (0.166-2.2) ...
Processing triggers for libc-bin (2.24-8) ...
Setting up libmnl0:amd64 (1.0.4-2) ...
Setting up netbase (5.3) ...
Setting up inetutils-ping (2:1.9.4-2+b1) ...
Setting up iproute2 (4.9.0-1) ...
Processing triggers for libc-bin (2.24-8) ...

$ debuerreotype-gen-sources-list rootfs stretch http://deb.debian.org/debian http://security.debian.org

$ debuerreotype-tar rootfs - | sha256sum
0542bec04135ed60ed5763f0bcf90381d4e5e33786d57aba5aa4b0fc4e43478a  -

$ # try it!  you should get that same sha256sum value!
```

## How much have you verified this?

Well, I ran the scripts across seven explicit architectures (`amd64`, `arm64`, `armel`, `armhf`, `i386`, `ppc64el`, `s390x`) and eight explicit suites (`oldstable`, `stable`, `testing`, `unstable`, `wheezy`, `jessie`, `stretch`, `sid`) for a timestamp of `2017-05-16T00:00:00Z` (where supported, since `wheezy`/`oldstable` didn't or no longer currently supports some of those architectures), and there were no modifications to any of the tarballs after several runs across several days.

Additionally, Travis runs with a fixed timestamp value across several suites to verify that their checksums are reproducible, as expected.

From time to time, comments in the files generated by `debuerreotype-minimizing-config` might change (for example), which would obviously result in a different checksum, but a simple [`diffoscope`](https://diffoscope.org/) should be sufficient to verify that the change is benign.
