#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function tcpfwd_port_socat () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local SELFFILE="$(readlink -m -- "$BASH_SOURCE")"
  local SELFPATH="$(dirname -- "$SELFFILE")"
  cd / || return $?

  local -A CFG=()
  local POS_ARGN=( lsnport tgthost tgtport + )
  local POS_ARGS=()
  local SOCAT_CMD=( socat )
  parse_cli_opts "$@" || return "${CFG[retval]:-$?}"

  cfg_dflt netproto TCP
  cfg_dflt lsnhost localhost
  cfg_dflt lsnport "77${CFG[tgtport]}"
  cfg_dflt tgthost localhost
  cfg_dflt tgtport 80
  cfg_dflt tgtproxy none

  local ITEM=
  for ITEM in {lsn,tgt}port; do
    [ "${CFG[$ITEM]:-0}" -ge 1 ] && continue
    echo "E: $ITEM must be a positive number" >&2
    return 2
  done

  local LSN_SOCK="${CFG[lsnproto]:-${CFG[netproto]}}-LISTEN:${CFG[lsnport]}"
  case "${CFG[lsnhost]}" in
    0.0.0.0 | \
    : | . | \
    '*' ) ;;
    * ) LSN_SOCK+=",bind=${CFG[lsnhost]}";;
  esac
  LSN_SOCK+=",reuseaddr"
  LSN_SOCK+=",fork"
  LSN_SOCK+=",${CFG[lsnopt]}"

  cfg_tgtproxy || return $?
  local TGT_SOCK="${CFG[tgtproto]:-${CFG[netproto]}}$(
    ):${CFG[tgthost]}:${CFG[tgtport]}"
  [ -z "${CFG[tgtopt]//,/}" ] || TGT_SOCK+=",${CFG[tgtopt]#,}"

  SOCAT_CMD+=( "$LSN_SOCK" "$TGT_SOCK" )

  opt_execalias || return $?

  [ "${DEBUGLEVEL:-0}" -ge 2 ] && echo "# exec ${SOCAT_CMD[*]}" >&2
  exec "${SOCAT_CMD[@]}"
  return $?
}


function opt_execalias () {
  local REP="${CFG[execalias-replace]}"
  if [ -n "$REP" ]; then
    local PIDS=( $(pidof "$REP" | grep -xPe '[\d\s]+') )
    if [ -n "${PIDS[*]}" ]; then
      kill -HUP "${PIDS[@]}"
      sleep 0.2s
    fi
  fi
  local EXA="${CFG[execalias]:-$REP}"
  [ -z "$EXA" ] || SOCAT_CMD=( -a "$EXA" "${SOCAT_CMD[@]}" )
}


function parse_cli_opts () {
  local OPT=
  while [ "$#" -gt 0 ]; do
    OPT="$1"; shift
    case "$OPT" in
      -- ) POS_ARGS+=( "$@" ); break;;
      --sslkey=* ) echo "E: SSL isn't supported yet." >&2; return 3;;
      -x | -v | -d ) SOCAT_CMD+=( "$OPT" );;
      --lsnopt=* | \
      --tgtopt=* | \
      --cfg+:*=* )
        OPT="${OPT#--}"
        OPT="${OPT#cfg+:}"
        CFG["${OPT%%=*}"]+="${OPT#*=}";;
      --execalias=* | \
      --execalias-replace=* | \
      --lsnhost=* | \
      --lsnport=* | \
      --lsnproto=* | \
      --netproto=* | \
      --sslcert=* | \
      --tgthost=* | \
      --tgtport=* | \
      --tgtproto=* | \
      --tgtproxy=* | \
      --cfg:*=* )
        OPT="${OPT#--}"
        OPT="${OPT#cfg:}"
        CFG["${OPT%%=*}"]="${OPT#*=}";;
      --public ) CFG[lsnhost]='*';;
      --sslenc ) CFG[tgtproto]='OPENSSL';;
      --sslenc-anycert )
        CFG[tgtproto]='OPENSSL'
        CFG[tgtopt]+=',verify=0'
        ;;
      --ancient-ssl )
        # required for Speedport W 503V
        CFG[tgtopt]+=',cipher=MD5'
        ;;
      --help | \
      -* )
        local -fp "${FUNCNAME[0]}" | guess_bash_script_config_opts-pmb
        if [ "${OPT//-/}" == help ]; then
          CFG[retval]=0
        else
          echo "E: $0, CLI: unsupported option: $OPT" >&2
        fi
        return 1;;
      * )
        case "${POS_ARGN[0]}" in
          '' ) echo "E: $0: unexpected positional argument" >&2; return 1;;
          '+' ) POS_ARGS+=( "$OPT" );;
          * ) CFG["${POS_ARGN[0]}"]="$OPT"; POS_ARGN=( "${POS_ARGN[@]:1}" );;
        esac;;
    esac
  done
}


function cfg_dflt { [ -n "${CFG[$1]}" ] || CFG["$1"]="$2"; }


function cfg_tgtproxy () {
  local PRX="${CFG[tgtproxy]}"
  case "$PRX" in
    none | '' ) return 0;;
    http://* ) cfg_tgtproxy__connect "$PRX"; return $?;;
  esac
  echo E: $FUNCNAME: "Option tgtproxy: Unsupported syntax: '$PRX" >&2
  return 2
}


function cfg_tgtproxy__connect () {
  local PRX_SPEC="$1"
  PRX_SPEC="${PRX_SPEC#*://}"
  PRX_SPEC="${PRX_SPEC%/}"
  local PRX_PORT="${PRX_SPEC##*:}"
  PRX_SPEC="${PRX_SPEC%:*}"
  [ "$PRX_SPEC" != "$PRX_PORT" ] || PRX_PORT=
  local PRX_AUTH="${PRX_SPEC%@*}"
  PRX_SPEC="${PRX_SPEC##*@}"
  [ "$PRX_SPEC" != "$PRX_AUTH" ] || PRX_AUTH=
  local PRX_HOST="$PRX_SPEC"
  CFG[tgtproto]="PROXY:$PRX_HOST"
  [ -z "$PRX_PORT" ] || CFG[tgtopt]+=",proxyport=$PRX_PORT"
  [ -z "$PRX_AUTH" ] || CFG[tgtopt]+=",proxyauth=$PRX_AUTH"
}












tcpfwd_port_socat "$@"; exit $?
