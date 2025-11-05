#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-

function ssh_retry_stubbornly () {
  local SSH_LOGIN="$1"; shift
  case "$SSH_LOGIN" in
    [a-z]* | *@* ) ;;
    * ) echo "E: expected arg1 to be of format 'user@host'" >&2; return 2;;
  esac

  local PID_FN="$HOME/.cache/var/run/${FUNCNAME//_/-}"
  mkdir --parents -- "$PID_FN" || return $?
  PID_FN+="/$SSH_LOGIN.$$.pid"
  >"$PID_FN" || return $?
  echo "D: using pidfile $PID_FN"
  local NOW=
  while [ -f "$PID_FN" ]; do
    printf -v NOW '%(%T)T'
    echo "$NOW" >"$PID_FN"
    printf '%s\t%s %s\n' "$$" "$NOW" "$SSH_LOGIN $*"
    ssh "$SSH_LOGIN" "$@" && return 0
    sleep "${SSH_RETRY_DELAY:-0.5s}" || return $?
  done
  return 0
}

ssh_retry_stubbornly "$@"; exit $?
