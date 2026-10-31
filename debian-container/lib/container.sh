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
        (($# >= 2)) || dc_die '--tarball requires a file path.'
        tarball=$2
        shift 2
        ;;
      --size)
        (($# >= 2)) || dc_die '--size requires a size.'
        size=$2
        shift 2
        ;;
      --profile)
        (($# >= 2)) || dc_die '--profile requires a file path.'
        profile=$2
        shift 2
        ;;
      --help|-h)
        dc_usage
        return 0
        ;;
      *)
        dc_die 'Unknown init option: %s' "$1"
        ;;
    esac
  done

  dc_require_commands debootstrap unshare mkfs.ext4 mount chroot setpriv flock

  if [[ -n "$tarball" ]]; then
    tarball=$(readlink -f -- "$tarball")
    [[ -f "$tarball" ]] || dc_die 'Tarball not found: %s' "$tarball"
  fi
  if [[ -n "$profile" ]]; then
    profile=$(readlink -f -- "$profile")
    [[ -f "$profile" ]] || dc_die 'Profile not found: %s' "$profile"
  fi

  if [[ -e "$DC_INSTANCE_DIR" ]]; then
    dc_die 'Instance already exists: %s. Use enter to access it instead of overwriting its data.' "$DC_INSTANCE"
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
  dc_print 'Initialization complete. Run sudo bash %s enter %s to enter the container.' "$DC_SCRIPT" "$DC_INSTANCE"
}

dc_resize() {
  local size=

  while (($# > 0)); do
    case "$1" in
      --size)
        (($# >= 2)) || dc_die '--size requires a size.'
        size=$2
        shift 2
        ;;
      --help|-h)
        dc_usage
        return 0
        ;;
      *)
        dc_die 'Unknown resize option: %s' "$1"
        ;;
    esac
  done

  [[ -n "$size" ]] || dc_die 'resize requires --size.'
  [[ -f "$DC_IMAGE" ]] || dc_die 'Image not found; run init first.'
  dc_resize_image "$size"
  dc_print 'Instance resized: %s, new size: %s' "$DC_INSTANCE" "$size"
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
  local manifest=
  local temporary_root
  local -a debootstrap_options=(--variant=minbase)

  while (($# > 0)); do
    case "$1" in
      --output)
        (($# >= 2)) || dc_die '--output requires a file path.'
        output=$2
        shift 2
        ;;
      --manifest)
        (($# >= 2)) || dc_die '--manifest requires a file path.'
        manifest=$2
        shift 2
        ;;
      --suite)
        (($# >= 2)) || dc_die '--suite requires a release name.'
        suite=$2
        shift 2
        ;;
      --arch)
        (($# >= 2)) || dc_die '--arch requires an architecture name.'
        arch=$2
        shift 2
        ;;
      --mirror)
        (($# >= 2)) || dc_die '--mirror requires a mirror URL.'
        mirror=$2
        shift 2
        ;;
      --include)
        (($# >= 2)) || dc_die '--include requires a package list.'
        include=$2
        shift 2
        ;;
      --exclude)
        (($# >= 2)) || dc_die '--exclude requires a package list.'
        exclude=$2
        shift 2
        ;;
      --help|-h)
        dc_usage
        return 0
        ;;
      *)
        dc_die 'Unknown base-create option: %s' "$1"
        ;;
    esac
  done

  output=$(readlink -m -- "$output")
  if [[ -z "$manifest" ]]; then
    manifest="$output.manifest"
  else
    manifest=$(readlink -m -- "$manifest")
  fi
  [[ "$manifest" != "$output" ]] || dc_die 'Manifest cannot overwrite the tarball.'
  [[ ! -e "$output" ]] || dc_die 'Tarball already exists: %s' "$output"
  [[ ! -e "$manifest" ]] || dc_die 'Manifest already exists: %s' "$manifest"

  dc_require_commands awk date debootstrap mktemp readlink sha256sum
  mkdir -p "$(dirname -- "$output")"
  mkdir -p "$(dirname -- "$manifest")"
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

  dc_manifest_write "$manifest" "$output" "$suite" "${arch:-native}" "$mirror" "$include" "$exclude"
  dc_print 'Base tarball created: %s' "$output"
  dc_print 'Manifest created: %s' "$manifest"
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
        (($# >= 2)) || dc_die '--network requires a mode.'
        network_mode=$2
        shift 2
        ;;
      --mount)
        (($# >= 2)) || dc_die '--mount requires a mount specification.'
        dc_bind_add "$2"
        shift 2
        ;;
      --help|-h)
        dc_usage
        return 0
        ;;
      *)
        dc_die 'Unknown enter option: %s' "$1"
        ;;
    esac
  done

  [[ -f "$DC_IMAGE" ]] || dc_die 'Image not found; run init first.'
  dc_network_prepare "$network_mode"
  for spec in "${DC_BIND_SPECS[@]}"; do
    bind_args+=(--mount "$spec")
  done

  if [[ "$network_mode" == nat ]]; then
    dc_network_nat_run _enter "${bind_args[@]}"
    return
  fi

  unshare --mount --uts --ipc --pid --fork --propagation private \
    "${DC_NETWORK_UNSHARE_ARGS[@]}" -- bash "$DC_SCRIPT" _enter "$DC_INSTANCE" "${bind_args[@]}"
}

dc_enter_rootfs() {
  dc_bind_load_options "$@"
  dc_mount_root
  trap dc_cleanup_mounts EXIT
  dc_network_configure_rootfs
  dc_mount_virtual_filesystems
  dc_bind_mount_all
  hostname debian-container
  dc_print 'Entered the isolated Debian environment; type exit to leave the container.'

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
        (($# >= 2)) || dc_die '--network requires a mode.'
        network_mode=$2
        shift 2
        ;;
      --mount)
        (($# >= 2)) || dc_die '--mount requires a mount specification.'
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
        dc_die 'Usage: exec NAME [--network MODE] -- command [arguments...]'
        ;;
    esac
  done

  (($# > 0)) || dc_die 'exec requires a command.'
  [[ -f "$DC_IMAGE" ]] || dc_die 'Image not found; run init first.'
  dc_network_prepare "$network_mode"
  for spec in "${DC_BIND_SPECS[@]}"; do
    bind_args+=(--mount "$spec")
  done

  if [[ "$network_mode" == nat ]]; then
    dc_network_nat_run _exec "${bind_args[@]}" -- "$@"
    return
  fi

  unshare --mount --uts --ipc --pid --fork --propagation private \
    "${DC_NETWORK_UNSHARE_ARGS[@]}" -- \
    bash "$DC_SCRIPT" _exec "$DC_INSTANCE" "${bind_args[@]}" -- "$@"
}

dc_exec_rootfs() {
  local -a command_args=()

  while (($# > 0)); do
    case "$1" in
      --mount)
        (($# >= 2)) || dc_die '--mount requires a mount specification.'
        dc_bind_add "$2"
        shift 2
        ;;
      --)
        shift
        command_args=("$@")
        break
        ;;
      *)
        dc_die 'Invalid exec child-process arguments.'
        ;;
    esac
  done

  (($# > 0)) || dc_die 'exec requires a command.'
  dc_mount_root
  trap dc_cleanup_mounts EXIT
  dc_network_configure_rootfs
  dc_mount_virtual_filesystems
  dc_bind_mount_all
  hostname debian-container

  setpriv --bounding-set=-sys_admin,-net_admin,-net_raw,-sys_module,-sys_boot,-sys_time,-sys_rawio,-sys_ptrace,-syslog -- \
    chroot "$DC_ROOT" "${command_args[@]}"
}

dc_status() {
  local spec

  dc_profile_load
  dc_print 'Instance: %s' "$DC_INSTANCE"
  dc_print 'Directory: %s' "$DC_INSTANCE_DIR"
  dc_print 'Network: %s' "$DC_PROFILE_NETWORK"
  for spec in "${DC_BIND_SPECS[@]}"; do
    dc_print 'Mount: %s' "$spec"
  done
  if [[ -f "$DC_IMAGE" ]]; then
    dc_print 'Image: exists'
  fi
  dc_status_image
}

dc_delete() {
  [[ -d "$DC_INSTANCE_DIR" ]] || { dc_print 'The Debian instance no longer exists.'; return 0; }
  dc_require_commands findmnt
  if findmnt --mountpoint "$DC_ROOT" >/dev/null 2>&1; then
    dc_die 'The instance is still mounted: %s' "$DC_INSTANCE"
  fi
  rm -rf -- "$DC_INSTANCE_DIR"
  dc_print 'Debian instance deleted: %s' "$DC_INSTANCE"
}

