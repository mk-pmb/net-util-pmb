#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function ssh_env_args () {
  local SSH_CMD=( ssh )
  [ -n "$SSH_OPTS" ] && SSH_CMD+=( $SSH_OPTS )

  local AGENT_VARS=
  local AGENT_TIMEOUT=10
  if [ -n "$SSH_PRIVKEY" ]; then
    AGENT_VARS="$(ssh-agent -t $AGENT_TIMEOUT -s 2>&1 | tr ';' '\n' \
      | sed -nre 's!^SSH_[A-Z_]+=[a-zA-Z0-9\./-]+$!export &;!p')"
    eval "$AGENT_VARS"
    LANG=C ssh-add "$SSH_PRIVKEY" 2>&1 | grep -vPe '^Identity added: '
    local ADD_RV=${PIPESTATUS[0]}
    unset SSH_PRIVKEY
    ( sleep $AGENT_TIMEOUT; kill -HUP "$SSH_AGENT_PID" &>/dev/null ) &
    [ $ADD_RV == 0 ] || return $ADD_RV
  fi

  local MUX_DIR="$SSH_MUX_DIR"

  case "$(basename "$0")" in
    ssh-nopw | \
    batch-ssh )
      SSH_CMD+=(
        -o NumberOfPasswordPrompts=0
        -o BatchMode=yes
        )
      [ -n "$MUX_DIR" ] || MUX_DIR=-
      # ^-- require explicit MUX_DIR to reduce risk of overbooked master
      #     connections and/or keeping a pipe open waiting idle because
      #     a new master connection process was spawned, inheriting our
      #     stderr and keeping that alive.
      ;;
  esac

  case "$MUX_DIR" in
    '~'/* ) MUX_DIR="$HOME${MUX_DIR:1}";;
  esac
  case "$MUX_DIR" in
    '' ) ;;
    - ) SSH_CMD+=( -o ControlMaster=no );;
    * )
      mkdir --parents -- "$MUX_DIR" || return $?
      SSH_CMD+=(
        -o ControlMaster=auto
        -o ControlPath="$MUX_DIR"/%u.%r@%n.%p
        )
      ;;
  esac

  exec "${SSH_CMD[@]}" "$@"
  echo "E: exec ssh failed!" >&2
  return 4
}


ssh_env_args "$@"; exit $?
