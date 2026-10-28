#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 by Richard Qin

dc_init() {
  local tarball=
  local size=$DC_SIZE
  local profile=

  while (($# > 0)); do
    case "$1" in
      --tarball)
        (($# >= 2)) || dc_die '--tarball 需要一个文件路径。'
        tarball=$2
        shift 2
        ;;
      --size)
        (($# >= 2)) || dc_die '--size 需要一个大小。'
        size=$2
        shift 2
        ;;
      --profile)
        (($# >= 2)) || dc_die '--profile 需要一个文件路径。'
        profile=$2
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
  if [[ -n "$profile" ]]; then
    profile=$(readlink -f -- "$profile")
    [[ -f "$profile" ]] || dc_die "找不到 profile：$profile"
  fi

  if [[ -e "$DC_INSTANCE_DIR" ]]; then
    dc_die "实例已存在：$DC_INSTANCE。请使用 enter 进入，避免覆盖容器数据。"
  fi

  dc_create_image "$size"
  if [[ -n "$tarball" ]]; then
    unshare --mount --propagation private -- bash "$DC_SCRIPT" _init "$DC_INSTANCE" "$tarball"
  else
    unshare --mount --propagation private -- bash "$DC_SCRIPT" _init "$DC_INSTANCE"
  fi
  DC_PROFILE_FILE="$DC_INSTANCE_DIR/config"
  if [[ -n "$profile" ]]; then
    cp -- "$profile" "$DC_PROFILE_FILE"
  else
    dc_profile_write_default "$DC_NETWORK_MODE"
  fi
  echo "初始化完成。执行 sudo bash $DC_SCRIPT enter $DC_INSTANCE 进入容器。"
}

dc_resize() {
  local size=

  while (($# > 0)); do
    case "$1" in
      --size)
        (($# >= 2)) || dc_die '--size 需要一个大小。'
        size=$2
        shift 2
        ;;
      --help|-h)
        dc_usage
        return 0
        ;;
      *)
        dc_die "未知的 resize 选项：$1"
        ;;
    esac
  done

  [[ -n "$size" ]] || dc_die 'resize 必须指定 --size。'
  [[ -f "$DC_IMAGE" ]] || dc_die '没有找到镜像，请先运行 init。'
  dc_resize_image "$size"
  echo "实例已扩容：$DC_INSTANCE，新的大小为 $size"
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
  local output=$DC_TARBALL
  local suite=$DC_SUITE
  local arch=$DC_ARCH
  local mirror=$DC_MIRROR
  local include=$DC_INCLUDE
  local exclude=$DC_EXCLUDE
  local temporary_root
  local -a debootstrap_options=(--variant=minbase)

  while (($# > 0)); do
    case "$1" in
      --output)
        (($# >= 2)) || dc_die '--output 需要一个文件路径。'
        output=$2
        shift 2
        ;;
      --suite)
        (($# >= 2)) || dc_die '--suite 需要一个版本名称。'
        suite=$2
        shift 2
        ;;
      --arch)
        (($# >= 2)) || dc_die '--arch 需要一个架构名称。'
        arch=$2
        shift 2
        ;;
      --mirror)
        (($# >= 2)) || dc_die '--mirror 需要一个镜像地址。'
        mirror=$2
        shift 2
        ;;
      --include)
        (($# >= 2)) || dc_die '--include 需要软件包列表。'
        include=$2
        shift 2
        ;;
      --exclude)
        (($# >= 2)) || dc_die '--exclude 需要软件包列表。'
        exclude=$2
        shift 2
        ;;
      --help|-h)
        dc_usage
        return 0
        ;;
      *)
        dc_die "未知的 base-create 选项：$1"
        ;;
    esac
  done

  output=$(readlink -m -- "$output")
  [[ ! -e "$output" ]] || dc_die "tarball 已存在：$output"

  dc_require_commands debootstrap mktemp readlink
  mkdir -p "$(dirname -- "$output")"
  temporary_root=$(mktemp -d)

  [[ -n "$arch" ]] && debootstrap_options+=("--arch=$arch")
  [[ -n "$include" ]] && debootstrap_options+=("--include=$include")
  [[ -n "$exclude" ]] && debootstrap_options+=("--exclude=$exclude")

  (
    trap 'rm -rf -- "$temporary_root"' EXIT
    debootstrap \
      "${debootstrap_options[@]}" \
      --make-tarball="$output" \
      "$suite" "$temporary_root" "$mirror"
  )

  echo "基础 tarball 已创建：$output"
}

dc_enter() {
  local network_mode=$DC_NETWORK_MODE
  local -a bind_args=()
  local spec

  dc_profile_load
  network_mode=$DC_PROFILE_NETWORK

  while (($# > 0)); do
    case "$1" in
      --network)
        (($# >= 2)) || dc_die '--network 需要一个模式。'
        network_mode=$2
        shift 2
        ;;
      --mount)
        (($# >= 2)) || dc_die '--mount 需要一个挂载参数。'
        dc_bind_add "$2"
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
  for spec in "${DC_BIND_SPECS[@]}"; do
    bind_args+=(--mount "$spec")
  done

  unshare --mount --uts --ipc --pid --fork --propagation private \
    "${DC_NETWORK_UNSHARE_ARGS[@]}" -- bash "$DC_SCRIPT" _enter "$DC_INSTANCE" "${bind_args[@]}"
}

dc_enter_rootfs() {
  dc_bind_load_options "$@"
  dc_mount_root
  trap dc_cleanup_mounts EXIT
  dc_mount_virtual_filesystems
  dc_bind_mount_all
  hostname debian-container
  echo '已进入独立的 Debian 实验环境；输入 exit 可退出容器。'

  # 完成挂载后撤销一些宿主级危险权限，保留 CAP_LINUX_IMMUTABLE。
  setpriv --bounding-set=-sys_admin,-net_admin,-net_raw,-sys_module,-sys_boot,-sys_time,-sys_rawio,-sys_ptrace,-syslog -- \
    chroot "$DC_ROOT" /bin/bash -l
}

dc_exec() {
  local network_mode=$DC_NETWORK_MODE
  local -a bind_args=()
  local spec

  dc_profile_load
  network_mode=$DC_PROFILE_NETWORK

  while (($# > 0)); do
    case "$1" in
      --network)
        (($# >= 2)) || dc_die '--network 需要一个模式。'
        network_mode=$2
        shift 2
        ;;
      --mount)
        (($# >= 2)) || dc_die '--mount 需要一个挂载参数。'
        dc_bind_add "$2"
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
  for spec in "${DC_BIND_SPECS[@]}"; do
    bind_args+=(--mount "$spec")
  done

  unshare --mount --uts --ipc --pid --fork --propagation private \
    "${DC_NETWORK_UNSHARE_ARGS[@]}" -- \
    bash "$DC_SCRIPT" _exec "$DC_INSTANCE" "${bind_args[@]}" -- "$@"
}

dc_exec_rootfs() {
  local -a command_args=()

  while (($# > 0)); do
    case "$1" in
      --mount)
        (($# >= 2)) || dc_die '--mount 需要一个挂载参数。'
        dc_bind_add "$2"
        shift 2
        ;;
      --)
        shift
        command_args=("$@")
        break
        ;;
      *)
        dc_die 'exec 子进程参数格式无效。'
        ;;
    esac
  done

  (($# > 0)) || dc_die 'exec 需要一个命令。'
  dc_mount_root
  trap dc_cleanup_mounts EXIT
  dc_mount_virtual_filesystems
  dc_bind_mount_all
  hostname debian-container

  setpriv --bounding-set=-sys_admin,-net_admin,-net_raw,-sys_module,-sys_boot,-sys_time,-sys_rawio,-sys_ptrace,-syslog -- \
    chroot "$DC_ROOT" "${command_args[@]}"
}

dc_status() {
  local spec

  dc_profile_load
  echo "实例：$DC_INSTANCE"
  echo "目录：$DC_INSTANCE_DIR"
  echo "网络：$DC_PROFILE_NETWORK"
  for spec in "${DC_BIND_SPECS[@]}"; do
    echo "挂载：$spec"
  done
  if [[ -f "$DC_IMAGE" ]]; then
    echo '镜像：存在'
  fi
  dc_status_image
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

