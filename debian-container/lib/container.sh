#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 by Richard Qin

dc_init() {
  local tarball=

  while (($# > 0)); do
    case "$1" in
      --tarball)
        (($# >= 2)) || dc_die '--tarball 需要一个文件路径。'
        tarball=$2
        shift 2
        ;;
      --help|-h)
        dc_usage
        return 0
        ;;
      *)
        dc_die "未知的 init 选项：$1"
        ;;
    esac
  done

  dc_require_commands debootstrap unshare mkfs.ext4 mount chroot setpriv flock

  if [[ -n "$tarball" ]]; then
    tarball=$(readlink -f -- "$tarball")
    [[ -f "$tarball" ]] || dc_die "找不到 tarball：$tarball"
  fi

  if [[ -e "$DC_INSTANCE_DIR" ]]; then
    dc_die "实例已存在：$DC_INSTANCE。请使用 enter 进入，避免覆盖容器数据。"
  fi

  mkdir -p "$DC_INSTANCE_DIR" "$DC_ROOT"
  truncate -s 3G "$DC_IMAGE"
  mkfs.ext4 -F -q -L DEBIAN_CONTAINER "$DC_IMAGE"
  if [[ -n "$tarball" ]]; then
    unshare --mount --propagation private -- bash "$DC_SCRIPT" _init "$DC_INSTANCE" "$tarball"
  else
    unshare --mount --propagation private -- bash "$DC_SCRIPT" _init "$DC_INSTANCE"
  fi
  echo "初始化完成。执行 sudo bash $DC_SCRIPT enter $DC_INSTANCE 进入容器。"
}

dc_init_rootfs() {
  local tarball=${1:-}
  local -a include_packages=()

  dc_mount_root
  trap dc_cleanup_mounts EXIT

  if [[ -n "$tarball" ]]; then
    debootstrap \
      --variant=minbase \
      --unpack-tarball="$tarball" \
      "$DC_SUITE" "$DC_ROOT" "$DC_MIRROR"
  else
    debootstrap \
      --variant=minbase \
      "$DC_SUITE" "$DC_ROOT" "$DC_MIRROR"
  fi

  rm -f "$DC_ROOT/etc/resolv.conf"
  cp -L /etc/resolv.conf "$DC_ROOT/etc/resolv.conf"
  dc_mount_virtual_filesystems

  if [[ -z "$tarball" ]]; then
    IFS=, read -r -a include_packages <<< "$DC_INCLUDE"
    chroot "$DC_ROOT" /usr/bin/env DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get update
    chroot "$DC_ROOT" /usr/bin/env DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get install -y "${include_packages[@]}"
  fi

  echo debian-container > "$DC_ROOT/etc/hostname"
}

dc_base_create() {
  local output=${1:-$DC_TARBALL}
  local temporary_root

  (($# <= 1)) || dc_die '用法：base-create [tarball 路径]'
  output=$(readlink -m -- "$output")
  [[ ! -e "$output" ]] || dc_die "tarball 已存在：$output"

  dc_require_commands debootstrap mktemp readlink
  mkdir -p "$(dirname -- "$output")"
  temporary_root=$(mktemp -d)

  (
    trap 'rm -rf -- "$temporary_root"' EXIT
    debootstrap \
      --variant=minbase \
      --include="$DC_INCLUDE" \
      --make-tarball="$output" \
      "$DC_SUITE" "$temporary_root" "$DC_MIRROR"
  )

  echo "基础 tarball 已创建：$output"
}

dc_enter() {
  local network_mode=$DC_NETWORK_MODE

  while (($# > 0)); do
    case "$1" in
      --network)
        (($# >= 2)) || dc_die '--network 需要一个模式。'
        network_mode=$2
        shift 2
        ;;
      --help|-h)
        dc_usage
        return 0
        ;;
      *)
        dc_die "未知的 enter 选项：$1"
        ;;
    esac
  done

  [[ -f "$DC_IMAGE" ]] || dc_die '没有找到镜像，请先运行 init。'
  dc_network_prepare "$network_mode"

  unshare --mount --uts --ipc --pid --fork --propagation private \
    "${DC_NETWORK_UNSHARE_ARGS[@]}" -- bash "$DC_SCRIPT" _enter "$DC_INSTANCE"
}

dc_enter_rootfs() {
  dc_mount_root
  trap dc_cleanup_mounts EXIT
  dc_mount_virtual_filesystems
  hostname debian-container
  echo '已进入独立的 Debian 实验环境；输入 exit 可退出容器。'

  # 完成挂载后撤销一些宿主级危险权限，保留 CAP_LINUX_IMMUTABLE。
  setpriv --bounding-set=-sys_admin,-net_admin,-net_raw,-sys_module,-sys_boot,-sys_time,-sys_rawio,-sys_ptrace,-syslog -- \
    chroot "$DC_ROOT" /bin/bash -l
}

dc_exec() {
  local network_mode=$DC_NETWORK_MODE

  while (($# > 0)); do
    case "$1" in
      --network)
        (($# >= 2)) || dc_die '--network 需要一个模式。'
        network_mode=$2
        shift 2
        ;;
      --)
        shift
        break
        ;;
      --help|-h)
        dc_usage
        return 0
        ;;
      *)
        dc_die '用法：exec NAME [--network MODE] -- 命令 [参数...]'
        ;;
    esac
  done

  (($# > 0)) || dc_die 'exec 需要一个命令。'
  [[ -f "$DC_IMAGE" ]] || dc_die '没有找到镜像，请先运行 init。'
  dc_network_prepare "$network_mode"

  unshare --mount --uts --ipc --pid --fork --propagation private \
    "${DC_NETWORK_UNSHARE_ARGS[@]}" -- \
    bash "$DC_SCRIPT" _exec "$DC_INSTANCE" "$@"
}

dc_exec_rootfs() {
  dc_mount_root
  trap dc_cleanup_mounts EXIT
  dc_mount_virtual_filesystems
  hostname debian-container

  setpriv --bounding-set=-sys_admin,-net_admin,-net_raw,-sys_module,-sys_boot,-sys_time,-sys_rawio,-sys_ptrace,-syslog -- \
    chroot "$DC_ROOT" "$@"
}

dc_status() {
  echo "实例：$DC_INSTANCE"
  echo "目录：$DC_INSTANCE_DIR"
  if [[ -f "$DC_IMAGE" ]]; then
    echo '镜像：存在'
  else
    echo '镜像：不存在'
  fi
}

dc_delete() {
  [[ -d "$DC_INSTANCE_DIR" ]] || { echo 'Debian 实例已不存在。'; return 0; }
  dc_require_commands findmnt
  if findmnt --mountpoint "$DC_ROOT" >/dev/null 2>&1; then
    dc_die "实例仍处于挂载状态：$DC_INSTANCE"
  fi
  rm -rf -- "$DC_INSTANCE_DIR"
  echo "Debian 实例已删除：$DC_INSTANCE"
}

