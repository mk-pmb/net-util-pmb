#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function spc_cli_init () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local SELFFILE="$(readlink -m -- "$BASH_SOURCE")"
  local -A CFG=(
    [appname]='serialport-chat'
    [task]='rlwrap'
    [dev]='/dev/ttyUSB0'
    [delay]=0.1
    )
  local VAL=
  for VAL in "$@"; do
    case "$VAL" in
      [a-z]*=* ) CFG["${VAL%%=*}"]="${VAL#*=}";;
      * ) echo E: "Unsupported CLI option: $VAL" >&2; return 4;;
    esac
  done
  spc_"${CFG[task]}" "$@"; return $?
}


function spc_rlwrap () {
  tty --silent || return 4$(echo E: 'Expected to run in a TTY.' >&2)
  exec rlwrap \
    --command-name "$(basename -- "${CFG[dev]}")" \
    -- "$SELFFILE" task=chat "$@"
  echo E: "Failed to re-exec in rlwrap" >&2
  return 4
}


function spc_chat () {
  cd /
  exec 3> >(exec -a "${CFG[appname]}-decorate" \
    sed -ure 's~\s+$~~; /\S/!d; s~^~\r> ~')
  case "${CFG[dev]}" in
    //nl ) exec 3> >(exec stdbuf -i0 -o0 nl -ba >&3);;
    * ) exec 3> >(exec socat STDIO GOPEN:"${CFG[dev]}" >&3);;
  esac
  exec 4<> >(:)
  local ORIG= BUF= IGNORE=
  while IFS= read -r -p ': ' BUF; do
    ORIG="$BUF"
    BUF="${BUF%%'   #'*}"
    BUF="${BUF%$'\r'}"
    while [[ "$BUF" == *' ' ]]; do BUF="${BUF% }"; done
    [ -n "$BUF" ] || continue
    IFS= read -r -t "${CFG[delay]}" -u 4 IGNORE
    [ "$BUF" != "$ORIG" ] || echo -ne '\b\r'
    echo "< $BUF"
    echo "$BUF"$'\r' >&3
    IFS= read -r -t "${CFG[delay]}" -u 4 IGNORE
  done
  exec 4<&-
  exec 3<&-
}




spc_cli_init "$@"; exit $?
