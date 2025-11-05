#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function serial_repl () {
  export LANG{,UAGE}=en_US.UTF-8 # make error messages search engine-friendly

  local -A CFG=(
    [readcmd-timeout]=30
    [restart-delay]=5
    [wait-tty]=10
    )
  local ARG=
  while [[ "$1" == --* ]]; do
    ARG="${1#--}"; shift
    case "$ARG" in
      *=* ) CFG["${ARG%%=*}"]="${ARG#*=}";;
      * ) CFG["$ARG"]=+;;
    esac
  done

  local PORT="${1:-0}"; shift
  case "$PORT" in
    */* ) ;;
    [0-9]* ) PORT="/dev/ttyUSB$PORT";;
    [a-z]* ) PORT="/dev/$PORT";;
    * ) echo "Invalid port spec." >&2;;
  esac

  local BAUD_RATE="$1"; shift
  case "$BAUD_RATE" in
    [0-9]* ) ;;
    slow ) BAUD_RATE=9600;;
    '' | medium | default ) BAUD_RATE=115200;;
    * ) echo "E: invalid baud rate: '$BAUD_RATE'" >&2; return 3;;
  esac


  while true; do
    one_turn
    [ "${CFG[restart-delay]}" == quit ] && break
    sleep "${CFG[restart-delay]}"
  done
}


function can_has_port () { [ -c "$PORT" -o -p "$PORT" ]; }


function loglv () {
  local LVL="$1"; shift
  local MSG="$(date +'%F %T') serial_repl[$$]: $LVL: $*"
  case "$LVL" in
    W | E ) echo "$MSG" >&2;;
    * ) echo "$MSG";;
  esac
  if can_has_port; then
    MSG="$MSG" PORT="$PORT" sh -c 'echo "$MSG" >>"$PORT"' &
    disown $!
  fi
}


function quickly_try_open_tty () {
  exec 0<&-
  can_has_port || return $?
  exec <"$PORT" || return $?
}


function patiently_try_open_tty () {
  # First, close stdin, to release the device name so it can disappear,
  # and potentially re-appear when a user reconnects the TTY.
  SECONDS=0
  local NOPE="Port '$PORT' not readable!"
  local TMO="${CFG[wait-tty]:-0}" RMN=
  while ! quickly_try_open_tty; do
    let RMN="$TMO - $SECONDS"
    loglv W "$NOPE Waiting for up to $RMN seconds."
    if [ "$RMN" -ge 1 ]; then
      sleep 2s
    else
      loglv E "$NOPE Giving up."
      return 3
    fi
  done
}


function one_turn () {
  if ! patiently_try_open_tty; then
    CFG[restart-delay]=quit
    return 3
  fi
  local STTY=(
    stty
    -F "$PORT" # --file= might not be available e.g. in initramfs busybox.
    "$BAUD_RATE"
    sane -cstopb raw litout -echo
    )
  loglv D "${STTY[*]}"
  "${STTY[@]}"

  local LN= PREV_LN= RV=
  local COOLDOWN=0
  local MAX_COOLDOWN=30
  while sleep 1s; do
    LN=
    loglv D 'trying to read one command.'
    SECONDS=0
    IFS= read -r -t "${CFG[readcmd-timeout]}" LN; RV=$?
    [ "$RV" -gt 128 ] && RV='timeout'
    case "$RV" in
      0 ) ;;
      timeout )
        loglv D "read timeout after $SECONDS sec"
        continue;;
      * )
        loglv W "failed ($?) to read command after $SECONDS sec"
        return $RV;;
    esac
    LN="${LN%$'\r'}"
    loglv D "read command after $SECONDS sec: '$LN'"
    case "$LN" in
      '' ) continue;;
      exit | quit | Q )
        loglv D "goodbye!"
        CFG[restart-delay]=quit
        return 0;;
      "$PREV_LN" )
        (( COOLDOWN = (COOLDOWN * 2) + 1 ))
        [ "$COOLDOWN" -le "$MAX_COOLDOWN" ] || COOLDOWN="$MAX_COOLDOWN"
        loglv D "repeated command ignored. cooldown! ($COOLDOWN sec)"
        sleep "$COOLDOWN"s
        continue;;
    esac
    COOLDOWN=0
    PREV_LN="$LN"
    case "$LN " in
      'set '* | \
      'let '* | \
      'export '* | \
      'pushd '* | 'popd '* | \
      'cd '* )
        LN="${LN#set }"
        eval "$LN"
        <<<"${LN%% *} rv=$?, cwd is now $PWD" tee -- "$PORT";;
      'fin? '* )
        in_new_scope eval "${LN#* }" |& tee -- "$PORT"
        RV="${PIPESTATUS[0]}"
        if [ "$RV" == 0 ]; then
          loglv D "final command succeeded => quit."
          CFG[restart-delay]=quit
          return 0
        fi
        ;;
      * )
        in_new_scope eval "$LN" |& tee -- "$PORT"
        # do NOT use stdin or it will echo!
        ;;
    esac
  done
}


function in_new_scope () { "$@"; }










serial_repl "$@"; exit $?
