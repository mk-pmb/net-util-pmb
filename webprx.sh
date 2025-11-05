#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function webprx_cli_main () {
  local INVOKED_AS="$(basename -- "$0" .sh)"
  local ALIAS="$INVOKED_AS"
  ALIAS="${ALIAS%proxy}"
  ALIAS="${ALIAS%prx}"
  ALIAS="${ALIAS%-}"
  ALIAS="${ALIAS%_}"
  local E='E: webprx:'
  local PRX=
  [ -z "$ALIAS" ] || PRX="$(webprx_lookup_alias "$ALIAS")"
  case "$1" in
    *:[1-9]* | *://* )
      [ -z "$PRX" ] || return 4$(echo $E >&2 \
        "Alias '$ALIAS' was found in /etc/hosts and designates '$PRX'," \
        "but the first CLI argument ('$1') also looks like a proxy." \
        "Cannot use both.")
      PRX="$1"
      shift;;
  esac
  [ -n "$PRX" ] || return 4$(echo $E >&2 \
    "No proxy given and cannot find proxy alias '$ALIAS' in /etc/hosts.")

  [[ "$PRX" == *://* ]] || PRX="http://${PRX%/}/"

  local VAR= EXPO='export'
  [ "$#" == 0 ] && EXPO='echo'
  for VAR in http{,s}; do
    VAR+='_proxy'
    $EXPO "$VAR=$PRX"
    $EXPO "${VAR^^}=$PRX"
  done

  exec "$@" || return $?$(echo $E >&2 "Failed to exec command: $*")
}


function webprx_lookup_alias () {
  DOC='''
  Look up proxy aliases in /etc/hosts.

  This is done with a marker "# proxy-alias:" which can be either at the end
  of a host line or in a separate line before host line. After the marker,
  there can be any number of words (i.e. consecutive non-whitespace) separated
  by whitespace, with optional whitespace at the end.
  If the last word consists of an initial colon followed by a non-zero digit
  and optional additional digits, it is considered the proxy port number.
  Whitespace after the port number is optional and discouraged.

  Example:
    | # proxy-alias: pvx :8118
    | 127.0.0.1   privoxy.proxy.lan
  or:
    | 127.0.0.1   privoxy.proxy.lan     # proxy-alias: pvx   :8118

  ''' :

  local ALIAS="$1"
  [ -n "$ALIAS" ] || return 0
  local ALIASES='
    s~# proxy-alias:\s*~\n~
    /\n/{
      /^\s*\n/{
        N
        s~^\s*(\S[^\n]*)\n(.*)$~\2\n\1~
      }
      s~^\s+~~
      s~^[0-9.]+\s+~\n~
      /^\n/!b
      s~^\n~~
      s~:~ &~g
      s~[\t ]+~ ~g
      s~\s*\n\s*~\t ~
      s~$~ ~
      p
    }'
  ALIASES="$(echo "$ALIASES" | sed -nrf - -- /etc/hosts)"
  local FOUND="$(echo "$ALIASES" | cut -sf 2- | grep -nFe " $ALIAS ")"
  FOUND="${FOUND%%:*}"
  [ -n "$FOUND" ] || return 2
  FOUND="$(echo "$ALIASES" | sed -nre "$FOUND"'{s~\s+$~~;p;q}')"
  local PORT=
  [[ "${FOUND##*$'\t'}" =~ :[1-9][0-9]*$ ]] && PORT="${BASH_REMATCH[0]}"
  FOUND="${FOUND%%[$'\t ']*}"
  [ -n "$FOUND" ] && echo "$FOUND$PORT"
}










webprx_cli_main "$@"; exit $?
