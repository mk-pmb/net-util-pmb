#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function ftpmount () {
  local DBGLV="${DEBUGLEVEL:-0}"
  local -A CFG=()
  local POS_ARGN=( ftp-url mountpoint )
  local POS_ARGS=()
  local OPT=
  CFG[ftp-user]=anonymous
  CFG[password]='opera@'
  CFG[uid]="$(id --user)"
  CFG[gid]="$(id --group)"
  CFG[charset]=utf8
  MOUNT_OPTS='nonempty'
  while [ "$#" -ge 1 ]; do
    OPT="$1"; shift
    case "$OPT" in
      '' ) ;;
      -- ) POS_ARGS+=( "$@" ); break;;
      -o ) MOUNT_OPTS+=",$1"; shift;;
      --verbose | -v ) CFG[verbose]='--verbose';;
      --anycert ) MOUNT_OPTS+=',no_verify_peer';;
      --no-verify-peer )
        OPT="${OPT#--}"
        OPT="${OPT//-/_}"
        MOUNT_OPTS+=",$OPT";;
      --*=* )
        OPT="${OPT#--}"
        CFG["${OPT%%=*}"]="${OPT#*=}";;
      -* ) return 1$(echo "E: $0: unsupported option: $OPT" >&2);;
      * )
        case "${POS_ARGN[0]}" in
          '' ) return 1$(echo "E: $0: unexpected positional argument." >&2);;
          '+' ) POS_ARGS+=( "$OPT" );;
          * ) CFG["${POS_ARGN[0]}"]="$OPT"; POS_ARGN=( "${POS_ARGN[@]:1}" );;
        esac;;
    esac
  done

  case "${CFG[mountpoint]}" in
    */* ) ;;
    * ) CFG[mountpoint]="$HOME/net/${CFG[mountpoint]}";;
  esac

  mkdir --parents -- "${CFG[mountpoint]}" || return $?

  case "${CFG[charset]}" in
    utf8 ) MOUNT_OPTS+=",${CFG[charset]}";;
  esac
  MOUNT_OPTS+=",iocharset=${CFG[charset]}"

  local CREDS='^([a-z0-9]+://)([^/]+)@'
  if [[ "${CFG[ftp-url]}" =~ $CREDS ]]; then
    CFG[ftp-url]="${BASH_REMATCH[1]}${CFG[ftp-url]:${#BASH_REMATCH[0]}}"
    CREDS="${BASH_REMATCH[2]}"
    CFG[ftp-user]="${CREDS%%:*}"
    CFG[password]=
    case "$CREDS" in
      *:* ) CFG[password]="${CREDS#*:}";;
    esac
  fi

  case "${CFG[ftp-url]}" in
    ftps://* )
      CFG[ftp-url]="ftp:${CFG[ftp-url]#*:}"
      MOUNT_OPTS+=',ssl,sslv3,tlsv1'
      ;;
  esac

  [ "$DBGLV" -gt 8 ] && local -p | sed -nre '/^CFG=/{
    s~^~D: ~
    s~" \[~"\nD:\t[~g
    # s~((\t|=\()\[password\]=)"[^"]+"~\1…~
    p}' >&2
  local FTPFS_MOUNTS=()
  readarray -t FTPFS_MOUNTS < <(LANG=C mount | sed -nre '
    s~curlftpfs#.* on (/.*) type fuse \([^\(\)]+\)$~\1~p')
  # maybe soon: check whether destination mountpoint is already mounted

  MOUNT_OPTS+=",uid=${CFG[uid]},gid=${CFG[gid]}"
  MOUNT_OPTS+=",user=${CFG[ftp-user]//,/\\,}:${CFG[password]//,/\\,}"
  local MOUNT_CMD=( curlftpfs )
  [ -n "${CFG[verbose]}" ] && MOUNT_CMD+=( "${CFG[verbose]}" )
  MOUNT_CMD+=( "${CFG[ftp-url]}" "${CFG[mountpoint]}" -o "$MOUNT_OPTS" )
  [ "$DBGLV" -gt 4 ] && echo "D: cmd: ${MOUNT_CMD[*]}" >&2
  "${MOUNT_CMD[@]}" && return 0
  local RV=$?
  ( echo -n W: $FUNCNAME "failed (rv=$RV)"
    [ -n "${CFG[verbose]}" ] || echo -n ';  try --verbose maybe?'
  ) >&2
  esac
  return $RV
}


ftpmount "$@"; exit $?
