#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 by Richard Qin

DC_NETWORK_MODE=${DEBIAN_NETWORK:-none}
DC_NETWORK_UNSHARE_ARGS=()
DC_NAT_BRIDGE=${DEBIAN_NAT_BRIDGE:-rutils0}
DC_NAT_NETWORK=${DEBIAN_NAT_NETWORK:-10.88.0.0/24}
DC_NAT_PREFIX=${DC_NAT_NETWORK#*/}
DC_NAT_GATEWAY=${DEBIAN_NAT_GATEWAY:-10.88.0.1}
DC_NAT_ADDRESS=${DEBIAN_NAT_ADDRESS:-10.88.0.2}
DC_NAT_DNS=${DEBIAN_NAT_DNS:-1.1.1.1}

dc_network_prepare() {
  local mode=${1:-$DC_NETWORK_MODE}

  case "$mode" in
    none)
      DC_NETWORK_UNSHARE_ARGS=(--net)
      ;;
    host)
      DC_NETWORK_UNSHARE_ARGS=()
      ;;
    nat)
      DC_NETWORK_UNSHARE_ARGS=(--net)
      ;;
    *)
      dc_die 'Invalid network mode: %s (choose none, host, or nat)' "$mode"
      ;;
  esac
}

dc_network_configure_rootfs() {
  [[ "$DC_NETWORK_MODE" == nat ]] || return 0
  rm -f "$DC_ROOT/etc/resolv.conf"
  printf 'nameserver %s\n' "$DC_NAT_DNS" > "$DC_ROOT/etc/resolv.conf"
}

dc_network_nat_setup_firewall() {
  dc_require_commands grep nft sysctl

  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  if ! nft list table ip rutils_nat >/dev/null 2>&1; then
    nft add table ip rutils_nat
  fi
  if ! nft list chain ip rutils_nat postrouting >/dev/null 2>&1; then
    nft 'add chain ip rutils_nat postrouting { type nat hook postrouting priority 100; policy accept; }'
  fi
  if ! nft list chain ip rutils_nat postrouting | grep -Fq "ip saddr $DC_NAT_NETWORK"; then
    nft add rule ip rutils_nat postrouting ip saddr "$DC_NAT_NETWORK" oifname != "$DC_NAT_BRIDGE" masquerade
  fi
}

dc_network_nat_setup() {
  local netns=$1
  local host_interface=$2
  local guest_interface=$3

  dc_require_commands grep ip
  if ! ip link show "$DC_NAT_BRIDGE" >/dev/null 2>&1; then
    ip link add "$DC_NAT_BRIDGE" type bridge
  fi
  ip link set "$DC_NAT_BRIDGE" up
  if ! ip -4 addr show dev "$DC_NAT_BRIDGE" | grep -Fq "inet $DC_NAT_GATEWAY/"; then
    ip addr add "$DC_NAT_GATEWAY/$DC_NAT_PREFIX" dev "$DC_NAT_BRIDGE"
  fi

  ip netns add "$netns"
  ip link add "$host_interface" type veth peer name "$guest_interface"
  ip link set "$guest_interface" netns "$netns"
  ip link set "$host_interface" master "$DC_NAT_BRIDGE"
  ip link set "$host_interface" up

  ip netns exec "$netns" ip link set lo up
  ip netns exec "$netns" ip link set "$guest_interface" name eth0
  ip netns exec "$netns" ip addr add "$DC_NAT_ADDRESS/$DC_NAT_PREFIX" dev eth0
  ip netns exec "$netns" ip link set eth0 up
  ip netns exec "$netns" ip route add default via "$DC_NAT_GATEWAY"
  dc_network_nat_setup_firewall
}

dc_network_nat_cleanup() {
  local netns=$1
  local host_interface=$2

  ip link delete "$host_interface" 2>/dev/null || true
  ip netns delete "$netns" 2>/dev/null || true
}

dc_network_nat_run() {
  local child_action=$1
  local netns="rutils-${DC_INSTANCE}-$$"
  local host_interface="rvh$$"
  local guest_interface="rvg$$"

  shift
  trap "dc_network_nat_cleanup '$netns' '$host_interface'" EXIT
  dc_network_nat_setup "$netns" "$host_interface" "$guest_interface"
  env DEBIAN_NETWORK=nat ip netns exec "$netns" \
    unshare --mount --uts --ipc --pid --fork --propagation private -- \
    bash "$DC_SCRIPT" "$child_action" "$DC_INSTANCE" "$@"
}

dc_network_nat_namespaces() {
  ip netns list | awk '$1 ~ /^rutils-/ { print $1 }'
}

dc_network_status() {
  local namespace
  local link

  dc_require_commands awk ip nft
  dc_print 'Bridge: %s' "$DC_NAT_BRIDGE"
  if ip link show "$DC_NAT_BRIDGE" >/dev/null 2>&1; then
    ip -brief addr show dev "$DC_NAT_BRIDGE"
  else
    dc_print 'Status: does not exist'
  fi

  dc_print 'Network namespaces:'
  while read -r namespace; do
    [[ -n "$namespace" ]] || continue
    dc_print '  %s' "$namespace"
    ip netns pids "$namespace" | awk '{ print "    pid: " $0 }'
  done < <(dc_network_nat_namespaces)

  dc_print 'Veth interfaces:'
  while read -r link; do
    [[ -n "$link" ]] || continue
    dc_print '  %s' "$link"
  done < <(ip -o link show | awk -F': ' '$2 ~ /^rvh[0-9]+@/ { sub(/@.*/, "", $2); print $2 }')

  dc_print 'nftables:'
  if nft list table ip rutils_nat >/dev/null 2>&1; then
    nft list table ip rutils_nat
  else
    dc_print '  rutils_nat does not exist'
  fi
}

dc_network_clean() {
  local namespace
  local link
  local active=0

  dc_require_commands awk ip nft
  while read -r namespace; do
    [[ -n "$namespace" ]] || continue
    if [[ -n "$(ip netns pids "$namespace")" ]]; then
      dc_print 'Keeping active namespace: %s' "$namespace"
      active=1
    else
      ip netns delete "$namespace"
      dc_print 'Deleted namespace: %s' "$namespace"
    fi
  done < <(dc_network_nat_namespaces)

  if ((active == 0)); then
    while read -r link; do
      [[ -n "$link" ]] || continue
      ip link delete "$link" 2>/dev/null || true
      dc_print 'Deleted veth: %s' "$link"
    done < <(ip -o link show | awk -F': ' '$2 ~ /^rvh[0-9]+@/ { sub(/@.*/, "", $2); print $2 }')

    nft delete table ip rutils_nat 2>/dev/null || true
    if ip link show "$DC_NAT_BRIDGE" >/dev/null 2>&1; then
      ip link set "$DC_NAT_BRIDGE" down
      ip link delete "$DC_NAT_BRIDGE" type bridge
    fi
    dc_print 'NAT bridge and nftables rules cleaned.'
  else
    dc_print 'Active namespaces exist; keeping veth interfaces.'
    dc_print 'Active namespaces exist; keeping NAT bridge and nftables rules.'
  fi
}
