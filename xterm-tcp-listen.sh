#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-

function xtcplisten () {
  cd / || return $?

  local LSN_PORT="$1"; shift

  local TERM_PROG=xterm
  local TERM_OPTS=()
  local WRAP_CMD=()
  local NET_PROG=socat
  local NET_OPTS=()

  case "$NET_PROG" in
    socat )
      NET_OPTS+=(
        -d -d -d
        TCP4-LISTEN:"$LSN_PORT",reuseaddr
        STDIO
        )
      ;;
  esac

  case "$TERM_PROG" in
    xterm )
      TERM_OPTS+=( -fs 16 )       # font-size: 12pt;
      TERM_OPTS+=( -title "$NET_PROG ${NET_OPTS[*]}" )
      TERM_OPTS+=( -geometry 140x40 )
      TERM_OPTS+=( -e )           # exec remainder. must be last.
      ;;
  esac

  local TERM_CMD=( "$TERM_PROG" "${TERM_OPTS[@]}" )
  TERM_CMD+=( "${WRAP_CMD[@]}" )
  which rlwrap | grep -qPe '^/' && TERM_CMD+=( rlwrap )
  TERM_CMD+=( "$NET_PROG" "${NET_OPTS[@]}" )
  echo ":: ${TERM_CMD[*]}"
  </dev/null setsid "${TERM_CMD[@]}" &>/dev/null &
  return 0
}








xtcplisten "$@"; exit $?
