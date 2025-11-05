#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function wifi_ap_macs () {
  LANG=C iwconfig 2>/dev/null | sed -nre '
    /^\S.* ESSID:"/{N;s!^(\S+) [^\n]* ESSID:"([^\n]*|$\
      )" *\n +Mode:Managed [^\n]* Access Point: ([0-9A-F:]+|$\
      ) *$!\3 \1 \2!p
    }'

  # export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  # iw dev | sed -re '/^\t?\S/s~^~.\n~; $s~$~\n.~' | sed -rf <(echo '
  #   s~^\t*~# &~
  #   s~^# \.$~.\f~
  #   s~^# \tInterface ~iface ~
  #   s~^# \t\t(addr) ~\1 ~
  #   # s~^# \t\t(ssid) ~\1 ~
  #   ') | grep -vPe '^#' | tr '\n\f' '\f\n' \
  #   | sed -nre 's~\f*iface (\S+)\faddr (\S+)\f\.\f*$~\2~p'
}










wifi_ap_macs "$@"; exit $?
