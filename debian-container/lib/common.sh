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

dc_select_instance() {
  local name=$1

  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || dc_die "实例名称无效：$name"
  DC_INSTANCE=$name
  DC_INSTANCE_DIR="$DC_INSTANCES/$DC_INSTANCE"
  DC_IMAGE="$DC_INSTANCE_DIR/rootfs.ext4"
  DC_ROOT="$DC_INSTANCE_DIR/root"
}

dc_list() {
  local path

  [[ -d "$DC_INSTANCES" ]] || return 0
  for path in "$DC_INSTANCES"/*; do
    [[ -d "$path" ]] || continue
    basename -- "$path"
  done
}

dc_usage() {
  cat <<EOF
用法：sudo bash $DC_SCRIPT <命令>

命令：
  base-create [路径]  下载一次并创建 debootstrap 软件包 tarball
  init NAME [选项]    创建指定名称的容器镜像
  enter NAME          进入指定容器
  exec NAME -- CMD    在指定容器中执行命令
  status NAME         查看指定容器状态
  list                列出所有容器
  delete NAME         删除指定容器

init 选项：
  --tarball PATH      从本地 tarball 初始化，跳过软件包下载

环境变量：
  DEBIAN_INSTANCES  实例目录（默认：当前目录/instances）
  DEBIAN_LOCK_FILE  锁文件路径（默认：/run/lock/debian-container.lock）
  DEBIAN_TARBALL    基础 tarball（默认：当前目录/debian-base.tar.gz）
  DEBIAN_SUITE      Debian 版本（默认：stable）
  DEBIAN_MIRROR     Debian 镜像地址
  DEBIAN_INCLUDE    额外软件包，使用逗号分隔
EOF
}

