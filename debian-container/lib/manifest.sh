#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 by Richard Qin

dc_manifest_write() {
  local manifest=$1
  local tarball=$2
  local suite=$3
  local arch=$4
  local mirror=$5
  local include=$6
  local exclude=$7
  local checksum

  checksum=$(sha256sum "$tarball" | awk '{print $1}')
  {
    printf 'format=debootstrap-package-tarball\n'
    printf 'tarball=%s\n' "$tarball"
    printf 'suite=%s\n' "$suite"
    printf 'arch=%s\n' "$arch"
    printf 'mirror=%s\n' "$mirror"
    printf 'include=%s\n' "$include"
    printf 'exclude=%s\n' "$exclude"
    printf 'created_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'sha256=%s\n' "$checksum"
  } > "$manifest"
}

dc_manifest_info() {
  local input=${1:-}
  local manifest
  local tarball
  local expected
  local actual

  (($# == 1)) || dc_die 'Usage: base-info TARBALL'
  dc_require_commands awk sha256sum

  if [[ "$input" == *.manifest ]]; then
    manifest=$input
    tarball=${input%.manifest}
  else
    manifest="$input.manifest"
    tarball=$input
  fi
  [[ -f "$manifest" ]] || dc_die 'Manifest not found: %s' "$manifest"

  cat "$manifest"
  expected=$(awk -F= '$1 == "sha256" { print $2 }' "$manifest")
  if [[ -f "$tarball" && -n "$expected" ]]; then
    actual=$(sha256sum "$tarball" | awk '{print $1}')
    if [[ "$actual" == "$expected" ]]; then
      dc_print 'checksum=match'
    else
      dc_print 'checksum=mismatch'
    fi
  fi
}
