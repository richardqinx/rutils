#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 by Richard Qin

DC_BIND_SPECS=()
DC_BIND_SOURCES=()
DC_BIND_TARGETS=()
DC_BIND_MODES=()

dc_bind_add() {
  local spec=$1
  local source
  local target
  local mode
  local extra

  IFS=: read -r source target mode extra <<< "$spec"
  [[ -n "$source" && -n "$target" && -z "$extra" ]] || dc_die 'Invalid mount specification: %s' "$spec"
  [[ "$source" = /* && "$target" = /* ]] || dc_die 'Mount source and target must be absolute paths: %s' "$spec"
  [[ "$target" != "/" ]] || dc_die 'A directory cannot be mounted at the container root.'

  mode=${mode:-rw}
  [[ "$mode" == rw || "$mode" == ro ]] || dc_die 'Invalid mount mode: %s' "$mode"
  source=$(readlink -f -- "$source")
  [[ -d "$source" ]] || dc_die 'Mount source is not a directory: %s' "$source"
  target=$(readlink -m -- "$target")
  [[ "$target" != "/" ]] || dc_die 'A directory cannot be mounted at the container root.'

  DC_BIND_SPECS+=("$source:$target:$mode")
  DC_BIND_SOURCES+=("$source")
  DC_BIND_TARGETS+=("$target")
  DC_BIND_MODES+=("$mode")
}

dc_bind_load_options() {
  while (($# > 0)); do
    [[ "$1" == --mount ]] || dc_die 'Invalid mount option.'
    (($# >= 2)) || dc_die '--mount requires a mount specification.'
    dc_bind_add "$2"
    shift 2
  done
}

dc_bind_mount_all() {
  local index
  local target

  for index in "${!DC_BIND_SPECS[@]}"; do
    target="$DC_ROOT${DC_BIND_TARGETS[index]}"
    mkdir -p "$target"
    mount --bind "${DC_BIND_SOURCES[index]}" "$target"
    if [[ "${DC_BIND_MODES[index]}" == ro ]]; then
      mount -o remount,bind,ro "$target"
    fi
  done
}

dc_bind_cleanup() {
  local index

  for ((index = ${#DC_BIND_TARGETS[@]} - 1; index >= 0; index--)); do
    umount "$DC_ROOT${DC_BIND_TARGETS[index]}" 2>/dev/null || true
  done
}
