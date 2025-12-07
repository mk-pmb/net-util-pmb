#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-

function serial_upload () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local SELFPATH="$(readlink -m -- "$BASH_SOURCE"/..)"
  local ESP_MNPT="${ESP_MNPT:-«HOST»_esp}"
  [ "${ESP_MNPT:0:1}" == / ] || ESP_MNPT="/mnt/$ESP_MNPT"

  local FINISH=
  if [ "$1" == --reboot ]; then FINISH='reboot -f'; shift; fi
  [ -n "$SUP_DEVICE" ] || local SUP_DEVICE='/dev/ttyUSB0'

  local ARG="$1"; shift
  case "$ARG:$#" in
    --grub:0 ) echo H: 'Try --grub-base';;
  esac
  local UPCMD=( serial_upload__one_file "$ARG" )
  case "$ARG" in
    -- ) ;;
    --grub ) UPCMD=( serial_upload__multi //ESP//grub/ );;
    -t | --into ) UPCMD=( serial_upload__multi );;

    --grub-base | \
    -- ) UPCMD=( with_logfile serial_upload"${ARG//-/_}" );;

    -* ) echo E: $FUNCNAME: "Unsupported option: '$ARG'" >&2; return 4;;
    * ) echo E: $FUNCNAME: "Invalid argument: '$ARG'" >&2; return 4;;
  esac
  "${UPCMD[@]}" "$@" || return $?
  [ -z "$FINISH" ] || <<<"$FINISH" serial_upload__communicate
}


function with_logfile {
  local LOG_FILE="tmp.$1.${ARG#--}.$(printf '%(%y%m%d-%H%M%S)T' -1)-$$.log"
  echo D: "Log file will be $LOG_FILE"
  "$@" |& unbuffered tee -- "$LOG_FILE"
  [ "${PIPESTATUS[*]}" == '0 0' ] || return 4$(
    echo E: $FUNCNAME: "rvs=<${PIPESTATUS[*]}>" >&2)
}


function serial_upload__multi () {
  local SRC= DEST="$1"; shift
  DEST="${DEST/#'//ESP//'/$ESP_MNPT/}"
  local VAL=
  local BYTES_SENT=0 BYTES_TOTAL=0
  for SRC in "$@"; do
    VAL=
    VAL="$(stat -c %s -- "$SRC")"
    if [ -n "$VAL" ]; then
      (( BYTES_TOTAL += VAL ))
    else
      echo "W: Failed to find file size for: $SRC" >&2
    fi
  done
  local FILES_SENT=0 FILES_TOTAL="$#"
  [ "$FILES_TOTAL" -ge 1 ] || return 4$(
    echo E: $FUNCNAME: "No files to be sent to destination: '$DEST'" >&2)
  SECONDS=0
  for SRC in "$@"; do
    serial_upload__one_file "$SRC" "$DEST" || return $?
    sleep 0.2 || return $? # <- Allow for Ctrl+c to hit this script.
  done
  sox-synth-play-notes C G &>/dev/null
  echo D: $FUNCNAME: "Done uploading $# files in $SECONDS seconds."
}


function timefmt_sec2dura () { TZ=UTC printf -- '%(%Hh:%Mm:%Ss)T' "$1"; }


function serial_upload__one_file () {
  [ "$1" == -- ] && shift
  local SRC="$1"; shift
  [ -n "$SRC" ] || return 4$(echo E: $FUNCNAME: 'No souce filename given!' >&2)
  local DEST="$1"; shift
  [ "$DEST" == . ] && DEST=
  case "$DEST" in
    '' | */ ) DEST+="$(basename -- "$SRC")";;
  esac
  local Q_DEST="'$DEST'"
  Q_DEST="${Q_DEST//«HOST»/\'\"\$irdex_host\"\'}"
  # echo ">> $SRC >> $Q_DEST"

  local SIZE="$(stat -c %s -- "$SRC")"
  [ "${SIZE:--1}" -ge 0 ] || return 4$(
    echo E: "Failed to detect file size for: $SRC" >&2)
  local PROGRESS=
  if [ -n "$FILES_SENT" ]; then
    (( FILES_SENT += 1 ))
    PROGRESS+=" file $FILES_SENT / $FILES_TOTAL ($((
      ( 100 * $FILES_SENT ) / $FILES_TOTAL ))%)"
  fi
  if [ -n "$BYTES_SENT" ]; then
    (( BYTES_SENT += SIZE ))
    PROGRESS+=" bytes $BYTES_SENT / $BYTES_TOTAL ($((
      ( 100 * $BYTES_SENT ) / $BYTES_TOTAL ))%)"
  fi
  if [ -n "$FILES_SENT$BYTES_SENT" ]; then
    PROGRESS+=", $SECONDS sec elapsed"
  fi

  local CKSUM_PROG='sha1sum'
  local CKSUM_LINE="$($CKSUM_PROG --binary - <"$SRC")"
  local UP_TMP_SUF=".up-$$.part"
  local UNIQ="# $$:$RANDOM$PROGRESS"
  local SYNC="sync; echo '${CKSUM_LINE%-}/dev/fd/5' |"
  SYNC+=" sha1sum --check 5<$Q_DEST$UP_TMP_SUF"

  SYNC+=" && mv -f -- $Q_DEST{$UP_TMP_SUF,}"
  # ^-- Busybox mv is very limited!
  SYNC+=" && sync"

  # SYNC+="; DEST=$Q_DEST"
  # SYNC+="; DEST=$Q_DEST"
  # SYNC+='; ls -l -- "$DEST"'
  # SYNC+='; stat -c %s -- "$DEST"'
  SYNC+=" $UNIQ"

  local HEAD_LINES=(
    "sed -nre '/:/q;s~[# \r]~~g;p' | base64 -d >$Q_DEST$UP_TMP_SUF"
    )
  local TAIL_LINES=(
    "# : $$" # this is the end marker for the remote sed
    ''  # The pipe behind the remote sed needs an extra bump.

    "$SYNC"
    )

  [ -n "$SUP_LINK_SPEED_BAUD" ] || local SUP_LINK_SPEED_BAUD=115200
  [ -n "$SUP_SAFETY_MARGIN_BAUD" ] || local SUP_SAFETY_MARGIN_BAUD=200
  local BITS_PER_BYTE=10 # 8 data bits + 1 start bit + 1 stop bit
  local MAX_KB_PER_SEC=$(( ( SUP_LINK_SPEED_BAUD - SUP_SAFETY_MARGIN_BAUD
    ) / BITS_PER_BYTE / 1024 ))

  [ -n "$SUP_LINE_DELAY_SEC" ] || local SUP_LINE_DELAY_SEC=1
  local MAX_KB_PER_LINE=$(( MAX_KB_PER_SEC * SUP_LINE_DELAY_SEC ))

  local B64_WIDTH=$(( ( MAX_KB_PER_LINE * 1024 ) - 3 )) # -3 = "# …\n"
  local B64_BYTES=$(( ( ( SIZE - 1) * 4 / 3 ) + 1))
  local B64_LINES=$(( ( ( B64_BYTES - 1) / B64_WIDTH ) + 1))

  local LINES_TOTAL=
  let LINES_TOTAL="$B64_LINES + ${#HEAD_LINES[@]} + ${#TAIL_LINES[@]}"
  local DURA_ESTIMATE_SEC=$(( LINES_TOTAL * SUP_LINE_DELAY_SEC ))
  echo D: "For $SRC ($SIZE bytes) we'll send ≈ $LINES_TOTAL lines" \
    "× $MAX_KB_PER_LINE KiB, which will take ≈ $(
    timefmt_sec2dura "$DURA_ESTIMATE_SEC"), ETA: $(
    date +'%F (%a) %T' --date="+$DURA_ESTIMATE_SEC sec")"

  exec < <(
    printf -- '%s\n' "${HEAD_LINES[@]}"
    base64 -w "$B64_WIDTH" -- "$SRC" | sed -re 's~^~# ~'
    printf -- '%s\n' "${TAIL_LINES[@]}"
    )
  if [ "$SUP_LINE_DELAY_SEC" == -1 ]; then
    DEST="tmp.sup.$(basename -- "$SRC").txt"
    cat >"$DEST"
    du -h -- "$DEST"
    return 0
  fi
  SUSS_CKSUM="$SRC" serial_upload__slowly_send
}


function serial_upload__communicate () {
  serialport-socat --device="$SUP_DEVICE" --ignblank STDIO
}


function serial_upload__slowly_send () {
  local SEND_DURA_EFF="$(printf -- '%(%s)T' -1)"
  # "unbuffered" and "oneline-alive" are from text-transforms-pmb
  perl -pe '$|=1;sleep '"$SUP_LINE_DELAY_SEC" | unbuffered tee -- >(
    unbuffered cut --bytes=1-120 | unbuffered nl -ba | oneline-alive >&2
    ) | serial_upload__communicate
  let SEND_DURA_EFF="$(printf -- '%(%s)T' -1) - $SEND_DURA_EFF"
  echo D: "Sent in ≈ $(timefmt_sec2dura "$SEND_DURA_EFF")."
}


function serial_upload__grub_base () {
  [ "$#" == 0 ] || return 4$(
    echo E: $FUNCNAME: "Unsupported argument: '$1'" >&2)
  local GRUB_CDP="${SUP_GRUB_CFG_DIR_PREFIX:-/boot/esp/grub/}"
  local SEND_ABS=() SEND_SUB=() SKIP_SUB=()
  local SRC= SUB= BFN=
  for SRC in "$GRUB_CDP"*.{grub,cfg}; do
    [ -f "$SRC" ] || continue
    SUB="${SRC#$GRUB_CDP}"
    case "$SUB" in
      # intentional skips:
      cfg.@* | \
      . ) SKIP_SUB+=( "$SUB" ); continue;;

      # suspicious file names:
      *@* | \
      . ) SRC=//skip+warn//;;

      [a-z]* ) SEND_ABS+=( "$SRC" ); SEND_SUB+=( "$SUB" );;
      * ) SRC=//skip+warn//;;
    esac
    case "$SRC" in
      //skip+warn// )
        SKIP_SUB+=( "$SUB" )
        echo W: $FUNCNAME: "skip: '$SRC'" >&2;;
    esac
  done
  echo D: $FUNCNAME: "send: ${SEND_SUB[*]} (n=${#SEND_SUB[@]})"
  echo D: $FUNCNAME: "skip: ${SKIP_SUB[*]} (n=${#SKIP_SUB[@]})"
  serial_upload__multi //ESP//grub/ "$@" "${SEND_ABS[@]}" || return $?
}

























serial_upload "$@"; exit $?
