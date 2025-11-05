#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function wifi_lost_renm () {
  has_any_unblocked_wifi_adapters || return 0
  guess_wifi_connected && return 0

  local GXCLS="${FUNCNAME//_/-}"

  SECONDS=-3
  local CTD_OPTS=(
    --time "${WIFI_LOSS_RENM_DELAY:-2min}"
    --mutex class:close-previous-finished --class "$GXCLS" --title "$GXCLS"
    )
  if [ -n "$DEBUG_OVR_IWC" ]; then
    CTD_OPTS+=( --msg "DEBUG_OVR_IWC=$DEBUG_OVR_IWC" )
  else
    CTD_OPTS+=(
      --msg 'We seem to have lost wifi. Gonna reconnect…'
      --execute sudo service network-manager restart
      )
  fi
  gxctd "${CTD_OPTS[@]}" &
  local CTD_PID=$!
  sleep 0.5s
  while true; do
    kill -0 "$CTD_PID" &>/dev/null || break
    if guess_wifi_connected; then
      disown "$CTD_PID"
      kill -HUP "$CTD_PID" &>/dev/null && return 0
    fi
    sleep 1s
  done
  wait "$CTD_PID"
  local CTD_RV=$?
  if [ "$CTD_RV" != 0 ]; then
    if [ "$SECONDS" -lt 0 ]; then
      echo "I: $FUNCNAME: probably counting down already"
      return 0
    fi
  fi
  return "$CTD_RV"
}


function has_any_unblocked_wifi_adapters () {
  rfkill-list-tsv --unblocked wifi | grep -qe . -m 1; return $?
}


function guess_wifi_connected () {
  [ -n "$DEBUG_OVR_IWC" ] && return "$DEBUG_OVR_IWC"
  LANG=C iwconfig 2>/dev/null | grep -qPie '^\s+link '
}













wifi_lost_renm "$@"; exit $?
