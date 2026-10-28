#!/usr/bin/env bash
# Debian 构建容器
set -Eeuo pipefail

SCRIPT=$(readlink -f -- "${BASH_SOURCE[0]}")
IMAGE=$PWD/rootfs.ext4
ROOT=$PWD/debian-root/
ACTION=${1:-}

if [[ ${EUID} -ne 0 ]]; then
  echo '请使用 sudo 执行本脚本。' >&2
  exit 1
fi

cleanup_mounts() {
  umount "$ROOT/dev/pts" 2>/dev/null || true
  umount "$ROOT/dev" 2>/dev/null || true
  umount "$ROOT/proc" 2>/dev/null || true
  umount "$ROOT" 2>/dev/null || true
}

mount_root() {
  mkdir -p "$ROOT"
  mount -o loop "$IMAGE" "$ROOT"
  mkdir -p "$ROOT/proc" "$ROOT/dev"
}

mount_virtual_filesystems() {
  mount -t proc -o ro,nosuid,nodev,noexec proc "$ROOT/proc"
  mount -t tmpfs -o mode=0755,nosuid tmpfs "$ROOT/dev"
  mknod -m 0666 "$ROOT/dev/null" c 1 3
  mknod -m 0666 "$ROOT/dev/zero" c 1 5
  mknod -m 0666 "$ROOT/dev/random" c 1 8
  mknod -m 0666 "$ROOT/dev/urandom" c 1 9
  mknod -m 0666 "$ROOT/dev/tty" c 5 0
  mkdir -p "$ROOT/dev/pts"
  mount -t devpts -o newinstance,ptmxmode=0666,mode=0620 devpts "$ROOT/dev/pts"
  ln -s pts/ptmx "$ROOT/dev/ptmx"
}

# 防止多个会话同时读写同一 ext4 镜像。
case "$ACTION" in
  init|enter|delete)
    mkdir -p /run/lock
    exec 9>/run/lock/debian-container.lock
    flock -n 9 || { echo 'Debian 容器已经在运行或正在初始化。' >&2; exit 1; }
    ;;
esac

case "$ACTION" in
  init)
    for tool in debootstrap unshare mkfs.ext4 mount chroot setpriv flock; do
      command -v "$tool" >/dev/null || { echo "缺少工具：$tool" >&2; exit 1; }
    done
    if [[ -e "$IMAGE" ]]; then
      echo "镜像已存在：$IMAGE。请使用 enter 进入，避免覆盖容器数据。" >&2
      exit 1
    fi
    mkdir -p "$(dirname "$IMAGE")" "$ROOT"
    truncate -s 3G "$IMAGE"
    mkfs.ext4 -F -q -L DEBIAN_CONTAINER "$IMAGE"
    unshare --mount --propagation private -- bash "$SCRIPT" _init
    echo '初始化完成。执行 sudo bash debian-container.sh enter 进入容器。'
    ;;
  _init)
    mount_root
    trap cleanup_mounts EXIT
    debootstrap --variant=minbase stable "$ROOT" http://deb.debian.org/debian
    rm -f "$ROOT/etc/resolv.conf"
    cp -L /etc/resolv.conf "$ROOT/etc/resolv.conf"
    mount_virtual_filesystems
    chroot "$ROOT" /usr/bin/env DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get update
    chroot "$ROOT" /usr/bin/env DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get install -y passwd util-linux vim-tiny e2fsprogs
    echo debian-container > "$ROOT/etc/hostname"
    ;;
  enter)
    [[ -f "$IMAGE" ]] || { echo '没有找到镜像，请先运行 init。' >&2; exit 1; }
    # 单独创建网络命名空间，暂时没有联网功能。
    unshare --mount --uts --ipc --pid --net --fork --propagation private -- bash "$SCRIPT" _enter
    ;;
  _enter)
    mount_root
    trap cleanup_mounts EXIT
    mount_virtual_filesystems
    hostname debian-container
    echo '已进入独立的 Debian 实验环境；输入 exit 可退出。'
    # 完成挂载后撤销一些宿主级危险权限，保留 CAP_LINUX_IMMUTABLE。
    setpriv --bounding-set=-sys_admin,-net_admin,-net_raw,-sys_module,-sys_boot,-sys_time,-sys_rawio,-sys_ptrace,-syslog -- \
      chroot "$ROOT" /bin/bash -l
    ;;
  delete)
    [[ -f "$IMAGE" ]] || { echo 'Debian 镜像已不存在。'; exit 0; }
    rm -- "$IMAGE"
    echo 'Debian 镜像已删除。'
    ;;
  *)
    echo "用法：sudo bash $0 init|enter|delete" >&2
    exit 2
    ;;
esac
