# Debian in Docker (reproducible snapshot-based builds)

This is based on [lamby](https://github.com/lamby)'s work for reproducible `debootstrap`:

- https://github.com/lamby/debootstrap/commit/66b15380814aa62ca4b5807270ac57a3c8a0558d
- https://wiki.debian.org/ReproducibleInstalls

## Why?

The goal is to create an auditable, reproducible process for creating rootfs tarballs (especially for use in Docker) of Debian releases, based on point-in-time snapshots from [snapshot.debian.org](http://snapshot.debian.org).

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
