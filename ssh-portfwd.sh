#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function ssh_portfwd () {
  local SSH_BASE_ARGS=(
    -2  # SSH proto v2 only
    -a  # disable auth agent
    -k  # disable forwarding of GSSAPI credentials
    -N  # no command to execute
    -T  # no pseudo-tty required
    -x  # no X forwarding
    )
  cd / || return $?

  case "$1" in
    *@* ) SSH_BASE_ARGS+=( "$1" ); shift;;
  esac
  local OPT="$1"
  case "$OPT" in
    -L ) ;; # open listen port on Local (SSH client) side
    -R ) ;; # open listen port on Remote (SSH server) side
    * )
      echo "E: $(readlink -m "$BASH_SOURCE"): stub:" \
        "will pass verbatim args if the first one" \
        "(after a potential user@host) is -L or -R." >&2
      return 2;;
  esac
  exec ssh "${SSH_BASE_ARGS[@]}" "$@" || return $?
}





ssh_portfwd "$@"; exit $?
