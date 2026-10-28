#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 by Richard Qin

# Debian 构建容器
set -Eeuo pipefail

DC_SCRIPT=$(readlink -f -- "${BASH_SOURCE[0]}")
DC_DIR=$(dirname -- "$DC_SCRIPT")

source "$DC_DIR/lib/config.sh"
source "$DC_DIR/lib/common.sh"
source "$DC_DIR/lib/mount.sh"
source "$DC_DIR/lib/container.sh"

DC_ACTION=${1:-}

case "$DC_ACTION" in
  help|-h|--help)
    dc_usage
    exit 0
    ;;
esac

dc_require_root

case "$DC_ACTION" in
  init|enter|delete)
    # 防止多个会话同时读写同一 ext4 镜像。
    dc_acquire_lock
    ;;
esac

case "$DC_ACTION" in
  init)    dc_init ;;
  _init)   dc_init_rootfs ;;
  enter)   dc_enter ;;
  _enter)  dc_enter_rootfs ;;
  delete)  dc_delete ;;
  *)
    dc_usage >&2
    exit 2
    ;;
esac
