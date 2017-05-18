# Reproducible, snapshot-based Debian rootfs builds (especially for Docker)

[![Build Status](https://travis-ci.org/tianon/docker-brew-debian-snapshot.svg?branch=master)](https://travis-ci.org/tianon/docker-brew-debian-snapshot)

This is based on [lamby](https://github.com/lamby)'s work for reproducible `debootstrap`:

- https://github.com/lamby/debootstrap/commit/66b15380814aa62ca4b5807270ac57a3c8a0558d
- https://wiki.debian.org/ReproducibleInstalls

## Why?

The goal is to create an auditable, reproducible process for creating rootfs tarballs (especially for use in Docker) of Debian releases, based on point-in-time snapshots from [snapshot.debian.org](http://snapshot.debian.org).

## TODO

- come up with a good generic name for these tools (unlike `docker-deboot`) that makes their generic use and purpose more clear (since there's only one "Docker specific" script here -- `docker-deboot-minimizing-config`)

## Usage

The usage of the scripts here center around a "rootfs" directory, which is both the working directory for building the target rootfs, and contains the `docker-deboot-epoch` file, which records our snapshot.debian.org epoch value (so we can adjust timestamps using it, as it is the basis for our reproducibility).

Available scripts:

- `docker-deboot-init`: create the initial "rootfs", given a suite and a timestamp (in some format `date(1)` can parse); `sources.list` will be pointing at snapshot.debian.org
- `docker-deboot-chroot`: run a command in the given "rootfs" (using `unshare` to mount `/dev`, `/proc`, and `/sys` from the parent environment in a simple, safe way)
- `docker-deboot-apt-get`: run `apt-get` via `docker-deboot-chroot`, including `-o Acquire::Check-Valid-Until=false` to account for older snapshots with (now) invalid `Valid-Until` values
- `docker-deboot-minimizing-config`: apply configuration tweaks to make the rootfs minimal and keep it minimal (especially targeted at Docker images, with comments explicitly describing Docker use cases)
- `docker-deboot-slimify`: remove files such as documentation to create an even smaller rootfs (used for creating `slim` variants of the Docker images, for example)
- `docker-deboot-gen-sources-list`: generate an appropriate `sources.list` in the rootfs given a suite, mirror, and secmirror (especially for updating `sources.list` to point at deb.debian.org before generating outputs)
- `docker-deboot-fixup`: invoked by `docker-deboot-tar` to fixup timestamps and remove known-bad log files for determinism
- `docker-deboot-tar`: deterministically create a tar file of the rootfs

`Dockerfile.builder` is provided for using these scripts in a simple deterministic environment based on Docker, but given a recent enough version of `debootstrap`, they should run fine outside Docker as well (and their deterministic properties have been verified on at least a Gentoo host in addition to the provided Debian-based Docker environment).

The provided `Dockerfile.builder` also includes comments with hints for bootstrapping the environment on a new architecture (which doesn't have a `debian` Docker base image yet).

Full example: (see [`build.sh`](build.sh) for this in practice)

```console
$ docker-deboot-init rootfs stretch 2017-01-01T00:00:00Z
I: Retrieving InRelease
I: Checking Release signature
I: Valid Release signature (key id 126C0D24BD8A2942CC7DF8AC7638D0442B90D010)
...
I: Checking component main on http://snapshot.debian.org/archive/debian/20170101T000000Z...
...
I: Base system installed successfully.

$ cat rootfs/docker-deboot-epoch
1483228800

$ docker-deboot-minimizing-config rootfs

$ docker-deboot-apt-get rootfs update -qq
$ docker-deboot-apt-get rootfs dist-upgrade -yqq
$ docker-deboot-apt-get rootfs install -yqq --no-install-recommends inetutils-ping iproute2
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

$ docker-deboot-gen-sources-list rootfs stretch http://deb.debian.org/debian http://security.debian.org

$ docker-deboot-tar rootfs - | sha256sum
3e028a13d97f0ab7c3d2a31213757bb485e0fecedbd62d4fdf45c51636951b7a  -

$ # try it!  you should get that same sha256sum value!
```

## Why isn't Wheezy reproducible??

Wheezy is a little sad, and will have a delta similar to the following (as seen via `diffoscope`):

```
├── etc/apt/trustdb.gpg
│ │ @@ -1,8 +1,8 @@
│ │ -0000000: 0167 7067 0303 0105 0102 0000 591b faa5  .gpg........Y...
│ │ +0000000: 0167 7067 0303 0105 0102 0000 591b fc0c  .gpg........Y...
│ │  0000010: 0000 0000 0000 0000 0000 0000 0000 0000  ................
│ │  0000020: 0000 0000 0000 0001 0a00 0000 0000 0000  ................
│ │  0000030: 0000 0000 0000 0000 0000 0000 0000 0000  ................
│ │  0000040: 0000 0000 0000 0000 0000 0000 0000 0000  ................
│ │  0000050: 0a00 0000 0000 0000 0000 0000 0000 0000  ................
│ │  0000060: 0000 0000 0000 0000 0000 0000 0000 0000  ................
│ │  0000070: 0000 0000 0000 0000 0a00 0000 0000 0000  ................
```

Presumably this is some sort of timestamp, but that's just a guess.  Suggestions for ways of fixing this would be most welcome!  (Otherwise, we'll just wait for Wheezy to go EOL and forget this ever happened. :trollface:)

## How much have you verified this?

Well, I ran the scripts across seven explicit architectures (`amd64`, `arm64`, `armel`, `armhf`, `i386`, `ppc64el`, `s390x`) and eight explicit suites (`oldstable`, `stable`, `testing`, `unstable`, `wheezy`, `jessie`, `stretch`, `sid`) for a timestamp of `2017-05-16T00:00:00Z` (where supported, since `wheezy`/`oldstable` didn't or no longer currently supports some of those architectures), and the above `wheezy` delta (a few bytes in `etc/apt/trustdb.gpg`) were the _only_ modification to any of the tarballs after several runs.

Additionally, Travis runs with a fixed timestamp value across several suites to verify that their checksums are reproducible, as expected.

For the curious, here's the `SHA256SUMS` of my above cross-architecture test run via [`build-all.sh`](build-all.sh) (minus all `wheezy`/`oldstable` variants, given their minor variability):

```console
$ grep -E '[.]tar[.]xz$' output/20170516/SHA256SUMS | grep -vE ' (wheezy|oldstable)-'
19d20a51a0be6cf2ce8ac874e088bffd3f4a46694c12bdddcb8b9077d14174b6  jessie-amd64.tar.xz
5838edbeec9bf675e71bc3841f2ba5000a71bd37705082510b0c13516aa3df1f  jessie-arm64.tar.xz
1adcacd4708ce2ea4f9c49c2e83f5d503a38b7bd5a077d302149c0a146cad342  jessie-armel.tar.xz
9028befe526b379b697c42689062d98ef62de026b9e170092e6e0da789361db2  jessie-armhf.tar.xz
4c0153b192620fcc2df0bb9dde33540109dc2c53baccbba6d76eed73c44e792d  jessie-i386.tar.xz
17cd94b6a7ed0db6f9f47b1fabc1982a3fb198c6d8447954bc9bcf9c68dfef39  jessie-ppc64el.tar.xz
e456df2536f93607e6a04895dc9fa7e20546d9eec698f34e806cfc27d036e0b3  jessie-s390x.tar.xz
a2a6f68454c47218ed4f7ab81cdbe88c6633b39de53aa528a44c29bda98d8904  jessie-slim-amd64.tar.xz
3aeba4328452b566a30bda012c8f9dee17db146a0fc23356144b70845c89f5e9  jessie-slim-arm64.tar.xz
e53b6053f9a7254fd79b01adabc5f635c84bf5ec4413d90555b99d0281e169fb  jessie-slim-armel.tar.xz
38132023bb70bc2e6a0e0db14be61b06f4c8c5d96fd4af82f4156657b7d2fcc3  jessie-slim-armhf.tar.xz
a89aad14ecf5c7a32f4e93174197cd9fa22af6bb6aa767c14ccb23b5949179d8  jessie-slim-i386.tar.xz
72b710259dbc48c361754fa2176527bc3769d80e7179841f9f58addc346d1e36  jessie-slim-ppc64el.tar.xz
7af3c4367b8b28a00a781e3e44e2a6767cdc603f7bdf14b576514bfa9431e9b9  jessie-slim-s390x.tar.xz
2ad093ee0546f90b5a63e98038453673e54a04ae979fff4a6956b83ee436bf90  sid-amd64.tar.xz
21bf1bb660f89286415a7205ba300412d754658e9f1b5f26db1edf3cb55a2db6  sid-arm64.tar.xz
c6ba3c285a49c78a3f1dbefdf8ad252c6b5ff5e564f2e294e098ef0d50e23e6b  sid-armel.tar.xz
6b70051466e68fb70b36744f2d1067c1ccf2ceea4bb2cfa283046290683394c2  sid-armhf.tar.xz
ca007f753dbcfce323dd3c7a0ed727ce83e1801fd931dccd6b5596716124d83c  sid-i386.tar.xz
f3e07d81676886698563b24a7d56eaa2223aa6aaa88909b910e9c6294ecbaa3d  sid-ppc64el.tar.xz
5b2f536ef7bf48a5281c2ad90f4b0e27f2a325dfc924173ffdb2738fb529ce78  sid-s390x.tar.xz
ec2cb1fb8e94de3ff09285e9a5cb60b7b1ba015f67e608dc838b0b9cc67bc622  sid-slim-amd64.tar.xz
db57298d7191564a4389dcfebf44d7dc115639c85d419683f50d4d47a1c5dcc9  sid-slim-arm64.tar.xz
ffa38bfbe0c55d94f5315f1908363578eb1cd65fd2858216a9e3da4ff8a02e5e  sid-slim-armel.tar.xz
efa7bdc3233384971d88c5086c636520df13e78a82548f0871e9295a64863ac5  sid-slim-armhf.tar.xz
0b5fe689b8455fc13a4e4bc85dbc059d512600112f7200259728f1142314af1d  sid-slim-i386.tar.xz
d4fbca6b32b8aec3f018d4a083316a3ce495b6aefaaebf63464958d813504a23  sid-slim-ppc64el.tar.xz
ad358f55feda2c6560df44c806376ea95fed1ca67c3c599eed207f2360798655  sid-slim-s390x.tar.xz
35c8b6b12b3df1d744f3ee739a55bb96b96514ffb621d1dc0ab20b554bf796fb  stable-amd64.tar.xz
a9e9d5438b9ba695ec16c5bad4c9787d0e04293118fabbe49d11a95e1870093f  stable-arm64.tar.xz
d00d10bf14fcd04b2b4d9abfec99b7ad9c3e11d4a34223ea92e449b8bc39992f  stable-armel.tar.xz
6ffc4de0e7c25f16951978364310c1d5331aed169f3d796849ed148c377dc3b6  stable-armhf.tar.xz
154772af7aea82ea8d64dbb35e2e953cc15d8005af354de8f388785761ec6841  stable-i386.tar.xz
e09b5edb39d7a77763f1a01cb0bb7321744379a0df288da70d78868958d7239b  stable-ppc64el.tar.xz
7bc4f061eba79c8fef5979890af58837dcbb3626ef19193254899545dfd456d7  stable-s390x.tar.xz
dc532ef3d8c78b3bd99b3d16cbf482231c2e3cbaf5a23a56804f55a8b30f852e  stable-slim-amd64.tar.xz
10c69f3595b21547f85daceb2b93c59593da7beaa70ff0c04262418e77c55345  stable-slim-arm64.tar.xz
468eeb3920c1c500ab4faa7d6969bfa9d98206356bc7a6fbb063975e90332b5a  stable-slim-armel.tar.xz
5ad60635d14365c17ebbe310c50f30e19360f3844c94acaaaba3cd4ac8df2f77  stable-slim-armhf.tar.xz
fc92569d4609fa38249e7ad7018c595131efe89629ec7e38b4d96403536971b2  stable-slim-i386.tar.xz
51cd2efb722a498af73ce3f39ac0f2dd7d6b4ccc995d8aa6d866f8e96e0552f3  stable-slim-ppc64el.tar.xz
591439821e4157e943500f60a5d0344c43a6fb0019c655b513723c570e0d25f6  stable-slim-s390x.tar.xz
3a530d065ffe830dd0d0d79b9009bf7ad6f4804cee219134d3b6a58cc5b429b4  stretch-amd64.tar.xz
3ecceecbc4ff2619de3294ea0b416016f33d46970b1571ade1231c87eb2251a5  stretch-arm64.tar.xz
58feb6e995118cf7f1d6423e3d37fa907f3ef9b33441b50d8100e04ad100a69e  stretch-armel.tar.xz
1437c63eee9d055ac1ef8b7a3190536d10c9230b8f82ea7ceb04875faad69427  stretch-armhf.tar.xz
6160312e020938b63de44a4c1f976e01654f79e166fec1488cc69481406879d7  stretch-i386.tar.xz
db2ceb46a7ff12c49c95b0f4b3f4b758192291f31c065aae43625df995737137  stretch-ppc64el.tar.xz
ca9499a8ed0f1c886bcc342aaebad3530a436115bdf6f177d22d005d128356ba  stretch-s390x.tar.xz
bd7e9721aac42b94661a3d840d34e86c1da5c38d9a2ead8d23201405e5e707d9  stretch-slim-amd64.tar.xz
575c6d6f107da4053e80c64c2f53835f77fc36ab730059ea0a4782613bcdcc38  stretch-slim-arm64.tar.xz
80e44eb4b606052d8d9907905619b51534ffb2905001b745ffb204051ec407a5  stretch-slim-armel.tar.xz
ab5e866561962d1dade24773ccff421a2e9c56e7f35e5d527ffeef4af959d00c  stretch-slim-armhf.tar.xz
3ed031cda8832f68bcb254150de2e4010c238d6ab6c0107c80d8c2b24e2b0aac  stretch-slim-i386.tar.xz
eecb1152e178fdd718545ecad0706bfc01745bdc0d80a996679c59352213b253  stretch-slim-ppc64el.tar.xz
174a744072156c257098c456ded9f0367693ffc322ab55f7d9bb5027cf1e35d6  stretch-slim-s390x.tar.xz
e7df1d07b07f6a8eac00c256ec30f2b129d356af9f78fe95a0e2d7867fc030c8  testing-amd64.tar.xz
0ab8a3802b46cfc47eb24c868eb24098f6f7a185b22880ed6d2468fe0703f751  testing-arm64.tar.xz
15781dcad35fb02f4c8b972b958d620912cb049ae626dbca885a5fb5296b60d8  testing-armel.tar.xz
da5556db64946f47dadefd48e33cbce39048f6538e5ba121b3b77cb07d1e5040  testing-armhf.tar.xz
308cbf15f0cb2eb513621efe1e70688cae18ac78e7dcd75d789e0148f23882a1  testing-i386.tar.xz
dd0a3609ff8937c11d73df8ff7f44118e0f4753b96f9c91900d9b713fec8c26f  testing-ppc64el.tar.xz
c500e70628edc2698cc97e4b749b8d986475dea56235d9013c5fa01ec046b512  testing-s390x.tar.xz
4d6f2ea6b35c29bb4d8334d38e54d9619331e0912e527e2ba6046925b61d7093  testing-slim-amd64.tar.xz
2585487f4ac231ec77e7b8c71a1b4613594945d5d49bfdf0c986219c857aa5db  testing-slim-arm64.tar.xz
5058e55e9fda8cc91561857a0786524ae813d7bd5d5f888b7494f4caa3c2864a  testing-slim-armel.tar.xz
2acc86600535049c9e1df37ce698b9820b15d8396b7686be8b1463ab9267c365  testing-slim-armhf.tar.xz
79b590d5b638d2537c7f1093fd1434c4efb849e312c4b03e33998bd532ca8c39  testing-slim-i386.tar.xz
b00d77dc7e58af82ed4d485c7b6de358135b17ae6508022e093cd235d5acef9d  testing-slim-ppc64el.tar.xz
86b790c071449aeeae6919543dc2a6658cb478bab5f9d7a4ecfda8a697ae6b46  testing-slim-s390x.tar.xz
8b5705b3e4cd15b9a3c4f4589ba4ab4437bee50524bd7e3e1ef0c4e92f1dbd82  unstable-amd64.tar.xz
019c9eca9b0fdfe44aeff050acddb5783376bfbe85e003b97f587dca5877d809  unstable-arm64.tar.xz
35a9a900d8bddd3acbdd9cfccbc8d6e69abaa4d820db0c183e453aeebd3bcdbf  unstable-armel.tar.xz
3b02e0107e5661bba741a468f17ab8b1a6530f202ebc306e9520690ec0c1e426  unstable-armhf.tar.xz
f5bf3d55069fae1ffde53674b38d0a73ef9c57d4991198b6feda2bfae9a4fecf  unstable-i386.tar.xz
65227c0c6fcb28e144aea67f1aab3d125553f00a535bec45dcca50a7290ecde9  unstable-ppc64el.tar.xz
5125d798aa36860e62f967fd96c77adf524e6e9fca351247dae573a31c01c6c3  unstable-s390x.tar.xz
9c22f153e435db8f966287b2fb9ca3d2e7121d7824956d890d6aa184fa99afdf  unstable-slim-amd64.tar.xz
70f29c0ebb17abebc67daa2f1e30e0fd5744d659726e54d7e0277bc4072f8abc  unstable-slim-arm64.tar.xz
0030e9732fcf498eddeb53cc50ee6157945b18dffabc87ec2fa86fb802bdb1be  unstable-slim-armel.tar.xz
0ace6b8f602122ba042a1b72689a6950c62552f99e1295d5c6b39d919b375ecc  unstable-slim-armhf.tar.xz
a1417c68a1d1fa30f12b257133ae8ecb25f550acb864e6fd6b786b837da83bda  unstable-slim-i386.tar.xz
ccaeca3d9ccbd2826021bee035217fca7395af548794bd4791c76d4bb32add22  unstable-slim-ppc64el.tar.xz
d236505929149f4a76ecd03fdb3790650d47d8e7ec942e5d964cd74fada42442  unstable-slim-s390x.tar.xz
```
