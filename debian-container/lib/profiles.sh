#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 by Richard Qin

DC_PROFILE_FILE=
DC_PROFILE_NETWORK=

dc_profile_parse() {
  local file=$1
  local line
  local key
  local value

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] || dc_die 'Invalid profile configuration: %s' "$line"
    key=${line%%=*}
    value=${line#*=}
    case "$key" in
      network)
        DC_PROFILE_NETWORK=$value
        ;;
      mount)
        dc_bind_add "$value"
        ;;
      *)
        dc_die 'Invalid profile option: %s' "$key"
        ;;
    esac
  done < "$file"
}

dc_profile_load() {
  DC_BIND_SPECS=()
  DC_BIND_SOURCES=()
  DC_BIND_TARGETS=()
  DC_BIND_MODES=()
  DC_PROFILE_FILE="$DC_INSTANCE_DIR/config"
  DC_PROFILE_NETWORK=$DC_NETWORK_MODE

  if [[ -f "$DC_PROFILE_FILE" ]]; then
    dc_profile_parse "$DC_PROFILE_FILE"
  fi
}

dc_profile_write_default() {
  local network_mode=$1

  printf 'network=%s\n' "$network_mode" > "$DC_PROFILE_FILE"
}
