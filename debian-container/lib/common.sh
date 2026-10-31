#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 by Richard Qin

TEXTDOMAIN=debian-container
TEXTDOMAINDIR="$DC_DIR/locale"
export TEXTDOMAIN TEXTDOMAINDIR

dc_gettext() {
  gettext "$1"
}

dc_print() {
  local format

  format=$(dc_gettext "$1")
  shift
  if (($# == 0)); then
    printf '%s\n' "$format"
  else
    printf "$format\n" "$@"
  fi
}

dc_die() {
  local format

  format=$(dc_gettext "$1")
  shift
  if (($# == 0)); then
    printf '%s\n' "$format" >&2
  else
    printf "$format\n" "$@" >&2
  fi
  exit 1
}

dc_require_root() {
  [[ ${EUID} -eq 0 ]] || dc_die 'Please run this script with sudo.'
}

dc_require_commands() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null || dc_die 'Required command is missing: %s' "$tool"
  done
}

dc_acquire_lock() {
  mkdir -p "$(dirname -- "$DC_LOCK_FILE")"
  exec 9>"$DC_LOCK_FILE"
  flock -n 9 || dc_die 'The Debian container is already running or being initialized.'
}

dc_select_instance() {
  local name=$1

  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || dc_die 'Invalid instance name: %s' "$name"
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
  printf "$(gettext 'Usage: sudo bash %s <command>\n\nCommands:\n  base-create [OPTIONS]  Download once and create a debootstrap package tarball\n  base-info TAR           Show the manifest of a base tarball\n  network-status          Show NAT network resources\n  network-clean           Clean NAT network resources\n  init NAME [OPTIONS]     Create a container image\n  enter NAME [OPTIONS]    Enter a container\n  exec NAME [OPTIONS]     Execute a command in a container\n  resize NAME [OPTIONS]   Resize a container image\n  status NAME             Show container status\n  list                    List all containers\n  delete NAME             Delete a container\n\ninit options:\n  --tarball PATH          Initialize from a local tarball\n  --size SIZE             Image size (default: 3G)\n  --profile PATH          Copy an instance profile\n\nresize options:\n  --size SIZE             New image size; it can only be increased\n\nbase-create options:\n  --output PATH           Output tarball path\n  --manifest PATH         Manifest path (default: TARBALL.manifest)\n  --suite SUITE           Debian release\n  --arch ARCH             Target architecture\n  --mirror URL            Debian mirror URL\n  --include PACKAGES      Packages to include, comma-separated\n  --exclude PACKAGES      Packages to exclude, comma-separated\n\nnetwork options:\n  --network MODE          Network mode: none (default), host, or nat\n\nmount options:\n  --mount SPEC            Mount specification: HOST:CONTAINER[:ro|rw]\n\nprofile options:\n  network=MODE\n  mount=HOST:CONTAINER[:ro|rw]\n\nenvironment variables:\n  DEBIAN_INSTANCES  Instance directory (default: current directory/instances)\n  DEBIAN_SIZE       Image size (default: 3G)\n  DEBIAN_LOCK_FILE  Lock file (default: /run/lock/debian-container.lock)\n  DEBIAN_TARBALL    Base tarball (default: current directory/debian-base.tar.gz)\n  DEBIAN_SUITE      Debian release (default: stable)\n  DEBIAN_ARCH       Target architecture\n  DEBIAN_MIRROR     Debian mirror URL\n  DEBIAN_INCLUDE    Additional packages, comma-separated\n  DEBIAN_EXCLUDE    Packages to exclude, comma-separated\n  DEBIAN_NETWORK    Default network mode (default: none)\n  DEBIAN_NAT_BRIDGE NAT bridge name (default: rutils0)\n  DEBIAN_NAT_NETWORK NAT subnet (default: 10.88.0.0/24)\n  DEBIAN_NAT_GATEWAY NAT gateway address (default: 10.88.0.1)\n  DEBIAN_NAT_ADDRESS Container address (default: 10.88.0.2)\n  DEBIAN_NAT_DNS     NAT mode DNS server (default: 1.1.1.1)\n')" \
    "$DC_SCRIPT" "$DC_SCRIPT" "$DC_SCRIPT" "$DC_SCRIPT"
}
