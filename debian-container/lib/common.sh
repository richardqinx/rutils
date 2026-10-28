#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 by Richard Qin

dc_die() {
  echo "$*" >&2
  exit 1
}

dc_require_root() {
  [[ ${EUID} -eq 0 ]] || dc_die '请使用 sudo 执行此脚本。'
}

dc_require_commands() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null || dc_die "缺少工具：$tool"
  done
}

dc_acquire_lock() {
  mkdir -p "$(dirname -- "$DC_LOCK_FILE")"
  exec 9>"$DC_LOCK_FILE"
  flock -n 9 || dc_die 'Debian 容器已经在运行或正在初始化。'
}

dc_usage() {
  cat <<EOF
用法：sudo bash $DC_SCRIPT <命令>

命令：
  init      创建 Debian 容器镜像
  enter     进入容器
  delete    删除容器镜像

环境变量：
  DEBIAN_IMAGE      镜像路径（默认：当前目录/rootfs.ext4）
  DEBIAN_ROOT       挂载目录（默认：当前目录/debian-root）
  DEBIAN_LOCK_FILE  锁文件路径
EOF
}

