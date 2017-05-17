# Debian in Docker (reproducible snapshot-based builds)

[![Build Status](https://travis-ci.org/tianon/docker-brew-debian-snapshot.svg?branch=master)](https://travis-ci.org/tianon/docker-brew-debian-snapshot)

This is based on [lamby](https://github.com/lamby)'s work for reproducible `debootstrap`:

- https://github.com/lamby/debootstrap/commit/66b15380814aa62ca4b5807270ac57a3c8a0558d
- https://wiki.debian.org/ReproducibleInstalls

## Why?

The goal is to create an auditable, reproducible process for creating rootfs tarballs (especially for use in Docker) of Debian releases, based on point-in-time snapshots from [snapshot.debian.org](http://snapshot.debian.org).

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
89187412edf5b5a487f33a38bff279fff4e1e6c096010417785880076f934112  -
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
a96ecb0d98c39db8d4bbb13dbb29964a86cae7b6485208bbc0b30a50dde7aa45  jessie-amd64.tar.xz
f31feb780e3566d8657d2ea4dfe1ceac44a88a29d535706c3992d138b8a89b3f  jessie-arm64.tar.xz
d119d20fb64b6dfcf1522a892613664f0072ddbadcdd109a1f4595fbc1f819ab  jessie-armel.tar.xz
b6c43b12b0a45a9eaf647ea2bb49b5a53801cedbd12852ba2456a73e380bae93  jessie-armhf.tar.xz
1495f102c1ade9a6748a921fda64fb1e8b9cfa169effb4bc10081cd4ee1c1669  jessie-i386.tar.xz
40e4636825a12640b3061d9b4d9046bc39829906663c6278cf4835e1db6975b5  jessie-ppc64el.tar.xz
857bee95616c00a2356d93f821c4c309dc4d5dd5c390dd10b1793d5d9c1d7120  jessie-s390x.tar.xz
0a11d53b1c8514cc2f52ad55bea0b5f3b3471d4548edaca03191b3db53b314ff  jessie-slim-amd64.tar.xz
5c271d0dd9df56ee7e189dc9fa3b4ad118e0a75bf683ceb7989013864e6589e3  jessie-slim-arm64.tar.xz
c180e827d2c16dff5ffc48a9a7c486df980f09091493324a7622d5cac859048f  jessie-slim-armel.tar.xz
f3c45ae35a1ab8d0de724a3634021c8264d1ada0d383e4596b31825114bf087e  jessie-slim-armhf.tar.xz
3ff5235712686b2449c207042252a15fbf6fbef78a0f43d921a1f45c149b8832  jessie-slim-i386.tar.xz
6b62eae3d21ecb9c8c65dfc69a7c298c4f96aa463f118f190a627b3b35a1a9ef  jessie-slim-ppc64el.tar.xz
ca0539490b8577f0a460ceaab6cb96c11a370799fe69879b93f2087ee1de90d5  jessie-slim-s390x.tar.xz
052bbf2e6bb8ec178ccef9341bca716b9c7deba77563b7a82db2ed486ccd0f97  sid-amd64.tar.xz
cf050a49de9056d2a717e1e11032e562cb4b61e4f04c2e63f63ba6688ddb8977  sid-arm64.tar.xz
95ce89448a32ea5fc3a5fd6acaac4039d3c3e665db88310e7d54e5a9b6b9dce6  sid-armel.tar.xz
7d1370894efc35a0f84b8cf847777de3aac5080bb70085402db4980527b10807  sid-armhf.tar.xz
3a0715d8bb1dbfa3ff2e442af9bfa1de1ed571769dda8be07d42c6a278f20bff  sid-i386.tar.xz
fc0612d811603cf1322b7ccc12cd5276d6e90f94d13bbd6e3ffb463381efa368  sid-ppc64el.tar.xz
aefd5adcd143cdb026a8f8a0297d702474dd5dd437a9404bce13feb058ce9ed6  sid-s390x.tar.xz
4784c566ef61909af1a27c4eb94e0f0f04930f0b8bb1c1c4607fc1e874094771  sid-slim-amd64.tar.xz
ec827df2a7e6a578d769de188e25df06e7bf0b5e10dac06623e16a085ce38af3  sid-slim-arm64.tar.xz
1436af04602dd1abb11b7119aefffb842221610c02caac0539d9f732f518c544  sid-slim-armel.tar.xz
910c4cc19dc90ff523018f9b4bc6ca370bb67c2d3b7d1bfc153c94fa6bea3a21  sid-slim-armhf.tar.xz
948bf76b40850e290d24cda6cc2eec9e338b2b4d2ede444adaafdf772774b914  sid-slim-i386.tar.xz
f90ed125f93decc6c02aedf266c2d33765238def7b3750b142f1d662a30d3f6f  sid-slim-ppc64el.tar.xz
0cc8f3b81de4a04042963204b90d831d02cca03794cb9258d3547864c936dbb3  sid-slim-s390x.tar.xz
679e796510c3241f0fb675c836654cb3bcd0c8fcf73e3d24c3ffc7edefdddfd9  stable-amd64.tar.xz
1a74a24005bb553a11060d53611716f42d5e6725a2442ac59b7cf8f26eece720  stable-arm64.tar.xz
94296127742d786d1ea18d9624f78aed00607f7be80794fd925092832167bf31  stable-armel.tar.xz
3520306242c2d8c409719a7277f24860247274e66d469909fb4ea7c6f7abaa27  stable-armhf.tar.xz
fa93388e8e59f29875c7d9694caf5604cfbedda1916805119201f088409fe906  stable-i386.tar.xz
a81d1e5f87a93a0efa253d32800c2c7014a35a123dafd424b862d78bac1f4116  stable-ppc64el.tar.xz
2936f6872955ceb3a6b7d77dda08f2c24c81e960a9483ded5de88e9f827b5971  stable-s390x.tar.xz
afbd6ace0e812182278f7ee9b469e6190c28dc915806570308072e75ddc138c2  stable-slim-amd64.tar.xz
8bce963d1c24e90a3a099e80fb68d324eb1609f1d5643c1badaa1d3fcb15e305  stable-slim-arm64.tar.xz
7d439bbc2bd805ec2b7733e513ab8d16d0769cac2fa01b16342a4da260958e2b  stable-slim-armel.tar.xz
f2347c1eb347ed62fd0cea2789a3b4633cb0a9d4bb87e0e9a4acc10229fa4f70  stable-slim-armhf.tar.xz
74f636e5f562ad75a6afe43dae82e4c3c1401e30abb6b8d55f24927c528c0c9b  stable-slim-i386.tar.xz
de63030b67e76671f1134c3af1f737512b88757b8058eea43a386971d9b7595a  stable-slim-ppc64el.tar.xz
e57835f875c4c66ff864983690219d706cc66eb53f2bb3ab2513d0374af7eb92  stable-slim-s390x.tar.xz
79d8bd0a5d907f34c4b68c6b7877100621a42eb3d0e8fea356a0cd42a562c34e  stretch-amd64.tar.xz
deda265998673f85089e5fd96e9ea65d60f51efa991819fef9e046c2fa345c5f  stretch-arm64.tar.xz
80170505810def83b585abfc2e4d14e822c534d640eca4fe5685562eab6fd03f  stretch-armel.tar.xz
a3635e97d43b7d337bba6251555c83c5c66f589784e86a27cccb8721394bc918  stretch-armhf.tar.xz
85be864163b5939af4f880ed2f2cb5b1538de2b69e1f923674ca58741cc679e7  stretch-i386.tar.xz
20f64bcc28317e49529ebd7098a69856ebda332e038d4d9a60199a7fa5b11e65  stretch-ppc64el.tar.xz
0802caa8e5b6540f9f1ca566b60eeb0ebaadb946a61647a6aa15ef157e2ee063  stretch-s390x.tar.xz
e2b907084a2e4e2aac8e5eecacf1f4ac1ab96f5a1408d57729837292272f90e9  stretch-slim-amd64.tar.xz
944b603a22534ceab0d92894375b381b6275342b213f374c44669dc81e66623c  stretch-slim-arm64.tar.xz
65b43f2310cf3bad833ea6c65e5a3029795069b0399b368357510a71bda62c4e  stretch-slim-armel.tar.xz
770433d86f85f63ae95c657351b8f26b31873b2a3dd34367473fa50b3512f9e6  stretch-slim-armhf.tar.xz
36664b17e9b00b999f770d20b11bba1d8da9b86401cbe09a9f9c3762026d25b1  stretch-slim-i386.tar.xz
99fa77cd5da8659b6ec89ee676202f86063288f198ef940182a5a11f1bbb3e5c  stretch-slim-ppc64el.tar.xz
2e1e00875ad602102df5a20248d91245e165df0457fa8747be6e3f8bf3e37fad  stretch-slim-s390x.tar.xz
1f21a9b7c0c5cdcfb25c1570e2f434c0aaffdb29d62bae9447e44b0220a0f7e8  testing-amd64.tar.xz
ae3fe61a098ec5ba66ac299dd141fcf66f8d46299090038c69af69520076f553  testing-arm64.tar.xz
cf01c6e878b5a633427947953b7d7924f53f4ad7c4deffc1247c8ef43392d0e0  testing-armel.tar.xz
d820af2c55f159ee9a46e00af02a11c64a019c2c91e0b3500a086c6041a9642b  testing-armhf.tar.xz
8c27f142b4fe533b60ba5ef965ee10f3a1acbec58eb65694136d8a58563c8062  testing-i386.tar.xz
b58f07374773809f2511babed5415ee68d28158631276ac0d864ead6818921b1  testing-ppc64el.tar.xz
ee36282ad9265f5cce699ef7628adefdc005c5fecba2ea5f19dc304fe2ffd1ab  testing-s390x.tar.xz
7ec38730ec962c1661dc27fc0ff659d17dc6a6d877b337ba81150fd69a925ba4  testing-slim-amd64.tar.xz
0ba698c40a6ee11100fc8f626def3998e59761d276621a9f3ce34d4ff26244f7  testing-slim-arm64.tar.xz
d18348b3e0c6cb73e6f2273689c520251d40a661cdc15dec21af273e6870dc69  testing-slim-armel.tar.xz
729877ddc873bb6e3ab326da215bd7f2ac229451905168dfd1ad908b55d6cefa  testing-slim-armhf.tar.xz
4cf719f349d71dffee7830cedf617f5d95f644d927df1f416283a4e12c38a80a  testing-slim-i386.tar.xz
0d508eb136085034fbd3ed0fdfc37f6be766e4f1fa525f9d269d200a6167091b  testing-slim-ppc64el.tar.xz
b0e206a921ef41ee71a7a957c859d7fc99d472a602323f7d45cf9b7cb14d8762  testing-slim-s390x.tar.xz
015ec9e84b4349704f3348c64a70c2096a635d83617384ce8c69b0f200ce7542  unstable-amd64.tar.xz
6d8d46dc6489ecb974c6017cbe5a1b78d551eb291939ef059fa23723a6b3d4db  unstable-arm64.tar.xz
fefacd80b438501095f39fabe7c608b417b87562a88faca95ca4b340466fca02  unstable-armel.tar.xz
318ad45315eacb88d5884935a4b5294f7e86e01ed09d63afdda486e7de75b6d7  unstable-armhf.tar.xz
f0bbbabde115c7985042675be5de34d896e7b2e763836e80440829621d734b2e  unstable-i386.tar.xz
7d47d05a7da493131ca30d3f3e6e8596e895a6dc1ee84447042bcb162c6266d4  unstable-ppc64el.tar.xz
99b5ac734c9e19004b989f7ef9a3b8426b7ea3caf9f3ae3ca416032aa9efb4b3  unstable-s390x.tar.xz
6b30e9fce680107403255c5dd1676569ddfebbc4e56c86f829af25e644d8a119  unstable-slim-amd64.tar.xz
24e7ab3f180b44ddb5ae1d2c4d455571fff8fb37a468dbf07d610b7e5784e258  unstable-slim-arm64.tar.xz
3fe841cef8b8e9834c8eb36a83a33b603cfaa9c719c82b199345acec7168a063  unstable-slim-armel.tar.xz
e08ec56f9befc058c0f053c64fd2f4253b927d4bc046a9d6ecd9a86eff2a5c23  unstable-slim-armhf.tar.xz
fda6a8b866359be2d706076e2bc7d1934d5887d11eda210fa0186fd32f8353ce  unstable-slim-i386.tar.xz
6f780db05e2d2333d98aa251a89dc73663b8fd36ef97bcd207c80e93c4984fbb  unstable-slim-ppc64el.tar.xz
451dc71e260b13e5d33b6b2eb56ff647cb22637ff51e1d2a59e53c1533f70de1  unstable-slim-s390x.tar.xz
```
