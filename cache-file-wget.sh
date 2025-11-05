#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-

function cache_file_wget () {
  local SAVE="$1"; shift
  local URL=
  local LATE_OPT=()
  local PART=
  case "$SAVE" in
    '' ) ;;

    --help )
      echo H: 'CLI args: [<destination filename> [<wget options>]] <url>'
      return 0;;

    -* )
      echo E: $FUNCNAME: >&2 \
        'CLI arg #1 (destination filename) must not start with a dash.'
      return 4;;

    *://* ) URL="${SAVE%%#*}"; SAVE='./';;

    */ )
      URL="$1"
      [[ "$URL" == *://* ]] || return 4$(echo E: "URL must contain '://'" >&2)
      shift;;
  esac

  if [ -n "$URL" ]; then
    [ "$#" -ge 1 ] || LATE_OPT+=( -- )
    LATE_OPT+=( "$URL" )
  fi

  case "$SAVE" in
    */ )
      PART="${URL%%\?*}"
      PART="${PART%/}"
      PART="${PART##*/}"
      SAVE="${SAVE#./}$PART"
      ;;
  esac

  [ -n "$SAVE" ] || return 6$(
    echo E: $FUNCNAME: 'Empty destination filename!' >&2)
  [ -s "$SAVE" ] && return 0 || true
  PART="$(dirname -- "$SAVE")/"
  PART="${PART#./}tmp.$$.$(basename -- "$SAVE").part"
  wget --output-document="$PART" "$@" "${LATE_OPT[@]}" || return $?
  local V='--verbose'
  case " $* " in
    *' -q '* | *' --quiet '* ) V=;;
  esac
  mv --no-target-directory $V -- "$PART" "$SAVE" || return $?
}


cache_file_wget "$@"; exit $?
