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
  base-create [选项]  下载一次并创建 debootstrap 软件包 tarball
  base-info TAR      查看基础 tarball 的 manifest
  network-status     查看 NAT 网络资源
  network-clean      清理 NAT 残留资源
  init NAME [选项]    创建指定名称的容器镜像
  enter NAME [选项]   进入指定容器
  exec NAME [选项]    在指定容器中执行命令
  resize NAME [选项]  扩大指定容器的镜像
  status NAME         查看指定容器状态
  list                列出所有容器
  delete NAME         删除指定容器

init 选项：
  --tarball PATH      从本地 tarball 初始化，跳过软件包下载
  --size SIZE         镜像大小（默认：3G）
  --profile PATH      复制实例 profile

resize 选项：
  --size SIZE         新的镜像大小，只能扩大

base-create 选项：
  --output PATH       输出 tarball 路径
  --manifest PATH     manifest 路径（默认：TARBALL.manifest）
  --suite SUITE       Debian 版本
  --arch ARCH         目标架构
  --mirror URL        Debian 镜像地址
  --include PACKAGES  要加入的软件包，使用逗号分隔
  --exclude PACKAGES  要排除的软件包，使用逗号分隔

网络选项：
  --network MODE      网络模式：none（默认）、host 或 nat

挂载选项：
  --mount SPEC        目录挂载：HOST:CONTAINER[:ro|rw]

profile 配置项：
  network=MODE
  mount=HOST:CONTAINER[:ro|rw]

环境变量：
  DEBIAN_INSTANCES  实例目录（默认：当前目录/instances）
  DEBIAN_SIZE       新实例镜像大小（默认：3G）
  DEBIAN_LOCK_FILE  锁文件路径（默认：/run/lock/debian-container.lock）
  DEBIAN_TARBALL    基础 tarball（默认：当前目录/debian-base.tar.gz）
  DEBIAN_SUITE      Debian 版本（默认：stable）
  DEBIAN_ARCH       目标架构
  DEBIAN_MIRROR     Debian 镜像地址
  DEBIAN_INCLUDE    额外软件包，使用逗号分隔
  DEBIAN_EXCLUDE    要排除的软件包，使用逗号分隔
  DEBIAN_NETWORK    默认网络模式（默认：none）
  DEBIAN_NAT_BRIDGE NAT 网桥名称（默认：rutils0）
  DEBIAN_NAT_NETWORK NAT 子网（默认：10.88.0.0/24）
  DEBIAN_NAT_GATEWAY NAT 网关地址（默认：10.88.0.1）
  DEBIAN_NAT_ADDRESS 容器地址（默认：10.88.0.2）
  DEBIAN_NAT_DNS    NAT 模式 DNS（默认：1.1.1.1）
EOF
}

