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
    dc_die "实例仍处于挂载状态：$DC_INSTANCE"
  fi

  current_size=$(stat -c '%s' "$DC_IMAGE")
  target_size=$(numfmt --from=iec "$size")
  ((target_size > current_size)) || dc_die "扩容大小必须大于当前镜像大小：$current_size bytes"

  truncate -s "$size" "$DC_IMAGE"
  if e2fsck -f -y "$DC_IMAGE"; then
    :
  else
    [[ $? -eq 1 ]] || dc_die "文件系统检查失败：$DC_IMAGE"
  fi
  resize2fs "$DC_IMAGE"
}

dc_status_image() {
  local allocated_blocks
  local block_size

  if [[ -f "$DC_IMAGE" ]]; then
    allocated_blocks=$(stat -c '%b' "$DC_IMAGE")
    block_size=$(stat -c '%B' "$DC_IMAGE")
    echo "逻辑大小：$(stat -c '%s' "$DC_IMAGE") bytes"
    echo "实际占用：$((allocated_blocks * block_size)) bytes"
  else
    echo '镜像：不存在'
  fi
}
