#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 by Richard Qin

# Debian 构建容器
set -Eeuo pipefail

DC_SCRIPT=$(readlink -f -- "${BASH_SOURCE[0]}")
DC_DIR=$(dirname -- "$DC_SCRIPT")

source "$DC_DIR/lib/config.sh"
source "$DC_DIR/lib/common.sh"
source "$DC_DIR/lib/network.sh"
source "$DC_DIR/lib/storage.sh"
source "$DC_DIR/lib/mount.sh"
source "$DC_DIR/lib/binds.sh"
source "$DC_DIR/lib/profiles.sh"
source "$DC_DIR/lib/manifest.sh"
source "$DC_DIR/lib/container.sh"

DC_ACTION=${1:-}
shift || true

case "$DC_ACTION" in
  help|-h|--help)
    dc_usage
    exit 0
    ;;
esac

dc_require_root

case "$DC_ACTION" in
  base-create|init|enter|exec|resize|delete)
    # 防止多个会话同时读写同一 ext4 镜像。
    dc_acquire_lock
    ;;
esac

case "$DC_ACTION" in
  init|enter|exec|resize|status|delete)
    (($# > 0)) || dc_die "$DC_ACTION 需要实例名称。"
    dc_select_instance "$1"
    shift
    ;;
  _init|_enter|_exec)
    (($# > 0)) || dc_die "$DC_ACTION 需要实例名称。"
    dc_select_instance "$1"
    shift
    ;;
esac

case "$DC_ACTION" in
  base-create) dc_base_create "$@" ;;
  base-info)   dc_manifest_info "$@" ;;
  init)    dc_init "$@" ;;
  _init)   dc_init_rootfs "$@" ;;
  enter)   dc_enter "$@" ;;
  _enter)  dc_enter_rootfs "$@" ;;
  exec)    dc_exec "$@" ;;
  _exec)   dc_exec_rootfs "$@" ;;
  resize)  dc_resize "$@" ;;
  status)  dc_status ;;
  list)    dc_list ;;
  delete)  dc_delete ;;
  *)
    dc_usage >&2
    exit 2
    ;;
esac
