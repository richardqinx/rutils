#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 by Richard Qin

# Keep runtime data in the directory from which the tool is invoked for now.
# These variables can be overridden by the environment without changing the
# command interface.
DC_IMAGE=${DEBIAN_IMAGE:-"$PWD/rootfs.ext4"}
DC_ROOT=${DEBIAN_ROOT:-"$PWD/debian-root"}
DC_LOCK_FILE=${DEBIAN_LOCK_FILE:-/run/lock/debian-container.lock}
DC_TARBALL=${DEBIAN_TARBALL:-"$PWD/debian-base.tar.gz"}
DC_SUITE=${DEBIAN_SUITE:-stable}
DC_MIRROR=${DEBIAN_MIRROR:-http://deb.debian.org/debian}
DC_INCLUDE=${DEBIAN_INCLUDE:-passwd,util-linux,vim-tiny,e2fsprogs}

