#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function serialcat_cli_main () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local DBGLV="${DEBUGLEVEL:-0}"
  local MAIN_PID=$$
  if [ "$1" == --func ]; then shift; "$@"; return $?; fi

  local INVOKED_AS="$(basename -- "$0" .sh)"
  local -A CFG=(
    [device]=
    [devopt]=
    [baud]=115200
    [addr]=
    [flags]=
    )
  local INSANE=(
    -cstopb     # one stop bit probably is enough
    -echo       # your terminal or rlwrap probably already does it
    )
  local OPT= KEY= VAL=
  while [ "$#" -gt 0 ]; do
    OPT="$1"; shift
    case "${OPT:-## hide from --help ##}" in
      [0-9]* )
        croak E "unsupported argument: '$OPT'" >&2
        croak H "Did you mean '--baud=$OPT' or 'GOPEN:$OPT'?" >&2
        return 3;;
      [A-Z]* )
        for KEY in device addr; do
          if [ -z "${CFG[$KEY]}" ]; then
            OPT="--$KEY=$OPT"
            break
          fi
        done
        if [ "${OPT:0:2}" != '--' ]; then
          echo "W: $0: Both device (${CFG[device]}) and addr (${CFG[addr]})" \
            "are already configured." >&2
          croak E "Unexpected device/addr argument: '$OPT'" >&2
          return 2
        fi;;
    esac
    case "$OPT" in
      --slow ) CFG[baud]=9600;;
      --addr=* | \
      --baud=* | \
      --device=* | \
      --input-line-delay=* | \
      --mode=* )
        OPT="${OPT#--}"
        CFG["${OPT%%=*}"]="${OPT#*=}";;
      --devopt=* )
        OPT="${OPT#--}"
        CFG["${OPT%%=*}"]+=",${OPT#*=}";;
      --one-stopbit ) INSANE+=( -cstopb );;
      --two-stopbits ) INSANE+=( cstopb );;
      --echo | +echo ) INSANE+=( echo );;
      --insane=* ) INSANE+=( "${OPT#*=}" );;
      --verbatim ) INSANE+=( raw litout -echo );;
      -. | --ignblank ) CFG[outgrep]=.;;
      --fd-info ) CFG[flags]+=' -D';;
      --verbose ) CFG[flags]+=' -d -d';;
      -d ) CFG[flags]+=' -d';;
      -P | --prepare-only ) CFG[addr]='PREPARE-ONLY';;
      --help | \
      * )
        local -fp "${FUNCNAME[0]}" | guess_bash_script_config_opts-pmb
        [ "${OPT//-/}" == help ] && return 1
        croak E "Unsupported option: $OPT" >&2; return 1;;
    esac
  done

  KEY="${CFG[device]}"
  VAL="$(scan_systemd_services_at_device "$KEY")"
  VAL="${VAL//$'\n'/ }"
  [ -z "$VAL" ] || return 4$(echo E: >&2 \
    "These systemd services are probably using device '$KEY': $VAL")

  local STTY=(
    stty
    -F "${CFG[device]}" # using -F instead of --file= to appease busybox
    "${CFG[baud]}"
    sane "${INSANE[@]}"
    )
  [ "$DBGLV" -ge 2 ] && echo "D: [main=$MAIN_PID] ${STTY[*]}" >&2
  "${STTY[@]}" || return $(
    croak E "failed to configure TTY: ${CFG[device]}" >&2)

  local ADDR="${CFG[addr]}"
  local TEE_FILE= TEE_OPTS=
  local EXEC=( exec -a "$INVOKED_AS" )
  case "$ADDR" in
    PREPARE-ONLY ) return 0;;
    '' )
      croak E "No local socat addr given!" >&2
      croak H "Try 'STDOUT'" \
        "or 'STDIO'" \
        "or 'READLINE'" \
        "or 'TEE:%(%F/%H%M%S)T.%p.log'" \
        "or 'TEE-APPEND:serial.log'" \
        >&2
      return 4;;
    READLINE )
      # see also: --ignblank
      EXEC+=( rlwrap )
      ADDR='STDIO';;
    BASE64.:* )
      exec < <(base64 -- "${ADDR#*:}" \
        | slowcat -d "${BASE64DOT_SPEED:-0.1}"; echo .)
      ADDR='STDIO';;
    TEE:* ) TEE_FILE="$ADDR";;
    TEE-APPEND:* ) TEE_FILE="$ADDR"; TEE_OPTS='-a';;
  esac

  if [ -n "$TEE_FILE" ]; then
    ADDR='STDOUT'
    TEE_FILE="${TEE_FILE#*:}"
    TEE_FILE="${TEE_FILE//%p/$$}"
    printf -v TEE_FILE "$TEE_FILE"
    mkdir --parents -- "$(dirname -- "$TEE_FILE")"
    >>"$TEE_FILE" || return $?
    exec &> >(stdbuf -{i,o,e}0 tee $TEE_OPTS -- "$TEE_FILE") || return $?
  fi

  KEY='input-line-delay'
  VAL="${CFG[$KEY]}"
  case "$VAL" in
    '' ) ;;
    [^0-9]* | *[^0-9.]* | *.*.* )
      croak E "Invalid number for option $KEY:" \
        "Expected seconds (potentially fractional) but got '$VAL'" >&2
      return 4;;
    * ) exec < <(perl -pe '$|=1;select(undef,undef,undef,'"$VAL);");;
  esac

  local EXEC=(
    "${EXEC[@]}"
    socat
    ${CFG[flags]}
    "$ADDR"
    GOPEN:"${CFG[device]}${CFG[devopt]}"
    )
  [ "$DBGLV" -ge 2 ] && echo "D: ${EXEC[*]}" >&2
  [ -z "${CFG[outgrep]}" ] || exec > >(
    grep --line-buffered -aPe "${CFG[outgrep]}")
  "${EXEC[@]}" || return $?
}


function croak () {
  local LOGLEVEL="$1"; shift
  echo "$LOGLEVEL: $INVOKED_AS [main=$MAIN_PID]: $*" >&2
}


function scan_nondead_systemd_services () {
  # non-dead = activating, active, deactivating, …
  LANG=C systemctl list-units --all --full --plain --no-legend \
    --type=path,service 2>/dev/null | tr -s '\t ' '\t' |
    cut -sf 1,3 | grep -vPe '\t(failed|inactive)$' | cut -sf 1
}


function scan_systemd_services_at_device () {
  set -- "${1#/dev/}"
  [ -n "$1" ] || return 3
  scan_nondead_systemd_services | sed -re '/@/!d; s~@|\.|$~ &~g' |
    grep -Fe " @$1 " | tr -d ' ' | sort --version-sort
}








serialcat_cli_main "$@"; exit $?
