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
  base-create [路径]  下载一次并创建 debootstrap 软件包 tarball
  init [选项]         创建 Debian 容器镜像
  enter               进入容器
  delete              删除容器镜像

init 选项：
  --tarball PATH      从本地 tarball 初始化，跳过软件包下载

环境变量：
  DEBIAN_IMAGE      镜像路径（默认：当前目录/rootfs.ext4）
  DEBIAN_ROOT       挂载目录（默认：当前目录/debian-root）
  DEBIAN_LOCK_FILE  锁文件路径
  DEBIAN_TARBALL    基础 tarball（默认：当前目录/debian-base.tar.gz）
  DEBIAN_SUITE      Debian 版本（默认：stable）
  DEBIAN_MIRROR     Debian 镜像地址
  DEBIAN_INCLUDE    额外软件包，使用逗号分隔
EOF
}

