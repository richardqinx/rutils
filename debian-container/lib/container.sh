#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 by Richard Qin

dc_init() {
  dc_require_commands debootstrap unshare mkfs.ext4 mount chroot setpriv flock

  if [[ -e "$DC_IMAGE" ]]; then
    dc_die "镜像已存在：$DC_IMAGE。请使用 enter 进入，避免覆盖容器数据。"
  fi

  mkdir -p "$(dirname -- "$DC_IMAGE")" "$DC_ROOT"
  truncate -s 3G "$DC_IMAGE"
  mkfs.ext4 -F -q -L DEBIAN_CONTAINER "$DC_IMAGE"
  unshare --mount --propagation private -- bash "$DC_SCRIPT" _init
  echo "初始化完成。执行 sudo bash $DC_SCRIPT enter 进入容器。"
}

dc_init_rootfs() {
  dc_mount_root
  trap dc_cleanup_mounts EXIT

  debootstrap --variant=minbase stable "$DC_ROOT" http://deb.debian.org/debian
  rm -f "$DC_ROOT/etc/resolv.conf"
  cp -L /etc/resolv.conf "$DC_ROOT/etc/resolv.conf"
  dc_mount_virtual_filesystems
  chroot "$DC_ROOT" /usr/bin/env DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get update
  chroot "$DC_ROOT" /usr/bin/env DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get install -y passwd util-linux vim-tiny e2fsprogs
  echo debian-container > "$DC_ROOT/etc/hostname"
}

dc_enter() {
  [[ -f "$DC_IMAGE" ]] || dc_die '没有找到镜像，请先运行 init。'

  # 单独创建网络命名空间，暂时没有联网功能。
  unshare --mount --uts --ipc --pid --net --fork --propagation private -- bash "$DC_SCRIPT" _enter
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

dc_delete() {
  [[ -f "$DC_IMAGE" ]] || { echo 'Debian 镜像已不存在。'; return 0; }
  rm -- "$DC_IMAGE"
  echo 'Debian 镜像已删除。'
}

