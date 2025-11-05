#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function ssh_mount_url () {
  # local SELFPATH="$(readlink -m "$0"/..)"
  local SSH_TIMEOUT_OPTS=(
    -o ServerAliveCountMax=2,ServerAliveInterval=20
    -o ConnectionAttempts=1,ConnectTimeout=30
    )
  case "$1" in
    --impatient )
      SSH_TIMEOUT_OPTS=(
        -o ServerAliveCountMax=2,ServerAliveInterval=5
        -o ConnectionAttempts=1,ConnectTimeout=5
        )
      shift;;
  esac

  local M_URL="$1"; shift
  local M_PNT="$1"; shift
  local M_PATH=

  case "$M_URL" in
    pmb:*/* | \
    __split_path__ ) M_PATH="${M_URL#*/}"; M_URL="${M_URL%%/*}";;
  esac
  case "$M_URL" in
    pmb:* )
      M_URL="${M_URL#*:}" # keep just the username
      [ -n "$M_PNT" ] || M_PNT="mkdir:$HOME/net/$M_URL@pmb"
      M_URL="ssh://$M_URL@ssh.pimpmybyte.de/$M_PATH"
      ;;
  esac

  case "$M_URL" in
    'ssh://'* ) M_URL="${M_URL#*://}";;
    * ) return 4$(echo 'E: unsupported protocol in URL' >&2);;
  esac

  case "$M_PNT" in
    mkdir:* )
      M_PNT="${M_PNT#*:}"
      mkdir --parents -- "$M_PNT" || return $?
      ;;
  esac

  M_PATH=
  case "$M_URL" in
    */* )
      M_PATH="${M_URL#*/}"
      M_URL="${M_URL%%/*}"
      ;;
  esac
  M_PATH="${M_PATH%/}/"
  local M_OPTS=(
    -o reconnect
    "${SSH_TIMEOUT_OPTS[@]}"
    -o idmap=user
    -o follow_symlinks
    -o ssh_command=ssh-nopw

    # -o umask=0133 # ATTN: 2025-10-04, Ubuntu focal, not-a-bug:
    #     When option umask is set, it is applied as if the remote
    #     permissions were 0777, regardless of what the file system
    #     on the remote host says. The sshfs man page describes the
    #     "umask" option as "set file permissions", not "adjust" or
    #     "restrict" or "partially clear".
    #     There is no separate option for directories because on sshfs
    #     with umask, you can chdir into non-executable directories.

    )

  if [[ "$M_URL" =~ :([0-9]+)$ ]]; then
    M_OPTS+=( -p "${BASH_REMATCH[1]}" )
    M_URL="${M_URL%:*}"
  fi

  case "$M_PATH" in
    '~/'* ) M_PATH="${M_PATH#\~/}";;
    '/'* ) ;;
    * ) M_PATH="/$M_PATH";;
  esac
  M_URL+=":$M_PATH"

  case "$M_PNT" in
    /* ) ;;
    * ) M_PNT="$PWD/$M_PNT";;
  esac
  cd / || return $?   # avoid locking the orig cwd

  local M_CMD=( sshfs "$M_URL" "$M_PNT" "${M_OPTS[@]}" )
  [ "${DEBUGLEVEL:-0}" -gt 5 ] && echo "${M_CMD[*]} $*"
  exec "${M_CMD[@]}" "$@"
  return 8$(echo 'E: failed to exec sshfs' >&2)
}








ssh_mount_url "$@"; exit $?
