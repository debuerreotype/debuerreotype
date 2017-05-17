# Debian in Docker (reproducible snapshot-based builds)

This is based on [lamby](https://github.com/lamby)'s work for reproducible `debootstrap`:

- https://github.com/lamby/debootstrap/commit/66b15380814aa62ca4b5807270ac57a3c8a0558d
- https://wiki.debian.org/ReproducibleInstalls

## Why?

The goal is to create an auditable, reproducible process for creating rootfs tarballs (especially for use in Docker) of Debian releases, based on point-in-time snapshots from [snapshot.debian.org](http://snapshot.debian.org).
