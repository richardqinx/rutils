#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 by Richard Qin

DC_NETWORK_MODE=${DEBIAN_NETWORK:-none}
DC_NETWORK_UNSHARE_ARGS=()

dc_network_prepare() {
  local mode=${1:-$DC_NETWORK_MODE}

  case "$mode" in
    none)
      DC_NETWORK_UNSHARE_ARGS=(--net)
      ;;
    host)
      DC_NETWORK_UNSHARE_ARGS=()
      ;;
    *)
      dc_die "网络模式无效：$mode（可选：none、host）"
      ;;
  esac
}
