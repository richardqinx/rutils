#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 by Richard Qin

dc_cleanup_mounts() {
  umount "$DC_ROOT/dev/pts" 2>/dev/null || true
  umount "$DC_ROOT/dev" 2>/dev/null || true
  umount "$DC_ROOT/proc" 2>/dev/null || true
  umount "$DC_ROOT" 2>/dev/null || true
}

dc_mount_root() {
  mkdir -p "$DC_ROOT"
  mount -o loop "$DC_IMAGE" "$DC_ROOT"
  mkdir -p "$DC_ROOT/proc" "$DC_ROOT/dev"
}

dc_mount_virtual_filesystems() {
  mount -t proc -o ro,nosuid,nodev,noexec proc "$DC_ROOT/proc"
  mount -t tmpfs -o mode=0755,nosuid tmpfs "$DC_ROOT/dev"
  mknod -m 0666 "$DC_ROOT/dev/null" c 1 3
  mknod -m 0666 "$DC_ROOT/dev/zero" c 1 5
  mknod -m 0666 "$DC_ROOT/dev/random" c 1 8
  mknod -m 0666 "$DC_ROOT/dev/urandom" c 1 9
  mknod -m 0666 "$DC_ROOT/dev/tty" c 5 0
  mkdir -p "$DC_ROOT/dev/pts"
  mount -t devpts -o newinstance,ptmxmode=0666,mode=0620 devpts "$DC_ROOT/dev/pts"
  ln -s pts/ptmx "$DC_ROOT/dev/ptmx"
}

