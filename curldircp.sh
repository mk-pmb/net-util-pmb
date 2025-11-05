#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-

function curldircp () {
  local DBGLV="${DEBUGLEVEL:-0}"
  local SRC_TODO=()
  local -A CFG=(
    [datefmt]='@%s = %F %T'
    [nice]=15
    [into]=  # destdir
    [limit-rate]=
    [max-files]=
    )
  local VAL=

  CFG[ionice]='idle'
  # ^-- 2019-04-15 FreeNode IRC, #ubuntu
  #   <Sven_vB> […] VLC to prio 2 and curl to 7 but still same problem. […]
  #   <lordcirth__> […] don't tinker with priority, set curl to be 'idle'

  while [ "$#" -gt 0 ]; do
    VAL="$1"; shift
    case "$VAL" in
      '' ) ;;
      -- ) SRC_TODO+=( "$@" ); break;;
      -. ) CFG[into]=.;;
      -G ) CFG[if-in-subdir]=retarget;;
      -g ) CFG[if-in-subdir]=skip;;
      -M ) CFG[preserve-free-mb]="$1"; shift;;
      -N ) CFG[max-files]="$1"; shift;;
      --*=* )
        VAL="${VAL#--}"
        CFG["${VAL%%=*}"]="${VAL#*=}";;
      -* ) echo "E: $0: unsupported option: $VAL" >&2; return 3;;
      * ) SRC_TODO+=( "$VAL" );;
    esac
  done

  local DEST_DIR="${CFG[into]}"
  if [ -z "$DEST_DIR" ]; then
    DEST_DIR="${SRC_TODO[${#SRC_TODO[@]}-1]}"
    SRC_TODO=( "${SRC_TODO[@]:0:${#SRC_TODO[@]}-1}" )
  fi
  [ "${#SRC_TODO[@]}" -ge 1 ] || return 3$(echo 'E: no sources given' >&2)
  case "$DEST_DIR" in
    '~'* ) DEST_DIR="$HOME${DEST_DIR:1}";;
  esac

  local PRESERVE_DISK_SPACE="${CFG[preserve-free-mb]:-0}"
  PRESERVE_DISK_SPACE="${PRESERVE_DISK_SPACE//[_ ]/}"
  [ -n "${PRESERVE_DISK_SPACE//[^0-9]/}" ] || return 4$(
    echo E: 'Unsupported number format for minimum required disk space!' >&2)
  # Convert to bytes so we don't need to worry about fractions later:
  PRESERVE_DISK_SPACE="$(( PRESERVE_DISK_SPACE * 1024 * 1024 ))"
  [ "$PRESERVE_DISK_SPACE" -ge 0 ] || return 4$(
    echo E: 'Unsupported number format for minimum required disk space!' >&2)

  local N_FILES_MAX="${CFG[max-files]}"
  if [ -n "$N_FILES_MAX" ]; then
    [ -n "${N_FILES_MAX//[^0-9]/}" ] || return 3$(echo E: $FUNCNAME: >&2 \
      "Non-empty value for option max-files contains no digits!")
    N_FILES_MAX="${N_FILES_MAX//[_,]/}" # strip potential thousands separators
    (( N_FILES_MAX += 0 ))
    [ "$N_FILES_MAX" -ge 0 ] || return 3$(echo E: $FUNCNAME: >&2 \
      echo E: "Value for option max-files must be empty, zero or positive.")
  fi
  local N_FILES_DONE=0

  DEST_DIR="${DEST_DIR%/}"
  mkdir --parents -- "$DEST_DIR" || return $?
  local DEST_BASE_REAL="$(readlink -m "$DEST_DIR")"

  local TIME_STARTED="$(date +"${CFG[datefmt]}")"
  renice -n "${CFG[nice]}" -p $$

  case "${CFG[ionice]}" in
    realtime )  # beware!
      ionice --class 1 --pid $$;;
    be:[0-7] )    # best effort
      ionice --class 2 --classdata "${CFG[ionice]#*:}" --pid $$;;
    idle )
      ionice --class 3 --pid $$;;
    * )
      echo "E: unsupported value for option ionice: '${CFG[ionice]}'" >&2
      return 8;;
  esac
  echo "D: ionice $$: $(ionice --pid $$)"

  local CURL_CMD=(
    curl
    --continue-at -
    )
  [ -n "${CFG[limit-rate]}" ] && CURL_CMD+=(
    --limit-rate "${CFG[limit-rate]}" )
  # echo "D: curl cmd: ${CURL_CMD[*]}"

  local RETVAL=0
  VAL=
  while [ "${#SRC_TODO[@]}" -ge 1 ]; do
    VAL="${SRC_TODO[0]}"; SRC_TODO=( "${SRC_TODO[@]:1}" )
    check_early_done && break || true
    copy_next_userprovided_src_todo_item "$VAL"
    RETVAL=$?
    [ "$RETVAL" == 0 ] || break
  done
  local TIME_FINISHED="$(date +"${CFG[datefmt]}")"

  echo
  VAL="$(disk-space-report "$DEST_DIR")" # <- from file-util-pmb
  [ -z "$VAL" ] || VAL=", $VAL."
  echo "started:  $TIME_STARTED"
  echo "finished: $TIME_FINISHED, rv=$RETVAL, $N_FILES_DONE files copied$VAL"
  return "$RETVAL"
}


function copy_next_userprovided_src_todo_item () {
  local SRC_ITEM="$1"
  local -A SRC_META=( [type]='filesystem_object' )
  copy_next_identify_src_type || return $?
  [ "$DBGLV" -lt 8 ] || echo D: $FUNCNAME: "$(local -p | tr '\n' ' ')"
  copy_next_userprovided_"${SRC_META[type]}" "$SRC_ITEM" || return $?
}


function copy_next_identify_src_type () {
  if [[ "$SRC_ITEM" =~ ^file:/+ ]]; then
    SRC_ITEM="${SRC_ITEM:${#BASH_REMATCH[0]}}"
    return 0
  fi

  local RGX='^(%p:|)(http)(s?)(\+%p|)://'
  RGX="${RGX//%p/[a-z0-9-]+}"
  if [[ "$SRC_ITEM" =~ $RGX ]]; then
    set -- "${BASH_REMATCH[@]:1}"
    SRC_META[fx]="${1%:}"
    [ -z "${SRC_META[fx]}" ] || SRC_ITEM="${SRC_ITEM#*:}"
    SRC_META[type]="url_$2"
    SRC_META[proto]="$2$3"
    SRC_META[subproto]="${4#+}"
    if [[ "$SRC_ITEM" == *'#'* ]]; then
      SRC_META[hash]="#${SRC_ITEM#*#}"
      SRC_ITEM="${SRC_ITEM%%#*}"
    fi
    return 0
  fi

  return 0 # Probably a file path => accept as is.
}


function copy_next_userprovided_filesystem_object () {
  local SRC_DIR="$(dirname -- "$SRC_ITEM")"
  local SRC_NAME="$SRC_DIR"
  SRC_NAME="${SRC_NAME/#$HOME/'~'}"
  [[ "$SRC_NAME" =~ ^(.{20}).+?(.{30})$ ]] &&
    SRC_NAME="${BASH_REMATCH[1]}…${BASH_REMATCH[2]}"
  copy_dive "$(basename -- "$SRC_ITEM")" || return $?
}


function copy_dive () {
  local SRC_SUB="$1"
  case "$SRC_SUB" in
    '' | . | .. | */ )
      echo E: $FUNCNAME: "Flinching: Suspicious filename: '$SRC_SUB'" >&2
      return 6;;
  esac
  local SRC_ABS="$SRC_DIR/$SRC_SUB"
  local DEST_ABS=
  chk_dest_in_subdir || return $?
  [ "$DEST_ABS" == //skip// ] && return 0
  [ -n "$DEST_ABS" ] || DEST_ABS="$DEST_DIR/$SRC_SUB"
  local SRC_DESCR="$SRC_SUB <- $SRC_NAME"
  case "${SRC_META[type]}" in
    url_* )
      echo "url: $SRC_DESCR"
      copy_file "$SRC_ABS" "$DEST_ABS"; return $?
  esac
  if [ -L "$SRC_ABS" ]; then
    copy_symlink; return $?
  elif [ -f "$SRC_ABS" ]; then
    echo "file: $SRC_DESCR"
    copy_file "$SRC_ABS" "$DEST_ABS"; return $?
  elif [ -d "$SRC_ABS" ]; then
    copy_subdir; return $?
  elif [ -S "$SRC_ABS" ]; then
    echo "skip socket: $SRC_DESCR"; return 0
  elif [ -p "$SRC_ABS" ]; then
    echo "skip pipe: $SRC_DESCR"; return 0
  fi
  echo "w00t: $SRC_ABS in copy_dive, source type '${SRC_META[type]}'"
  return 2
}


function chk_dest_in_subdir () {
  local IFSUB="${CFG[if-in-subdir]}"
  [ -n "$IFSUB" ] || return 0
  [ "$DBGLV" -lt 5 ] || echo "subdir scan: $IFSUB? $DEST_DIR/*/$SRC_SUB"
  # DEST_ABS: inherited and used for '//skip//' feedback
  for DEST_ABS in "$DEST_DIR"/*/"$SRC_SUB"; do
    [ -e "$DEST_ABS" ] && break
    DEST_ABS=
  done
  [ -n "$DEST_ABS" ] || return 0
  local DEST_IN_SUB="$(basename -- "$(dirname -- "$DEST_ABS")")"
  echo -n "found '$SRC_SUB' in subdir '$DEST_IN_SUB'"
  case "$IFSUB" in
    skip )
      echo ', skip.'
      DEST_ABS=//skip//
      return 0;;
    retarget )
      echo ', will adjust target.'
      return 0;;
    ignore | ign )
      echo ', fyi.'
      DEST_ABS=
      return 0;;
  esac
  echo -n ', but ';
  echo "strategy '$IFSUB' is not supported." >&2
  return 8
}


function grant_temp_write () {
  local DEST="$1"
  [ -w "$DEST" ] && return $?
  chmod u+w "$DEST" && return $?
  echo "W: failed to grant user write access to target: $DEST" >&2
  return 0
}


function copy_symlink () {
  echo -n "link: $SRC_SUB"
  local SYM_DEST="$(symlink-get-dest "$SRC_ABS")"
  [ -n "$SYM_DEST" ] || return 4$(
    echo "E: $FUNCNAME: unable to read original symlink's target" >&2)
  echo " = $SYM_DEST"
  if [ ! -L "$DEST_ABS" ]; then
    ln --symbolic --no-target-directory -- "$SYM_DEST" "$DEST_ABS"
    return $?
  fi
  # Target is a symlink => compare:
  local TRGT_SYM="$(symlink-get-dest "$DEST_ABS")"
  [ -n "$TRGT_SYM" ] || return 4$(
    echo "E: $FUNCNAME: unable to read destination symlink's target" >&2)
  if [ "$TRGT_SYM" == "$SYM_DEST" ]; then
    (( N_FILES_DONE += 1 ))
    return 0
  fi
  echo 'E: target symlink already exists but points elsewhere!' >&2
  c_stat %N "$DEST_ABS"
  return 2
}


function copy_file () {
  local SRC_FN="$1"; shift
  local DEST_FN="$(curl_defuse_savefn <<<"$1")"; shift
  DEST_FN="$(curl_defuse_savefn <<<"$DEST_FN")"
  local CURL_RV=0

  case "${SRC_META[type]}" in
    url_* )
      copy_file__create_dest || return $?
      SRC_URL="$SRC_ITEM" copy_file__core_download || return $?
      ;;

    * )
      SRC_FN="$(curl_defuse_savefn <<<"$SRC_FN")"
      copy_file__content || return $?
      copy_attribs "$SRC_FN" "$DEST_FN"
      ;;
  esac

  [ "${SRC_URL:0:5}" == 'info:' ] && echo "${SRC_URL:5}"
  (( N_FILES_DONE += 1 ))
  echo
  return $CURL_RV
}


function copy_file__content () {
  local SRC_SZ="$(c_stat %s -- "$SRC_FN")"
  [ "$SRC_SZ" -ge 0 ] || return 4$(
    echo E: 'Cannot determine source file size!' >&2)
  [ "$SRC_SZ" -ge 1 ] || [ "${CFG[empty-source-file]}" == accept ] || return 4$(
    echo E: 'Source file seems empty. Consider option "empty-source-file".' >&2)

  local DEST_SZ=0 MIN_COPY_BYTES=0
  if [ -f "$DEST_FN" ]; then
    DEST_SZ="$(c_stat %s -- "$DEST_FN")"
    [ "$DEST_SZ" == 0 ] || MIN_COPY_BYTES=1
  fi

  local BYTES_TO_COPY="$(( SRC_SZ - DEST_SZ ))"
  if [ -f "$DEST_FN" -a "$BYTES_TO_COPY" == 0 ]; then
    SRC_URL="info:skip: Nothing to copy, destination file is the same size."
    return 0
  fi

  if [ "$BYTES_TO_COPY" -lt 0 ]; then
    echo D: "Destination seems larger ($DEST_SZ bytes) than source" \
      "($SRC_SZ bytes), keep content." | numthsep >&2
    return 0
  fi

  # Only copy if there are bytes missing: This way, read-only files
  # on un-chmod-able file systems can be skipped if already copied,
  # allowing to resume with the next ones instead of failing.
  [ "$BYTES_TO_COPY" -ge "$MIN_COPY_BYTES" ] || return 4$(
    echo E: "Unsupported number in BYTES_TO_COPY='$BYTES_TO_COPY'." \
      'This error is about control flow or math.' >&2)

  copy_file__check_preserve_disk_space || return $?
  copy_file__create_dest || return $?
  CURL_RV=0
  if [ "$SRC_SZ:$BYTES_TO_COPY" == 0:0 ]; then
    echo 'Created. (Source file is empty.)'
    return 0
  fi

  local SRC_URL="file://$(readlink -m "$SRC_FN" | curl_defuse_glob_chars)"
  # SRC_URL+='{#}'
  copy_file__core_download || return $?
}


function copy_file__create_dest () {
  if [ ! -e "$DEST_FN" ]; then
    >>"$DEST_FN"
  fi
  [ -f "$DEST_FN" ] || return 4$(echo E: >&2 \
    "Destination is not a regular file even after creating it: $DEST_FN")
  grant_temp_write "$DEST_FN" || return $?
}


function copy_file__core_download () {
  # echo " url: $SRC_URL"
  "${CURL_CMD[@]}" --output "$DEST_FN" "$SRC_URL"
  CURL_RV=$?
  return 0
}


function copy_file__check_preserve_disk_space () {
  [ "$PRESERVE_DISK_SPACE" == 0 ] && return 0
  local BEFORE=
  # Unfortunately, "stat" cannot internally multiply the number of free
  # blocks with the fundamental block size, so instead we let it print
  # the formula and then have "let" calculate it.
  BEFORE="$(c_stat --file-system --format='%a*%S' -- "$DEST_DIR"/)"
  case "$BEFORE" in
    *[0-9]'*?' )
      # Reporting of fundamental block size isn't implemented, e.g. in sshfs
      BEFORE="$(df --block-size=1 --output=avail -- .)"
      BEFORE="${BEFORE//[^0-9]}";;
  esac
  let BEFORE="${BEFORE:--1}"
  [ "$BEFORE" -ge 0 ] || return 4$(
    echo E: "Failed to measure free disk space before copying" >&2)
  local AFTER="$(( BEFORE - BYTES_TO_COPY ))"
  local MISS="$(( PRESERVE_DISK_SPACE - AFTER ))"
  [ "$MISS" -lt 0 ] && MISS=0
  # ^-- We could just use -le in the next statement, but allowing a negative
  #     number of missing bytes would needlessly confuse future readers.
  [ "$MISS" == 0 ] && return 0
  echo E: "Not enough disk space on destination: After copying the missing" \
    "$BYTES_TO_COPY bytes, only $AFTER" \
    "bytes would remain free on the destination," \
    "but config says to preserve at least $PRESERVE_DISK_SPACE" \
    "bytes, so we'd need $MISS more bytes." | numthsep >&2
  return 4
}


function numthsep () {
  LANG=C sed -re $':b\n''s~([0-9]+)([0-9]{3})\b~\1\x27\2~g'$'\ntb'
}


function copy_subdir () {
  echo " dir: $SRC_SUB"
  mkdir --parents -- "$DEST_ABS" || return $?
  local REAL_SRC="$(readlink -m "$SRC_ABS")"
  # local REAL_DEST="$(readlink -m "$DEST_ABS")"
  case "$REAL_SRC" in
    "$DEST_BASE_REAL" )
      echo "E: flinching rather than copying from the destination itself" >&2
      return 8;;
    "$DEST_BASE_REAL"/* )
      echo >&2 "E: flinching rather than copying from a source inside the" \
        "destination ($DEST_BASE_REAL <- …${REAL_SRC:${#DEST_BASE_REAL}})"
      return 8;;
  esac
  guard_recursion
  copy_attribs "$SRC_ABS" "$DEST_ABS" || return $?
  grant_temp_write "$DEST_ABS" || return $?
  local SUB_FILES=()
  local SUB_FILE=
  readarray -t SUB_FILES < <(ls -A1 -- "$SRC_ABS")
  for SUB_FILE in "${SUB_FILES[@]}"; do
    check_early_done && break || true
    case "$SUB_FILE" in
      . | .. ) continue;; # actually this shouldn't even have been in ls -A
    esac
    # echo " sub: $SRC_SUB/$SUB_FILE"
    copy_dive "$SRC_SUB/$SUB_FILE" || return $?
  done
  copy_attribs "$SRC_ABS" "$DEST_ABS" || return $?
}


function guard_recursion () {
  # Every few depth levels, wait a bit, to allow catching run-away recursion.
  local DEPTH="${SRC_SUB//[^\/]/}" SLOW=0
  DEPTH="${#DEPTH}"
  [ "$DEPTH" -ge 15 ] || return 0
  (( SLOW = DEPTH % 5 ))
  [ "$SLOW" == 0 ] || return 0
  echo "D: sleeping to guard against potential run-away recursion"
  sleep 0.2s
}


function c_stat () { LANG=C LANGUAGE=C stat -c "$@"; }


function curl_defuse_savefn () {
  LANG=C sed -re '
    s!\#!_!g
    # :BUG: found no way yet to preserve literal "#1" in filename
    '
}


function curl_defuse_glob_chars () {
  LANG=C sed -re '
    s!\[|\]|\{|\}|\\!\\&!g
    s!\%!%25!g
    s!\#!%23!g
    '
}


function copy_attribs () {
  local SRC_FN="$1"; shift
  local DEST_FN="$1"; shift
  local MODES="$(c_stat %A "$SRC_FN")"
  MODES="u=${MODES:1:3},g=${MODES:4:3},o=${MODES:7:3}"
  MODES="${MODES//\-/}"
  # echo chmod -v "$MODES" "$DEST_FN"
  local CHMOD_RV=
  chmod -c "$MODES" "$DEST_FN"
  CHMOD_RV=$?
  # ls -l "$SRC_FN" "$DEST_FN"
  # return $CHMOD_RV
}


function check_early_done () {
  # Assume we have a limit:
  [ -n "$N_FILES_MAX" ] || return 1
  # Assume we have reached the limit:
  [ "$N_FILES_DONE" -ge "$N_FILES_MAX" ] || return 1
  # All assumptions are met.
  echo "done: Copied enough files." \
    "($N_FILES_DONE copied, limit = $N_FILES_MAX)"
}


function copy_next_userprovided_url_http () {
  # It's actually retrofitted into…
  copy_next_userprovided_filesystem_object || return $?
}














curldircp "$@"; exit $?
