#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-

function ip_dgw_iface () {
  export LANG=C
  local KEY= VAL='
    s~^(via|dev)$~\nDR_\U&\E~;
    /^\n/N;
    s~^\n(\S+)\n([A-Za-z0-9_\.\-]+)$~\1=\2~p
    '
  VAL="${VAL//[$'\n ']/}"
  local $(ip route show default | LANG=C tr ' \t' '\n' |
    LANG=C sed -nre "$VAL")

  [ -n "$DR_VIA" ] || return 4$(
    echo E: 'Failed to detect default IPv4 gateway IP address!' >&2)
  echo NET_DEFAULT_GATEWAY="'$DR_VIA'"
  [ -n "$DR_DEV" ] || return 4$(
    echo E: 'Failed to detect default IPv4 interface name!' >&2)
  echo NET_DEFAULT_IFACE_NAME="'$DR_DEV'"

  VAL="$(ip addr show "$DR_DEV" | tr -s '\t ' ' ' |
    grep -m 1 -oPe ' inet(?= )([\. ]\d+){4}(?=/| )')"
  VAL="${VAL# * }"
  [ -n "$VAL" ] || return 4$(
    echo E: 'Failed to detect default IPv4 IP address!' >&2)
  echo NET_DEFAULT_IFACE_IPV4="'$VAL'"

  VAL="$(ip addr show "$DR_DEV" | tr -s '\t ' ' ' |
    grep -m 1 -oPe ' inet6 [0-9a-f:]+(?=/| )')"
  VAL="${VAL# * }"
  [ -n "$VAL" ] || return 4$(
    echo E: 'Failed to detect default IPv6 IP address!' >&2)
  echo NET_DEFAULT_IFACE_IPV6="'$VAL'"
}

ip_dgw_iface "$@"; exit $?
