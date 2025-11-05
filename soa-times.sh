#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
#
# Parse the durations for SOA (Stard of Authority) DNS records.
#
# Examples (the optional timestamp number is ignored):
#
# $ soa-times 2025062800 3600 7200 2419200 60
# Refresh:     3600 sec = 1h
# Retry:       7200 sec = 2h
# Expire:   2419200 sec = 4wk
# Minimum:       60 sec = 1m
#
# $ soa-times 1758598368 10800 3600 1209600 10800
# Refresh:    10800 sec = 3h
# Retry:       3600 sec = 1h
# Expire:   1209600 sec = 2wk
# Minimum:    10800 sec = 3h
#
# $ soa-times 6543210 86400 600 30
# Refresh:  6543210 sec = 10wk 5d 17h 33m 30s
# Retry:      86400 sec = 1d
# Expire:       600 sec = 10m
# Minimum:       30 sec = 30s


function soa_times () {
  set -- $(echo "$*" | grep -woPe '\d+')
  [ "$#" == 5 ] && shift
  local SLOTS=( Refresh Retry Expire Minimum )
  [ "$#" == "${#SLOTS[@]}" ] || return 2$(echo E: >&2 \
    "Expected exactly ${#SLOTS[@]} numbers as arguments: ${SLOTS[*]}" >&2)
  local SLOT= TIME_SEC= WEEKS= DAYS= HMS=
  local SEC_PER_DAY=$(( 24 * 60 * 60 ))
  for SLOT in "${SLOTS[@]}"; do
    TIME_SEC="$1"; shift
    printf '%- 8s % 8s sec = ' "$SLOT:" "$TIME_SEC"
    (( DAYS = TIME_SEC / SEC_PER_DAY ))
    (( WEEKS = DAYS / 7 ))
    [ "$WEEKS" == 0 ] || WEEKS+='wk'
    (( DAYS %= 7 ))
    [ "$DAYS" == 0 ] || DAYS+='d'
    TZ=UTC printf -v HMS -- '%( %Hh  %Mm  %Ss  )T' "$TIME_SEC"
    HMS="${HMS// 0/ }"
    HMS="${HMS// 0[a-z] /}"
    echo ${WEEKS%0} ${DAYS%0} $HMS
  done
}


soa_times "$@"; exit $?
