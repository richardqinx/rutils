#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 by Richard Qin

# Keep instance data in the directory from which the tool is invoked for now.
DC_INSTANCES=${DEBIAN_INSTANCES:-"$PWD/instances"}
DC_LOCK_FILE=${DEBIAN_LOCK_FILE:-/run/lock/debian-container.lock}
DC_TARBALL=${DEBIAN_TARBALL:-"$PWD/debian-base.tar.gz"}
DC_SUITE=${DEBIAN_SUITE:-stable}
DC_ARCH=${DEBIAN_ARCH:-}
DC_MIRROR=${DEBIAN_MIRROR:-http://deb.debian.org/debian}
DC_INCLUDE=${DEBIAN_INCLUDE:-passwd,util-linux,vim-tiny,e2fsprogs}
DC_EXCLUDE=${DEBIAN_EXCLUDE:-}

DC_INSTANCE=
DC_INSTANCE_DIR=
DC_IMAGE=
DC_ROOT=

