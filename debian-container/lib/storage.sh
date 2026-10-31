#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 by Richard Qin

dc_create_image() {
  local size=$1

  mkdir -p "$DC_INSTANCE_DIR" "$DC_ROOT"
  truncate -s "$size" "$DC_IMAGE"
  mkfs.ext4 -F -q -L DEBIAN_CONTAINER "$DC_IMAGE"
}

dc_resize_image() {
  local size=$1
  local current_size
  local target_size
  local allocated_blocks
  local block_size

  dc_require_commands e2fsck findmnt numfmt resize2fs stat truncate
  if findmnt --mountpoint "$DC_ROOT" >/dev/null 2>&1; then
    dc_die 'The instance is still mounted: %s' "$DC_INSTANCE"
  fi

  current_size=$(stat -c '%s' "$DC_IMAGE")
  target_size=$(numfmt --from=iec "$size")
  ((target_size > current_size)) || dc_die 'The new image size must be greater than the current size: %s bytes' "$current_size"

  truncate -s "$size" "$DC_IMAGE"
  if e2fsck -f -y "$DC_IMAGE"; then
    :
  else
    [[ $? -eq 1 ]] || dc_die 'Filesystem check failed: %s' "$DC_IMAGE"
  fi
  resize2fs "$DC_IMAGE"
}

dc_status_image() {
  local allocated_blocks
  local block_size

  if [[ -f "$DC_IMAGE" ]]; then
    allocated_blocks=$(stat -c '%b' "$DC_IMAGE")
    block_size=$(stat -c '%B' "$DC_IMAGE")
    dc_print 'Logical size: %s bytes' "$(stat -c '%s' "$DC_IMAGE")"
    dc_print 'Actual usage: %s bytes' "$((allocated_blocks * block_size))"
  else
    dc_print 'Image: does not exist'
  fi
}
