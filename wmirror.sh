#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function wmirror_cli_init () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local SELFPATH="$(readlink -m -- "$BASH_SOURCE"/..)"
  # cd -- "$SELFPATH" || return $?

  local BASEURL="$1"; shift
  case "$BASEURL" in
    http://*/ ) ;;
    https://*/ ) ;;
    * )
      echo E: 'Expected base URL to start with http:// or https://'
        'and end with a slash.' >&2
      return 4;;
  esac
  local DOMAIN= BURL_DIR=
  DOMAIN="${BASEURL#*://}"
  BURL_DIR="${DOMAIN#*/}"
  DOMAIN="${DOMAIN%%/*}"
  DOMAIN="${DOMAIN##*@}"
  local CUT_DIRS="${BURL_DIR//[^'/']/}"
  CUT_DIRS="${#CUT_DIRS}"

  # local -p
  # BASEURL=https://user:pw@us.archive.org/20/items/202302/
  # BURL_DIR=20/items/202302/
  # CUT_DIRS=3
  # DOMAIN=us.archive.org

  local DL_CMD=(
    wget
    --mirror
    --no-parent
    --no-host-directories
    --domains="$DOMAIN"
    --cut-dirs="$CUT_DIRS"
    --wait=3
    --random-wait
    "$@"
    -- "$BASEURL"
    )
  echo D: "run:$(printf -- '%q' "${DL_CMD[@]}")"
  exec "${DL_CMD[@]}" || return $?
}










wmirror_cli_init "$@"; exit $?
